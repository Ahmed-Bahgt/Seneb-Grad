import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'theme_provider.dart';

/// Singleton class to manage patients across screens
class PatientManager extends ChangeNotifier {
  static final PatientManager _instance = PatientManager._internal();

  factory PatientManager() {
    return _instance;
  }

  PatientManager._internal() {
    _loadPatientsFromFirestore();
    // Ensure patient lists are scoped to the signed-in doctor
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (appDevMode) return;
      if (user == null) {
        _myPatients.clear();
        _allPatients.clear();
        notifyListeners();
      } else {
        _loadPatientsFromFirestore();
      }
    });
  }

  // Patients assigned to current doctor
  final List<PatientData> _myPatients = [];
  // All patients with accounts (available to add to care)
  final List<PatientData> _allPatients = [];
  bool _isLoading = false;
  // ignore: unused_field
  StreamSubscription<User?>? _authSub;

  bool get isLoading => _isLoading;

  /// Load both assigned and all available patients from Firestore
  Future<void> _loadPatientsFromFirestore() async {
    if (appDevMode) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _myPatients.clear();
      _allPatients.clear();
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Load all patients first
      final allSnapshot =
          await FirebaseFirestore.instance.collection('patients').get();

      _allPatients.clear();
      _myPatients.clear();

      final myPatientIds = <String>{};

      // Process all patients and separate into assigned/unassigned
      for (final doc in allSnapshot.docs) {
        final data = doc.data();
        final firstName = data['firstName'] as String? ?? '';
        final lastName = data['lastName'] as String? ?? '';
        final assignedDoctorId = data['assignedDoctorId'] as String? ?? '';
        final patientName = firstName.isNotEmpty && lastName.isNotEmpty
            ? '$firstName $lastName'
            : data['fullName'] as String? ?? 'Patient';

        final patient = PatientData(
          id: doc.id,
          name: patientName,
          diagnosis: data['diagnosis'] as String? ?? 'Rehabilitation',
          progress: ((data['progress'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
          phone: data['phone'] as String? ?? '',
          email: data['email'] as String? ?? '',
          assignedPlan: data['assignedPlan'] as String? ?? '',
          assignedMode: data['assignedMode'] as String? ?? '',
          notes: data['notes'] as String? ?? '',
          lastSession: data['lastSession'] is Timestamp ? (data['lastSession'] as Timestamp).toDate().toString().split(' ')[0] : data['lastSession']?.toString() ?? '',
          nextAppointment: data['nextAppointment'] is Timestamp ? (data['nextAppointment'] as Timestamp).toDate().toString().split(' ')[0] : data['nextAppointment']?.toString() ?? '',
          sessions: (data['sessions'] as num?)?.toInt() ?? 0,
          completedSessions: (data['completedSessions'] as num?)?.toInt() ?? 0,
          sets: (data['sets'] as num?)?.toInt() ?? 3,
          reps: (data['reps'] as num?)?.toInt() ?? 10,
          assignedDoctorId: assignedDoctorId,
          medicalHistory: MedicalHistoryData.fromMap(
            data['medicalHistory'] is Map
                ? Map<String, dynamic>.from(data['medicalHistory'] as Map)
                : null,
          ),
          prescriptions: (data['prescriptions'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((item) => TreatmentPrescription.fromMap(
                  Map<String, dynamic>.from(item)))
              .toList(),
        );

        // Check if assigned to current doctor or anyone else
        if (assignedDoctorId == user.uid) {
          // Patient assigned to current doctor - add to myPatients
          _myPatients.add(patient);
          myPatientIds.add(patient.id);
        } else if (assignedDoctorId.isEmpty) {
          // Patient unassigned - add to allPatients for discovery
          _allPatients.add(patient);
        }
        // If assigned to another doctor, don't show in either list (hidden from this doctor)
      }
    } catch (e) {
      debugPrint('Error loading patients: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Seed in-memory data for dev/test mode (no Firebase needed)
  void loadDevModeData({
    required List<PatientData> myPatients,
    required List<PatientData> allPatients,
  }) {
    _myPatients
      ..clear()
      ..addAll(myPatients);
    _allPatients
      ..clear()
      ..addAll(allPatients);
    _isLoading = false;
    notifyListeners();
  }

  /// Reload patients from Firestore
  Future<void> refreshPatients() async {
    await _loadPatientsFromFirestore();
  }

  /// Ensure all data is persisted to Firestore
  Future<void> syncAllData() async {
    await _loadPatientsFromFirestore();
    debugPrint('[PatientManager] Data synced with Firestore');
  }

  List<PatientData> get myPatients => List.unmodifiable(_myPatients);
  List<PatientData> get allPatients => List.unmodifiable(_allPatients);

  /// Add patient to current doctor's care (save to Firestore)
  Future<void> addToMyCare(PatientData patient) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Update patient document with current doctor's ID
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(patient.id)
          .update({'assignedDoctorId': user.uid});

      // Update local lists
      if (!_myPatients.any((p) => p.id == patient.id)) {
        _myPatients.add(patient.copyWith(assignedDoctorId: user.uid));
      }
      // Remove from allPatients since it's now assigned
      _allPatients.removeWhere((p) => p.id == patient.id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding patient to care: $e');
    }
  }

  /// Remove patient from current doctor's care (save to Firestore)
  Future<void> removeFromMyCare(PatientData patient) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    debugPrint(
        '[PatientManager] removeFromMyCare called for patient ${patient.id} (${patient.name}) by doctor ${user.uid}');

    if (patient.assignedDoctorId != user.uid && patient.assignedDoctorId.isNotEmpty) {
      debugPrint(
          '[PatientManager] WARNING: Doctor ${user.uid} tried to remove patient ${patient.id} who is assigned to ${patient.assignedDoctorId}. Aborting.');
      return;
    }

    try {
      // Set assignedDoctorId to empty string in Firestore
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(patient.id)
          .update({'assignedDoctorId': ''});

      // Update local lists
      _myPatients.removeWhere((p) => p.id == patient.id);
      // Add back to allPatients since it's now unassigned
      if (!_allPatients.any((p) => p.id == patient.id)) {
        _allPatients.add(patient.copyWith(assignedDoctorId: ''));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error removing patient from care: $e');
    }
  }

  /// Auto-add patient to doctor's care when they book an appointment
  Future<void> autoAddPatientOnBooking(
      String patientId, String patientName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Check if already in myPatients
      if (_myPatients.any((p) => p.id == patientId)) return;

      // Update Firestore: set assignedDoctorId
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .update({'assignedDoctorId': user.uid});

      // Find in allPatients; if missing, fetch from Firestore for full data
      PatientData patient;
      final cached = _allPatients.where((p) => p.id == patientId);
      if (cached.isNotEmpty) {
        patient = cached.first;
      } else {
        final doc = await FirebaseFirestore.instance
            .collection('patients')
            .doc(patientId)
            .get();
        final data = doc.data() ?? {};
        final firstName = data['firstName'] as String? ?? '';
        final lastName  = data['lastName']  as String? ?? '';
        final fullName  = firstName.isNotEmpty && lastName.isNotEmpty
            ? '$firstName $lastName'
            : data['fullName'] as String? ?? patientName;
        patient = PatientData(
          id: patientId,
          name: fullName,
          diagnosis: data['diagnosis'] as String? ?? 'Rehabilitation',
          progress: ((data['progress'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
          phone: data['phone'] as String? ?? '',
          email: data['email'] as String? ?? '',
          assignedPlan: data['assignedPlan'] as String? ?? '',
          assignedMode: data['assignedMode'] as String? ?? '',
          notes: data['notes'] as String? ?? '',
          lastSession: data['lastSession'] is Timestamp ? (data['lastSession'] as Timestamp).toDate().toString().split(' ')[0] : data['lastSession']?.toString() ?? '',
          nextAppointment: data['nextAppointment'] is Timestamp ? (data['nextAppointment'] as Timestamp).toDate().toString().split(' ')[0] : data['nextAppointment']?.toString() ?? '',
          completedSessions: (data['completedSessions'] as num?)?.toInt() ?? 0,
          assignedDoctorId: user.uid,
          medicalHistory: MedicalHistoryData.fromMap(
            data['medicalHistory'] is Map
                ? Map<String, dynamic>.from(data['medicalHistory'] as Map)
                : null,
          ),
          prescriptions: (data['prescriptions'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((item) => TreatmentPrescription.fromMap(
                  Map<String, dynamic>.from(item)))
              .toList(),
        );
      }

      if (!_myPatients.any((p) => p.id == patientId)) {
        _myPatients.add(patient);
      }
      // Remove from allPatients since it's now assigned
      _allPatients.removeWhere((p) => p.id == patientId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error auto-adding patient on booking: $e');
    }
  }

  /// Static method to assign a patient to a specific doctor (called from patient's booking)
  static Future<void> assignPatientToDoctor(
      String patientId, String doctorId, String patientName) async {
    try {
      // First, check if patient already has a doctor
      final patientDoc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .get();

      if (!patientDoc.exists) {
        debugPrint('[PatientManager] Patient $patientId not found');
        return;
      }

      final currentDoctorId =
          patientDoc.data()?['assignedDoctorId'] as String? ?? '';

      // Only assign if not already assigned to this doctor
      if (currentDoctorId != doctorId) {
        await FirebaseFirestore.instance
            .collection('patients')
            .doc(patientId)
            .update({'assignedDoctorId': doctorId});

        debugPrint(
            '[PatientManager] Patient $patientId assigned to doctor $doctorId');
      } else {
        debugPrint(
            '[PatientManager] Patient $patientId already assigned to doctor $doctorId');
      }
    } catch (e) {
      debugPrint('[PatientManager] Error assigning patient to doctor: $e');
    }
  }

  Future<void> updatePatient(PatientData updatedPatient) async {
    // Update in local lists
    final myIndex = _myPatients.indexWhere((p) => p.id == updatedPatient.id);
    if (myIndex != -1) {
      _myPatients[myIndex] = updatedPatient;
    }

    final allIndex = _allPatients.indexWhere((p) => p.id == updatedPatient.id);
    if (allIndex != -1) {
      _allPatients[allIndex] = updatedPatient;
    }
    notifyListeners();

    // Save to Firestore
    try {
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(updatedPatient.id)
          .update({
        'assignedPlan': updatedPatient.assignedPlan,
        'assignedMode': updatedPatient.assignedMode,
        'notes': updatedPatient.notes,
        'sessions': updatedPatient.sessions,
        'completedSessions': updatedPatient.completedSessions,
        'sets': updatedPatient.sets,
        'reps': updatedPatient.reps,
        'progress': updatedPatient.calculatedProgress,
        'lastSession': updatedPatient.lastSession,
        'nextAppointment': updatedPatient.nextAppointment,
        'medicalHistory': updatedPatient.medicalHistory.toMap(),
        'prescriptions':
            updatedPatient.prescriptions.map((item) => item.toMap()).toList(),
      });
      debugPrint('Patient ${updatedPatient.id} updated in Firestore');
    } catch (e) {
      debugPrint('Error updating patient in Firestore: $e');
    }
  }

  Future<void> saveMedicalHistory(
      PatientData patient, MedicalHistoryData history) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No authenticated doctor');
    }

    await _assertDoctorAssignedToPatient(patient.id, user.uid);
    final doctorName = await _resolveDoctorName(user.uid, user.email);
    final stamped = history.copyWith(
      updatedByDoctorId: user.uid,
      updatedByDoctorName: doctorName,
      updatedAt: DateTime.now(),
    );

    await FirebaseFirestore.instance
        .collection('patients')
        .doc(patient.id)
        .update({
      'medicalHistory': stamped.toMap(),
    });

    final myIndex = _myPatients.indexWhere((p) => p.id == patient.id);
    if (myIndex != -1) {
      _myPatients[myIndex] = _myPatients[myIndex].copyWith(
        medicalHistory: stamped,
      );
      notifyListeners();
    }
  }

  Future<void> saveTreatmentPrescription(
      PatientData patient, TreatmentPrescription draft) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No authenticated doctor');
    }

    await _assertDoctorAssignedToPatient(patient.id, user.uid);
    final doctorName = await _resolveDoctorName(user.uid, user.email);
    final now = DateTime.now();

    final patientDoc = await FirebaseFirestore.instance
        .collection('patients')
        .doc(patient.id)
        .get();
    final rawList = patientDoc.data()?['prescriptions'] as List<dynamic>? ?? [];
    final updatedPrescriptions = rawList
        .whereType<Map>()
        .map((item) =>
            TreatmentPrescription.fromMap(Map<String, dynamic>.from(item)))
        .toList();

    final existingIndex =
        updatedPrescriptions.indexWhere((item) => item.doctorId == user.uid);

    if (existingIndex >= 0) {
      final existing = updatedPrescriptions[existingIndex];
      updatedPrescriptions[existingIndex] = draft.copyWith(
        id: existing.id,
        doctorId: user.uid,
        doctorName: doctorName,
        createdAt: existing.createdAt,
        updatedAt: now,
      );
    } else {
      updatedPrescriptions.add(
        draft.copyWith(
          id: '${user.uid}_${now.millisecondsSinceEpoch}',
          doctorId: user.uid,
          doctorName: doctorName,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    await FirebaseFirestore.instance
        .collection('patients')
        .doc(patient.id)
        .update({
      'prescriptions':
          updatedPrescriptions.map((item) => item.toMap()).toList(),
    });

    final myIndex = _myPatients.indexWhere((p) => p.id == patient.id);
    if (myIndex != -1) {
      _myPatients[myIndex] = _myPatients[myIndex].copyWith(
        prescriptions: updatedPrescriptions,
      );
      notifyListeners();
    }
  }

  Future<void> _assertDoctorAssignedToPatient(
      String patientId, String doctorId) async {
    final doc = await FirebaseFirestore.instance
        .collection('patients')
        .doc(patientId)
        .get();
    if (!doc.exists) {
      throw StateError('Patient not found');
    }
    final assignedDoctorId = doc.data()?['assignedDoctorId'] as String? ?? '';
    if (assignedDoctorId != doctorId) {
      throw StateError('Doctor is not assigned to this patient');
    }
  }

  Future<String> _resolveDoctorName(
      String doctorId, String? fallbackEmail) async {
    if (globalThemeProvider.displayName.trim().isNotEmpty) {
      return globalThemeProvider.displayName.trim();
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(doctorId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        final firstName = data['firstName'] as String? ?? '';
        final lastName = data['lastName'] as String? ?? '';
        if (firstName.isNotEmpty && lastName.isNotEmpty) {
          return '$firstName $lastName';
        }
        final fullName = data['fullName'] as String? ?? '';
        if (fullName.trim().isNotEmpty) {
          return fullName.trim();
        }
      }
    } catch (_) {}

    return fallbackEmail?.split('@').first ?? 'Doctor';
  }
}

class PatientData {
  final String id;
  final String name;
  final String diagnosis;
  final double progress;
  final String phone;
  final String email;
  final String assignedPlan;
  final String assignedMode;
  final String notes;
  final String lastSession;
  final String nextAppointment;
  final String assignedDoctorId;
  final int sessions; // Total sessions set by doctor
  final int completedSessions; // Sessions completed by patient
  final int sets;
  final int reps;
  final MedicalHistoryData medicalHistory;
  final List<TreatmentPrescription> prescriptions;

  PatientData({
    required this.id,
    required this.name,
    required this.diagnosis,
    required this.progress,
    required this.phone,
    required this.email,
    required this.assignedPlan,
    required this.assignedMode,
    required this.notes,
    required this.lastSession,
    required this.nextAppointment,
    this.assignedDoctorId = '',
    this.sessions = 0,
    this.completedSessions = 0,
    this.sets = 3,
    this.reps = 10,
    MedicalHistoryData? medicalHistory,
    List<TreatmentPrescription>? prescriptions,
  })  : medicalHistory = medicalHistory ?? const MedicalHistoryData(),
        prescriptions = prescriptions ?? const [];

  /// Calculate progress based on completed sessions vs total sessions
  double get calculatedProgress {
    if (sessions <= 0) return 0.0;
    return ((completedSessions / sessions) * 100).clamp(0.0, 100.0);
  }

  PatientData copyWith({
    String? id,
    String? name,
    String? diagnosis,
    double? progress,
    String? phone,
    String? email,
    String? assignedPlan,
    String? assignedMode,
    String? notes,
    String? lastSession,
    String? nextAppointment,
    String? assignedDoctorId,
    int? sessions,
    int? completedSessions,
    int? sets,
    int? reps,
    MedicalHistoryData? medicalHistory,
    List<TreatmentPrescription>? prescriptions,
  }) {
    return PatientData(
      id: id ?? this.id,
      name: name ?? this.name,
      diagnosis: diagnosis ?? this.diagnosis,
      progress: progress ?? this.progress,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      assignedPlan: assignedPlan ?? this.assignedPlan,
      assignedMode: assignedMode ?? this.assignedMode,
      notes: notes ?? this.notes,
      lastSession: lastSession ?? this.lastSession,
      nextAppointment: nextAppointment ?? this.nextAppointment,
      assignedDoctorId: assignedDoctorId ?? this.assignedDoctorId,
      sessions: sessions ?? this.sessions,
      completedSessions: completedSessions ?? this.completedSessions,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      medicalHistory: medicalHistory ?? this.medicalHistory,
      prescriptions: prescriptions ?? this.prescriptions,
    );
  }
}

class MedicalHistoryData {
  final int? age;
  final double? heightCm;
  final double? weightKg;
  final String walkingDuration;
  final String mealsPerDay;
  final String smokingStatus;
  final String painLevel;
  final String sleepQuality;
  final String chronicConditions;
  final String medications;
  final String allergies;
  final String updatedByDoctorId;
  final String updatedByDoctorName;
  final DateTime? updatedAt;

  const MedicalHistoryData({
    this.age,
    this.heightCm,
    this.weightKg,
    this.walkingDuration = '',
    this.mealsPerDay = '',
    this.smokingStatus = '',
    this.painLevel = '',
    this.sleepQuality = '',
    this.chronicConditions = '',
    this.medications = '',
    this.allergies = '',
    this.updatedByDoctorId = '',
    this.updatedByDoctorName = '',
    this.updatedAt,
  });

  bool get isEmpty {
    return age == null &&
        heightCm == null &&
        weightKg == null &&
        walkingDuration.isEmpty &&
        mealsPerDay.isEmpty &&
        smokingStatus.isEmpty &&
        painLevel.isEmpty &&
        sleepQuality.isEmpty &&
        chronicConditions.isEmpty &&
        medications.isEmpty &&
        allergies.isEmpty &&
        updatedByDoctorId.isEmpty &&
        updatedByDoctorName.isEmpty;
  }

  Map<String, dynamic> toMap() {
    return {
      'age': age,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'walkingDuration': walkingDuration,
      'mealsPerDay': mealsPerDay,
      'smokingStatus': smokingStatus,
      'painLevel': painLevel,
      'sleepQuality': sleepQuality,
      'chronicConditions': chronicConditions,
      'medications': medications,
      'allergies': allergies,
      'updatedByDoctorId': updatedByDoctorId,
      'updatedByDoctorName': updatedByDoctorName,
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    };
  }

  factory MedicalHistoryData.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const MedicalHistoryData();

    return MedicalHistoryData(
      age: (map['age'] as num?)?.toInt(),
      heightCm: (map['heightCm'] as num?)?.toDouble(),
      weightKg: (map['weightKg'] as num?)?.toDouble(),
      walkingDuration: map['walkingDuration'] as String? ?? '',
      mealsPerDay: map['mealsPerDay'] as String? ?? '',
      smokingStatus: map['smokingStatus'] as String? ?? '',
      painLevel: map['painLevel'] as String? ?? '',
      sleepQuality: map['sleepQuality'] as String? ?? '',
      chronicConditions: map['chronicConditions'] as String? ?? '',
      medications: map['medications'] as String? ?? '',
      allergies: map['allergies'] as String? ?? '',
      updatedByDoctorId: map['updatedByDoctorId'] as String? ?? '',
      updatedByDoctorName: map['updatedByDoctorName'] as String? ?? '',
      updatedAt: _parseDateTime(map['updatedAt']),
    );
  }

  MedicalHistoryData copyWith({
    int? age,
    double? heightCm,
    double? weightKg,
    String? walkingDuration,
    String? mealsPerDay,
    String? smokingStatus,
    String? painLevel,
    String? sleepQuality,
    String? chronicConditions,
    String? medications,
    String? allergies,
    String? updatedByDoctorId,
    String? updatedByDoctorName,
    DateTime? updatedAt,
  }) {
    return MedicalHistoryData(
      age: age ?? this.age,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      walkingDuration: walkingDuration ?? this.walkingDuration,
      mealsPerDay: mealsPerDay ?? this.mealsPerDay,
      smokingStatus: smokingStatus ?? this.smokingStatus,
      painLevel: painLevel ?? this.painLevel,
      sleepQuality: sleepQuality ?? this.sleepQuality,
      chronicConditions: chronicConditions ?? this.chronicConditions,
      medications: medications ?? this.medications,
      allergies: allergies ?? this.allergies,
      updatedByDoctorId: updatedByDoctorId ?? this.updatedByDoctorId,
      updatedByDoctorName: updatedByDoctorName ?? this.updatedByDoctorName,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class TreatmentPrescription {
  final String id;
  final String doctorId;
  final String doctorName;
  final String treatmentName;
  final List<PrescriptionMedicationItem> items;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TreatmentPrescription({
    this.id = '',
    this.doctorId = '',
    this.doctorName = '',
    this.treatmentName = '',
    this.items = const [],
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  bool get isEmpty {
    return treatmentName.trim().isEmpty &&
        items.every((item) => item.isEmpty) &&
        notes.trim().isEmpty;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'doctorId': doctorId,
      'doctorName': doctorName,
      'treatmentName': treatmentName,
      'items': items.map((item) => item.toMap()).toList(),
      'notes': notes,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    };
  }

  factory TreatmentPrescription.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const TreatmentPrescription();
    final rawItems = map['items'];
    List<PrescriptionMedicationItem> items;
    if (rawItems is List) {
      items = rawItems
          .whereType<Map>()
          .map((item) => PrescriptionMedicationItem.fromMap(
              Map<String, dynamic>.from(item)))
          .toList();
    } else {
      final rawMeds = map['medications'];
      List<String> meds;
      if (rawMeds is List) {
        meds = rawMeds.whereType<String>().toList();
      } else if (map['medicationDetails'] is String &&
          (map['medicationDetails'] as String).isNotEmpty) {
        meds = [map['medicationDetails'] as String];
      } else {
        meds = [];
      }
      items = meds
          .map(
            (medication) => PrescriptionMedicationItem(
              medication: medication,
              dosage: map['dosage'] as String? ?? '',
              duration: map['duration'] as String? ?? '',
            ),
          )
          .toList();
    }
    return TreatmentPrescription(
      id: map['id'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      doctorName: map['doctorName'] as String? ?? '',
      treatmentName: map['treatmentName'] as String? ?? '',
      items: items,
      notes: map['notes'] as String? ?? '',
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
    );
  }

  TreatmentPrescription copyWith({
    String? id,
    String? doctorId,
    String? doctorName,
    String? treatmentName,
    List<PrescriptionMedicationItem>? items,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TreatmentPrescription(
      id: id ?? this.id,
      doctorId: doctorId ?? this.doctorId,
      doctorName: doctorName ?? this.doctorName,
      treatmentName: treatmentName ?? this.treatmentName,
      items: items ?? this.items,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class PrescriptionMedicationItem {
  final String medication;
  final String dosage;
  final String duration;

  const PrescriptionMedicationItem({
    this.medication = '',
    this.dosage = '',
    this.duration = '',
  });

  bool get isEmpty {
    return medication.trim().isEmpty &&
        dosage.trim().isEmpty &&
        duration.trim().isEmpty;
  }

  Map<String, dynamic> toMap() {
    return {
      'medication': medication,
      'dosage': dosage,
      'duration': duration,
    };
  }

  factory PrescriptionMedicationItem.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PrescriptionMedicationItem();
    return PrescriptionMedicationItem(
      medication: map['medication'] as String? ?? '',
      dosage: map['dosage'] as String? ?? '',
      duration: map['duration'] as String? ?? '',
    );
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
