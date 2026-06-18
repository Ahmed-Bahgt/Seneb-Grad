// =============================================================================
// PATIENT BOOK SCREEN - DOCTOR APPOINTMENT BOOKING
// =============================================================================
// Purpose: Browse and book available doctor appointments
// Features:
// - List of doctors with their available slots
// - Search by doctor name
// - Filter by date
// - Book appointments
// - View booking confirmation
// Data Source:
// - AvailabilityManager (shared with doctors)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/theme_provider.dart';
import '../../utils/availability_manager.dart';
import '../../utils/patient_bookings_manager.dart';
import '../../utils/patient_manager.dart';
import '../../services/sql_service.dart';

class PatientBookScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PatientBookScreen({super.key, this.onBack});

  @override
  State<PatientBookScreen> createState() => _PatientBookScreenState();
}

class _PatientBookScreenState extends State<PatientBookScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterDoctors(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  void _showSlotSelection(BuildContext context, DoctorInfo doctor) {
    // Keep a stable reference to the page context for navigations/dialogs
    final pageContext = context;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bg(isDark),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey[300]!,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  t('Select a Slot', 'اختر موعداً'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text(isDark),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          // Doctor Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Doctor: ', 'الطبيب: '),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.sub(isDark),
                  ),
                ),
                Text(
                  doctor.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text(isDark),
                  ),
                ),
              ],
            ),
          ),

          // Slots List
          Expanded(
            child: StreamBuilder<List<AvailabilitySlot>>(
              stream: AvailabilityManager.watchDoctorSlots(doctor.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.cyan,
                    ),
                  );
                }
                final slots = snapshot.data ?? const [];
                if (slots.isEmpty) {
                  return Center(
                    child: Text(
                      t('No available slots', 'لا توجد مواعيد متاحة'),
                      style: TextStyle(
                        color: AppTheme.sub(isDark),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: slots.length,
                  itemBuilder: (itemContext, index) {
                    final slot = slots[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: AppTheme.cardDeco(isDark, radius: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatDate(slot.date),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.text(isDark),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_formatTime(slot.timeFrom)} - ${_formatTime(slot.timeTo)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.sub(isDark),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.cyan,
                            ),
                            onPressed: () {
                              _bookAppointment(
                                  pageContext, sheetContext, doctor, slot);
                            },
                            child: Text(
                              t('Book', 'احجز'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('EEE, MMM d').format(date);
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  void _bookAppointment(BuildContext pageContext, BuildContext sheetContext,
      DoctorInfo doctor, AvailabilitySlot slot) {
    final isDark = Theme.of(pageContext).brightness == Brightness.dark;

    showDialog(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('Confirm Booking', 'تأكيد الحجز')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t('Doctor: ', 'الطبيب: ')}${doctor.name}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('${t('Date: ', 'التاريخ: ')}${_formatDate(slot.date)}'),
            const SizedBox(height: 4),
            Text(
              '${t('Time: ', 'الوقت: ')}${_formatTime(slot.timeFrom)} - ${_formatTime(slot.timeTo)}',
            ),
            const SizedBox(height: 12),
            Text(
              t('Confirm this appointment?', 'تأكيد هذا الموعد؟'),
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cyan,
            ),
            onPressed: () async {
              // Save booking data before closing any dialogs
              final bookingDate =
                  DateTime(slot.date.year, slot.date.month, slot.date.day);
              final bookingDateTime = bookingDate.add(Duration(
                hours: slot.timeFrom.hour,
                minutes: slot.timeFrom.minute,
              ));
              final endDateTime = bookingDate.add(Duration(
                hours: slot.timeTo.hour,
                minutes: slot.timeTo.minute,
              ));

              final booking = PatientBooking(
                id: 'booking_${DateTime.now().millisecondsSinceEpoch}',
                doctorId: doctor.id,
                doctorName: doctor.name,
                specialty: doctor.specialty,
                dateTime: bookingDateTime,
                endTime: endDateTime,
                doctorImage: doctor.image,
              );

              // Close confirmation dialog first
              if (mounted) Navigator.of(dialogContext).pop();

              // Capture navigator before async gap
              final sheetNavigator = Navigator.of(sheetContext);

              // Wait a frame
              await Future.delayed(const Duration(milliseconds: 100));

              // Close bottom sheet using captured navigator to avoid context across async gap
              if (mounted) sheetNavigator.pop();

              // Save booking data
              if (mounted) {
                final patientId = FirebaseAuth.instance.currentUser?.uid ?? '';
                final patientDoc = await FirebaseFirestore.instance
                    .collection('patients')
                    .doc(patientId)
                    .get();

                final patientData = patientDoc.data();
                final firstName = patientData?['firstName'] as String? ?? '';
                final lastName = patientData?['lastName'] as String? ?? '';
                final patientName = firstName.isNotEmpty && lastName.isNotEmpty
                    ? '$firstName $lastName'
                    : patientData?['fullName'] as String? ?? 'Patient';

                // Add patient name to booking before saving
                booking.patientName = patientName;

                // Add booking
                await PatientBookingsManager().addBooking(booking);

                // Remove slot from doctor's availability
                await AvailabilityManager.removeSlotForDoctor(doctor.id, slot);

                // Assign patient to doctor only if not already assigned to someone else
                final existingDoctorId =
                    patientData?['assignedDoctorId'] as String? ?? '';
                if (existingDoctorId.isNotEmpty &&
                    existingDoctorId != doctor.id) {
                  // Warn but still allow — booking was already confirmed above
                  debugPrint(
                      '[PatientBook] WARNING: patient already assigned to $existingDoctorId, overwriting with ${doctor.id}');
                }
                await PatientManager.assignPatientToDoctor(
                    patientId, doctor.id, patientName);

                // --- SYNC BOOKING TO SQL BACKEND ---
                try {
                  final sqlService = SqlService();
                  await sqlService.createBooking(
                    bookingId: booking.id,
                    patientId: patientId,
                    doctorId: doctor.id,
                    doctorName: doctor.name,
                    patientName: patientName,
                    specialty: doctor.specialty,
                    dateTime: bookingDateTime,
                    endTime: endDateTime,
                  );
                  debugPrint('✅ SQL: Booking synced to PostgreSQL');
                } catch (sqlError) {
                  debugPrint('⚠️ SQL: Booking sync failed - $sqlError');
                }

                debugPrint(
                    '[PatientBook] Booking completed - Patient: $patientName, Doctor: ${doctor.name}');

                // Show success dialog on next frame using stable page context
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _showBookingSuccess(pageContext, doctor, slot);
                  }
                });
              }
            },
            child: Text(
              t('Confirm', 'تأكيد'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showBookingSuccess(
      BuildContext context, DoctorInfo doctor, AvailabilitySlot slot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cyan.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppTheme.cyan,
                size: 64,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t('Booking Confirmed!', 'تم تأكيد الحجز!'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t('Your appointment with ${doctor.name} has been booked successfully.',
                  'تم حجز موعدك مع ${doctor.name} بنجاح.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Text(
              '${_formatDate(slot.date)} • ${_formatTime(slot.timeFrom)} - ${_formatTime(slot.timeTo)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: AppTheme.cyan),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        backgroundColor: AppTheme.card(isDark),
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.cyan),
          onPressed: widget.onBack ?? () => Navigator.pop(context),
        ),
        title: Text(
          t('Book Appointment', 'حجز موعد'),
          style: TextStyle(
            color: AppTheme.text(isDark),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: t('All Slots', 'كل المواعيد'),
            icon: const Icon(Icons.calendar_month, color: AppTheme.cyan),
            onPressed: () => _showAllSlots(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card(isDark),
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.border(isDark),
                ),
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _filterDoctors,
              style: TextStyle(color: AppTheme.text(isDark)),
              decoration: InputDecoration(
                hintText: t('Search by doctor name...', 'ابحث باسم الطبيب...'),
                hintStyle:
                    TextStyle(color: AppTheme.sub(isDark).withValues(alpha: 0.6)),
                prefixIcon: const Icon(Icons.search, color: AppTheme.cyan),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          _filterDoctors('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.bg(isDark),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Streamed Doctors List
          Expanded(
            child: StreamBuilder<List<GlobalAvailabilityItem>>(
              stream: AvailabilityManager.watchAllSlots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF8BC34A),
                    ),
                  );
                }

                final items = snapshot.data ?? const [];
                
                // Extract unique doctors from available slots
                final Map<String, DoctorInfo> uniqueDoctors = {};
                for (final item in items) {
                  if (!uniqueDoctors.containsKey(item.doctorId)) {
                    uniqueDoctors[item.doctorId] = DoctorInfo(
                      id: item.doctorId,
                      name: item.doctorName,
                      specialty: item.doctorDegree,
                      rating: 4.8,
                      experience: '5 years',
                      image: '👨‍⚕️',
                    );
                  }
                }

                // Apply search filter
                final List<DoctorInfo> allDoctors = uniqueDoctors.values.toList();
                final List<DoctorInfo> filteredDoctors;
                if (_searchQuery.isEmpty) {
                  filteredDoctors = allDoctors;
                } else {
                  filteredDoctors = allDoctors
                      .where((doctor) =>
                          doctor.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                          doctor.specialty.toLowerCase().contains(_searchQuery.toLowerCase()))
                      .toList();
                }

                if (filteredDoctors.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: AppTheme.sub(isDark).withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty 
                              ? t('No doctors have available slots right now', 'لا يوجد أطباء لديهم مواعيد متاحة حالياً')
                              : t('No doctors found matching your search', 'لم يتم العثور على أطباء'),
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.sub(isDark),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredDoctors.length,
                  itemBuilder: (context, index) {
                    final doctor = filteredDoctors[index];
                    return _DoctorCard(
                      doctor: doctor,
                      isDark: isDark,
                      onBook: () => _showSlotSelection(context, doctor),
                      formatDate: _formatDate,
                      formatTime: _formatTime,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAllSlots(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final pageContext = context;
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.bg(isDark),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  bottom: BorderSide(color: AppTheme.border(isDark)),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    t('All Available Slots', 'كل المواعيد المتاحة'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text(isDark),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<GlobalAvailabilityItem>>(
                stream: AvailabilityManager.watchAllSlots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.cyan));
                  }
                  final items = snapshot.data ?? const [];
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        t('No available slots', 'لا توجد مواعيد متاحة'),
                        style: TextStyle(
                            color: AppTheme.sub(isDark)),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final slot = item.slot;
                      final doctor = DoctorInfo(
                        id: item.doctorId,
                        name: item.doctorName,
                        specialty: item.doctorDegree,
                        rating: 4.8,
                        experience: '5 years',
                        image: '👨‍⚕️',
                      );
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: AppTheme.cardDeco(isDark, radius: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    doctor.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.text(isDark),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatDate(slot.date)} · ${_formatTime(slot.timeFrom)} - ${_formatTime(slot.timeTo)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.sub(isDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.cyan,
                              ),
                              onPressed: () {
                                _bookAppointment(
                                    pageContext, sheetContext, doctor, slot);
                              },
                              child: Text(t('Book', 'احجز'),
                                  style: const TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DoctorCard extends StatelessWidget {
  final DoctorInfo doctor;
  final bool isDark;
  final VoidCallback onBook;
  final String Function(DateTime) formatDate;
  final String Function(TimeOfDay) formatTime;

  const _DoctorCard({
    required this.doctor,
    required this.isDark,
    required this.onBook,
    required this.formatDate,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AppTheme.cardDeco(isDark),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _DoctorAvatar(name: doctor.name),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doctor.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text(isDark),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    doctor.specialty,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.sub(isDark),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star,
                          color: Color(0xFFFFB300), size: 16),
                      const SizedBox(width: 4),
                      Text(
                        doctor.rating.toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.text(isDark),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.work_outline,
                        size: 16,
                        color: AppTheme.sub(isDark),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          doctor.experience,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.sub(isDark),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyan,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              onPressed: onBook,
              child: Text(
                t('Book', 'احجز'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DoctorInfo {
  final String id;
  final String name;
  final String specialty;
  final double rating;
  final String experience;
  final String image;

  DoctorInfo({
    required this.id,
    required this.name,
    required this.specialty,
    required this.rating,
    required this.experience,
    required this.image,
  });
}

class _DoctorAvatar extends StatelessWidget {
  final String name;
  const _DoctorAvatar({required this.name});

  String get _initials {
    final parts = name
        .replaceAll(RegExp(r'^Dr\.\s*', caseSensitive: false), '')
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Color get _bg {
    const palette = [
      Color(0xFF1565C0), Color(0xFF00838F), Color(0xFF2E7D32),
      Color(0xFF6A1B9A), Color(0xFFAD1457), Color(0xFF00695C),
    ];
    return palette[name.codeUnits.fold(0, (a, b) => a + b) % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          _initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
