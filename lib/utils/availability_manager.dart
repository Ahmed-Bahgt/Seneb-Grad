import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'theme_provider.dart';
import '../services/sql_service.dart';

/// Singleton class to manage availability slots across screens
class AvailabilityManager implements Listenable {
  static final AvailabilityManager _instance = AvailabilityManager._internal();

  factory AvailabilityManager() {
    return _instance;
  }

  AvailabilityManager._internal() {
    // Initial load for current user
    _loadSlotsFromFirestore();
    _listenToBookedCount();
    _listenToBookedAppointments();
    // React to auth changes to keep slots scoped to the signed-in doctor
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (appDevMode) return;
      if (user == null) {
        // Signed out: clear any cached slots and counters
        _slots.clear();
        _bookedCount = 0;
        _bookedAppointments.clear();
        _bookedCountSub?.cancel();
        _bookedAppointmentsSub?.cancel();
        _notifyListeners();
      } else {
        // Signed in as a different doctor: reload that doctor's slots and booked appointments
        _loadSlotsFromFirestore();
        _listenToBookedCount();
        _listenToBookedAppointments();
      }
    });
  }

  final List<AvailabilitySlot> _slots = [];
  final List<VoidCallback> _listeners = [];
  // ignore: unused_field
  StreamSubscription<User?>? _authSub;
  int? _editingIndex;
  int _bookedCount = 0;
  final List<BookedAppointment> _bookedAppointments = [];
  StreamSubscription<QuerySnapshot>? _bookedCountSub;
  StreamSubscription<QuerySnapshot>? _bookedAppointmentsSub;

  List<AvailabilitySlot> get slots => List.unmodifiable(_slots);
  int? get editingIndex => _editingIndex;
  int get bookedCount => _bookedCount;
  List<BookedAppointment> get bookedAppointments =>
      List.unmodifiable(_bookedAppointments);

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Seed in-memory data for dev/test mode (no Firebase needed)
  void loadDevModeData({
    required List<AvailabilitySlot> slots,
    required List<BookedAppointment> bookedAppointments,
    required int bookedCount,
  }) {
    _bookedCountSub?.cancel();
    _bookedAppointmentsSub?.cancel();
    _slots
      ..clear()
      ..addAll(slots);
    _bookedAppointments
      ..clear()
      ..addAll(bookedAppointments);
    _bookedCount = bookedCount;
    _notifyListeners();
  }

  /// Force a manual reload (optional)
  Future<void> refresh() async => _loadSlotsFromFirestore();

  /// Ensure all slots and booked count are synced from Firestore
  Future<void> syncAllData() async {
    await _loadSlotsFromFirestore();
    await _loadBookedAppointmentsFromFirestore();
    debugPrint('[AvailabilityManager] Data synced with Firestore');
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }

  /// Listen to booked count in real-time for current doctor
  void _listenToBookedCount() {
    if (appDevMode) return;
    _bookedCountSub?.cancel();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _bookedCount = 0;
      _notifyListeners();
      return;
    }
    // Query only the doctor's own bookings collection to avoid duplicates
    _bookedCountSub = FirebaseFirestore.instance
        .collection('doctors')
        .doc(user.uid)
        .collection('bookings')
        .where('status', isNotEqualTo: 'cancelled')
        .snapshots()
        .listen((snapshot) {
      _bookedCount = snapshot.docs.length;
      _notifyListeners();
    }, onError: (e) {
      debugPrint('Error listening to booked count: $e');
      _bookedCount = 0;
      _notifyListeners();
    });
  }

  /// Listen to booked appointments in real-time for current doctor
  void _listenToBookedAppointments() {
    if (appDevMode) return;
    _bookedAppointmentsSub?.cancel();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _bookedAppointments.clear();
      _notifyListeners();
      return;
    }

    debugPrint('[AvailabilityManager] Setting up real-time listener for doctor bookings: ${user.uid}');

    // Query only the doctor's own bookings collection to avoid duplicates
    _bookedAppointmentsSub = FirebaseFirestore.instance
        .collection('doctors')
        .doc(user.uid)
        .collection('bookings')
        .where('status', isNotEqualTo: 'cancelled')
        .snapshots()
        .listen((snapshot) {
      debugPrint(
          '[AvailabilityManager] 🔥 Real-time update received: ${snapshot.docs.length} booked appointments');

      try {
        _bookedAppointments.clear();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          
          // Defensive null checks for required timestamp fields
          final dateTimeField = data['dateTime'];
          final endTimeField = data['endTime'];
          
          if (dateTimeField == null || endTimeField == null) {
            debugPrint(
                '[AvailabilityManager] ⚠️ Skipping appointment ${doc.id}: missing dateTime or endTime');
            continue;
          }
          
          final dateTime = (dateTimeField as Timestamp).toDate();
          final endTime = (endTimeField as Timestamp).toDate();

          _bookedAppointments.add(BookedAppointment(
            id: doc.id,
            doctorId: data['doctorId'] as String? ?? '',
            doctorName: data['doctorName'] as String? ?? 'Unknown Doctor',
            patientId: data['patientId'] as String? ?? '',
            patientName: data['patientName'] as String? ?? 'Patient',
            dateTime: dateTime,
            endTime: endTime,
            status: data['status'] as String? ?? 'upcoming',
          ));
        }
        _bookedAppointments.sort((a, b) => a.dateTime.compareTo(b.dateTime));
        debugPrint(
            '[AvailabilityManager] ✅ Real-time update complete: ${_bookedAppointments.length} booked appointments');
        _notifyListeners();
      } catch (e) {
        debugPrint(
            '[AvailabilityManager] ❌ Error processing booked appointments update: $e');
      }
    }, onError: (e) {
      debugPrint('[AvailabilityManager] ❌ Real-time listener error for bookings: $e');
    });
  }

  /// Load booked appointments from Firestore for current doctor
  Future<void> _loadBookedAppointmentsFromFirestore() async {
    if (appDevMode) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _bookedAppointments.clear();
      return;
    }

    try {
      // Query only the doctor's own bookings collection to avoid duplicates
      final snapshot = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(user.uid)
          .collection('bookings')
          .where('status', isNotEqualTo: 'cancelled')
          .get();

      _bookedAppointments.clear();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final dateTime = (data['dateTime'] as Timestamp).toDate();
        final endTime = (data['endTime'] as Timestamp).toDate();

        _bookedAppointments.add(BookedAppointment(
          id: doc.id,
          doctorId: data['doctorId'] as String? ?? '',
          doctorName: data['doctorName'] as String? ?? '',
          patientId: data['patientId'] as String? ?? '',
          patientName: data['patientName'] as String? ?? 'Patient',
          dateTime: dateTime,
          endTime: endTime,
          status: data['status'] as String? ?? 'upcoming',
        ));
      }
      _bookedAppointments.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      _notifyListeners();
    } catch (e) {
      debugPrint('Error loading booked appointments from Firestore: $e');
    }
  }

  /// Stream all availability slots for a given doctorId (real-time)
  static Stream<List<AvailabilitySlot>> watchDoctorSlots(String doctorId) {
    return FirebaseFirestore.instance
        .collection('doctors')
        .doc(doctorId)
        .collection('availability_slots')
        .snapshots()
        .map((snapshot) {
      final slots = snapshot.docs.map((doc) {
        final data = doc.data();
        final date = (data['date'] as Timestamp).toDate();
        final timeFromHour   = (data['timeFromHour']   as num?)?.toInt() ?? 0;
        final timeFromMinute = (data['timeFromMinute'] as num?)?.toInt() ?? 0;
        final timeToHour     = (data['timeToHour']     as num?)?.toInt() ?? 0;
        final timeToMinute   = (data['timeToMinute']   as num?)?.toInt() ?? 0;
        return AvailabilitySlot(
          date: date,
          timeFrom: TimeOfDay(hour: timeFromHour, minute: timeFromMinute),
          timeTo: TimeOfDay(hour: timeToHour, minute: timeToMinute),
        );
      }).toList();
      slots.sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return a.timeFrom.hour * 60 +
            a.timeFrom.minute -
            (b.timeFrom.hour * 60 + b.timeFrom.minute);
      });
      return slots;
    });
  }

  /// Remove a specific slot from a doctor's availability in Firestore
  static Future<void> removeSlotForDoctor(
      String doctorId, AvailabilitySlot slot) async {
    try {
      final col = FirebaseFirestore.instance
          .collection('doctors')
          .doc(doctorId)
          .collection('availability_slots');
      final snapshot = await col.get();
      bool slotRemoved = false;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final date = (data['date'] as Timestamp).toDate();
        final tfh = data['timeFromHour'] as int? ?? 0;
        final tfm = data['timeFromMinute'] as int? ?? 0;
        final tth = data['timeToHour'] as int? ?? 0;
        final ttm = data['timeToMinute'] as int? ?? 0;
        final same = date.year == slot.date.year &&
            date.month == slot.date.month &&
            date.day == slot.date.day &&
            tfh == slot.timeFrom.hour &&
            tfm == slot.timeFrom.minute &&
            tth == slot.timeTo.hour &&
            ttm == slot.timeTo.minute;
        if (same) {
          await doc.reference.delete();
          slotRemoved = true;
          break;
        }
      }

      if (slotRemoved) {
        // Note: We do NOT delete bookings here. Bookings are preserved on both
        // patient and doctor sides. The slot is simply marked as unavailable by
        // removing it from the availability_slots collection. Bookings remain
        // visible in upcoming appointments for both patient and doctor.
        debugPrint('[AvailabilityManager] Slot removed for doctor $doctorId at ${slot.date} ${slot.timeFrom}-${slot.timeTo}');
      }
    } catch (e) {
      debugPrint('Error removing doctor slot and related bookings: $e');
    }
  }

  /// Combined view: watch all doctors' availability slots via collectionGroup
  static Stream<List<GlobalAvailabilityItem>> watchAllSlots() {
    final firestore = FirebaseFirestore.instance;
    return firestore
        .collectionGroup('availability_slots')
        .snapshots()
        .asyncMap((qs) async {
      final docs = qs.docs;
      if (docs.isEmpty) return <GlobalAvailabilityItem>[];

      // Collect unique doctorIds from parent paths
      final doctorIds = <String>{};
      for (final d in docs) {
        final parentDoctor = d.reference.parent.parent;
        if (parentDoctor != null) doctorIds.add(parentDoctor.id);
      }

      // Fetch doctor records in parallel and cache names/degree
      final Map<String, Map<String, dynamic>> doctorData = {};
      await Future.wait(doctorIds.map((id) async {
        try {
          final snap = await firestore.collection('doctors').doc(id).get();
          doctorData[id] = snap.data() ?? {};
        } catch (_) {}
      }));

      final items = <GlobalAvailabilityItem>[];
      for (final doc in docs) {
        final data = doc.data();
        final parentDoctor = doc.reference.parent.parent;
        if (parentDoctor == null) continue;
        final doctorId = parentDoctor.id;
        final date = (data['date'] as Timestamp).toDate();
        final tfh = data['timeFromHour'] as int? ?? 0;
        final tfm = data['timeFromMinute'] as int? ?? 0;
        final tth = data['timeToHour'] as int? ?? 0;
        final ttm = data['timeToMinute'] as int? ?? 0;
        final slot = AvailabilitySlot(
          date: date,
          timeFrom: TimeOfDay(hour: tfh, minute: tfm),
          timeTo: TimeOfDay(hour: tth, minute: ttm),
        );

        // Only future slots
        final start = DateTime(date.year, date.month, date.day, tfh, tfm);
        if (start.isBefore(DateTime.now())) continue;

        final ddata = doctorData[doctorId] ?? {};
        final first = (ddata['firstName'] as String?) ?? '';
        final last = (ddata['lastName'] as String?) ?? '';
        final fullName = (first.isNotEmpty && last.isNotEmpty)
            ? 'Dr. $first $last'
            : (ddata['fullName'] as String?) ?? 'Dr. Unknown';
        final degree =
            (ddata['degree'] as String?) ?? 'Physiotherapy Specialist';

        items.add(GlobalAvailabilityItem(
          doctorId: doctorId,
          doctorName: fullName,
          doctorDegree: degree,
          slot: slot,
        ));
      }

      items.sort((a, b) {
        final dc = a.slot.date.compareTo(b.slot.date);
        if (dc != 0) return dc;
        return a.slot.timeFrom.hour * 60 +
            a.slot.timeFrom.minute -
            (b.slot.timeFrom.hour * 60 + b.slot.timeFrom.minute);
      });

      return items;
    });
  }

  /// Load slots from Firestore for current doctor
  Future<void> _loadSlotsFromFirestore() async {
    if (appDevMode) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[AvailabilityManager] No user logged in, skipping slot load');
      return;
    }

    try {
      debugPrint('[AvailabilityManager] Loading slots for doctor: ${user.uid}');
      final snapshot = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(user.uid)
          .collection('availability_slots')
          .get();

      _slots.clear();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final date = (data['date'] as Timestamp).toDate();
        final timeFromHour   = (data['timeFromHour']   as num?)?.toInt() ?? 0;
        final timeFromMinute = (data['timeFromMinute'] as num?)?.toInt() ?? 0;
        final timeToHour     = (data['timeToHour']     as num?)?.toInt() ?? 0;
        final timeToMinute   = (data['timeToMinute']   as num?)?.toInt() ?? 0;

        _slots.add(AvailabilitySlot(
          date: date,
          timeFrom: TimeOfDay(hour: timeFromHour, minute: timeFromMinute),
          timeTo: TimeOfDay(hour: timeToHour, minute: timeToMinute),
        ));
      }
      _sortSlots();
      debugPrint(
          '[AvailabilityManager] Loaded ${_slots.length} slots from Firestore');
      _notifyListeners();
    } catch (e) {
      debugPrint(
          '[AvailabilityManager] Error loading slots from Firestore: $e');
    }
  }

  /// Save slot to Firestore AND sync to SQL backend
  Future<void> _saveSlotsToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[AvailabilityManager] No user logged in, skipping slot save');
      return;
    }

    try {
      debugPrint(
          '[AvailabilityManager] Saving ${_slots.length} slots to Firestore for doctor: ${user.uid}');
      final docRef =
          FirebaseFirestore.instance.collection('doctors').doc(user.uid);

      // First, delete all existing slots
      final existingSlots = await docRef.collection('availability_slots').get();
      for (final doc in existingSlots.docs) {
        await doc.reference.delete();
      }

      // Then, add all current slots
      for (final slot in _slots) {
        await docRef.collection('availability_slots').add({
          'date': slot.date,
          'timeFromHour': slot.timeFrom.hour,
          'timeFromMinute': slot.timeFrom.minute,
          'timeToHour': slot.timeTo.hour,
          'timeToMinute': slot.timeTo.minute,
        });
      }
      debugPrint('[AvailabilityManager] Successfully saved slots to Firestore');

      // --- SYNC TO SQL BACKEND ---
      try {
        final sqlService = SqlService();
        // Delete old non-booked slots for this doctor
        await sqlService.deleteAllDoctorSlots(user.uid);
        // Re-create all current slots
        for (final slot in _slots) {
          final startTime = DateTime(
            slot.date.year, slot.date.month, slot.date.day,
            slot.timeFrom.hour, slot.timeFrom.minute,
          );
          final endTime = DateTime(
            slot.date.year, slot.date.month, slot.date.day,
            slot.timeTo.hour, slot.timeTo.minute,
          );
          await sqlService.createSlot(
            doctorId: user.uid,
            startTime: startTime,
            endTime: endTime,
          );
        }
        debugPrint('✅ SQL: ${_slots.length} slots synced to PostgreSQL');
      } catch (sqlError) {
        debugPrint('⚠️ SQL: Slot sync failed - $sqlError');
      }
    } catch (e) {
      debugPrint('[AvailabilityManager] Error saving slots to Firestore: $e');
    }
  }

  /// Remove a slot after booking and increment booked counter
  void bookSlot(AvailabilitySlot slot) {
    _slots.removeWhere((s) => _isSameSlot(s, slot));
    _bookedCount++;
    _saveSlotsToFirestore();
    _notifyListeners();
  }

  void addSlot(AvailabilitySlot slot) {
    _slots.add(slot);
    _sortSlots();
    _saveSlotsToFirestore();
    _notifyListeners();
  }

  void updateSlot(int index, AvailabilitySlot slot) {
    if (index >= 0 && index < _slots.length) {
      _slots[index] = slot;
      _sortSlots();
      _saveSlotsToFirestore();
      _notifyListeners();
    }
  }

  void removeSlot(int index) {
    if (index >= 0 && index < _slots.length) {
      _slots.removeAt(index);
      _saveSlotsToFirestore();
      _notifyListeners();
    }
  }

  void setEditingIndex(int index) {
    _editingIndex = index;
    _notifyListeners();
  }

  void clearEditingIndex() {
    _editingIndex = null;
    _notifyListeners();
  }

  void _sortSlots() {
    _slots.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.timeFrom.hour * 60 +
          a.timeFrom.minute -
          (b.timeFrom.hour * 60 + b.timeFrom.minute);
    });
  }

  bool _isSameSlot(AvailabilitySlot a, AvailabilitySlot b) {
    return a.date.year == b.date.year &&
        a.date.month == b.date.month &&
        a.date.day == b.date.day &&
        a.timeFrom.hour == b.timeFrom.hour &&
        a.timeFrom.minute == b.timeFrom.minute &&
        a.timeTo.hour == b.timeTo.hour &&
        a.timeTo.minute == b.timeTo.minute;
  }
}

class AvailabilitySlot {
  final DateTime date;
  final TimeOfDay timeFrom;
  final TimeOfDay timeTo;

  AvailabilitySlot({
    required this.date,
    required this.timeFrom,
    required this.timeTo,
  });
}

class GlobalAvailabilityItem {
  final String doctorId;
  final String doctorName;
  final String doctorDegree;
  final AvailabilitySlot slot;

  GlobalAvailabilityItem({
    required this.doctorId,
    required this.doctorName,
    required this.doctorDegree,
    required this.slot,
  });
}

/// Model for a booked appointment
class BookedAppointment {
  final String id;
  final String doctorId;
  final String? doctorName;
  final String? patientId;
  final String? patientName;
  final DateTime dateTime;
  final DateTime? endTime;
  final String status;

  BookedAppointment({
    required this.id,
    required this.doctorId,
    this.doctorName,
    this.patientId,
    this.patientName,
    required this.dateTime,
    this.endTime,
    required this.status,
  });
}
