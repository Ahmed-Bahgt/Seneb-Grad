// =============================================================================
// DOCTOR HOME SCREEN - DASHBOARD & OVERVIEW
// =============================================================================
// Purpose: Main dashboard showing doctor's overview and quick access
// Features:
// - Welcome message with doctor's name
// - Summary cards: Total patients, Booked appointments
// - My Patients list with progress tracking
// - Available slots quick view with edit/remove actions
// Data Sources:
// - PatientManager (shared) - Syncs with Patient Management screen
// - AvailabilityManager (shared) - Syncs with Availability screen
// =============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/custom_app_bar.dart';
import '../../utils/theme_provider.dart';
import '../../utils/availability_manager.dart';
import '../../utils/patient_manager.dart';
import '../../services/doctor_patient_chat_service.dart';

/// Doctor Home Screen
class DoctorHomeScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final Function(int)? onNavigateToTab;
  const DoctorHomeScreen({super.key, this.onBack, this.onNavigateToTab});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  final AvailabilityManager _manager = AvailabilityManager();
  final PatientManager _patientManager = PatientManager();

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onSlotsChanged);
    // Sync all data from Firestore on app start
    _syncData();
  }

  Future<void> _syncData() async {
    try {
      await _manager.syncAllData();
      await _patientManager.syncAllData();
      debugPrint('[DoctorHomeScreen] All data synced');
    } catch (e) {
      debugPrint('[DoctorHomeScreen] Error syncing data: $e');
    }
  }

  @override
  void dispose() {
    _manager.removeListener(_onSlotsChanged);
    super.dispose();
  }

  void _onSlotsChanged() {
    setState(() {});
  }

  void _removeSlot(int index) {
    _manager.removeSlot(index);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('Slot removed', 'تم حذف الموعد')),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _editSlot(int index) {
    _manager.setEditingIndex(index);
    if (widget.onNavigateToTab != null) {
      widget.onNavigateToTab!(1);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('Go to Availability tab to edit the slot',
              'انتقل إلى تبويب التوفر لتعديل الموعد')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('EEEE, MMM d, yyyy').format(date);
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Widget _buildBookedAppointmentCard(
    BuildContext context,
    BookedAppointment appointment,
    bool isDark,
  ) {
    final dateFormat = DateFormat('EEE, MMM d');
    final dayFormat = DateFormat('EEEE');
    final timeFormat = DateFormat('h:mm a');

    final dayLabel = dayFormat.format(appointment.dateTime);
    final dateLabel = dateFormat.format(appointment.dateTime);
    final timeLabel = appointment.endTime != null
        ? '${timeFormat.format(appointment.dateTime)} - ${timeFormat.format(appointment.endTime!)}'
        : timeFormat.format(appointment.dateTime);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.border(isDark),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.cyan.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (appointment.patientName ?? 'P').substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.cyan,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment.patientName ??
                      t('Unknown Patient', 'مريض غير معروف'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppTheme.text(isDark),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: AppTheme.sub(isDark),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dayLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.sub(isDark),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.event,
                      size: 14,
                      color: AppTheme.sub(isDark),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.sub(isDark),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: AppTheme.sub(isDark),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: 13,
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
          IconButton(
            icon: const Icon(Icons.check_circle_outline,
                color: Color(0xFF18B900)),
            tooltip: t('Mark as completed', 'تم الانتهاء'),
            onPressed: () => _confirmCompleteAppointment(appointment),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: t('Cancel appointment', 'إلغاء الموعد'),
            onPressed: () => _confirmCancelAppointment(appointment),
          ),
        ],
      ),
    );
  }

  void _confirmCompleteAppointment(BookedAppointment appointment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Mark as Completed?', 'وضع علامة كمكتمل؟')),
        content: Text(t(
          'Confirm that the session with ${appointment.patientName} has been completed. This will count as one completed session for the patient.',
          'قم بتأكيد اكتمال الجلسة مع ${appointment.patientName}. ستُحتسب كجلسة مكتملة للمريض.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('No', 'لا')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF18B900)),
            onPressed: () async {
              Navigator.pop(context);
              await _completeAppointment(appointment);
            },
            child: Text(t('Confirm', 'تأكيد'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _completeAppointment(BookedAppointment appointment) async {
    final doctorId = FirebaseAuth.instance.currentUser?.uid;
    if (doctorId == null) return;
    try {
      final now = FieldValue.serverTimestamp();
      // 1. Mark as completed in doctor's bookings
      await FirebaseFirestore.instance
          .collection('doctors')
          .doc(doctorId)
          .collection('bookings')
          .doc(appointment.id)
          .update({'status': 'completed', 'completedAt': now});

      // 2. Mirror to patient's bookings collection (if linked)
      if (appointment.patientId != null && appointment.patientId!.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('patients')
            .doc(appointment.patientId)
            .collection('bookings')
            .doc(appointment.id)
            .update({'status': 'completed', 'completedAt': now});

        // 3. Increment the patient's completed-session counter
        await FirebaseFirestore.instance
            .collection('patients')
            .doc(appointment.patientId)
            .update({'completedSessions': FieldValue.increment(1)});

        // Add patient to My Patients
        await PatientManager.assignPatientToDoctor(
          appointment.patientId!,
          doctorId,
          globalThemeProvider.displayName.isNotEmpty ? globalThemeProvider.displayName : 'Doctor',
        );
      }

      // 4. Refresh the doctor's patient list so progress bars update
      await PatientManager().refreshPatients();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('Session marked as completed',
                'تم وضع علامة على الجلسة كمكتملة')),
            backgroundColor: const Color(0xFF18B900),
          ),
        );
      }
    } catch (e) {
      debugPrint('[DoctorHome] Error completing appointment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('Error completing appointment',
                'خطأ في إكمال الموعد')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmCancelAppointment(BookedAppointment appointment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Cancel Appointment?', 'إلغاء الموعد؟')),
        content: Text(
          t(
            'Do you want to cancel this appointment with ${appointment.patientName}?',
            'هل تريد إلغاء هذا الموعد مع ${appointment.patientName}؟',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('No', 'لا')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await _cancelAppointment(appointment);
            },
            child: Text(
              t('Yes, Cancel', 'نعم، إلغاء'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelAppointment(BookedAppointment appointment) async {
    try {
      // Delete from doctor's bookings collection
      await FirebaseFirestore.instance
          .collection('doctors')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .collection('bookings')
          .doc(appointment.id)
          .delete();

      // Delete from patient's bookings collection if patientId exists
      if (appointment.patientId != null && appointment.patientId!.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('patients')
            .doc(appointment.patientId)
            .collection('bookings')
            .doc(appointment.id)
            .delete();
            
        final doctorId = FirebaseAuth.instance.currentUser?.uid;
        if (doctorId != null) {
          await DoctorPatientChatService().sendTextMessage(
            doctorId: doctorId,
            patientId: appointment.patientId!,
            text: t(
              'Sorry, I had to cancel our appointment on ${_formatDate(appointment.dateTime)} at ${_formatTime(TimeOfDay.fromDateTime(appointment.dateTime))}.',
              'عذراً، اضطررت لإلغاء موعدنا يوم ${_formatDate(appointment.dateTime)} الساعة ${_formatTime(TimeOfDay.fromDateTime(appointment.dateTime))}.',
            ),
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('Appointment cancelled', 'تم إلغاء الموعد')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error cancelling appointment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(t('Error cancelling appointment', 'خطأ في إلغاء الموعد')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showBookingsDialog(List<BookedAppointment> appointments, bool isDark) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bg(isDark),
          title: Text(t('Upcoming Appointments', 'المواعيد القادمة'), style: TextStyle(color: AppTheme.text(isDark))),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: appointments.length,
              itemBuilder: (context, index) {
                return _buildBookedAppointmentCard(context, appointments[index], isDark);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Close', 'إغلاق')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppBar(
          title: t('Doctor Home', 'الصفحة الرئيسية للطبيب'),
          onBack: widget.onBack),
      backgroundColor: AppTheme.bg(isDark),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Welcome Header
          Text(
            '${t('Welcome back, ', 'مرحباً بعودتك ')}${globalThemeProvider.displayName.isNotEmpty ? globalThemeProvider.displayName : t('Doctor', 'دكتور')}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.text(isDark),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t('Here\'s a quick overview of your clinic today.',
                'إليك نظرة سريعة على عيادتك اليوم.'),
            style: TextStyle(color: AppTheme.sub(isDark)),
          ),
          const SizedBox(height: 16),

          // Summary Cards
          ListenableBuilder(
            listenable: Listenable.merge([_patientManager, _manager]),
            builder: (context, _) {
              final patients = _patientManager.myPatients;
              final totalPatients = patients.length;
              final bookedAppointments = _manager.bookedAppointments
                  .where((appointment) =>
                      appointment.dateTime.isAfter(DateTime.now()) &&
                      appointment.status != 'completed')
                  .toList()
                ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
              final bookedSlots = bookedAppointments.length;

              return Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: t('Patients', 'المرضى'),
                      value: '$totalPatients',
                      color: const Color(0xFF00BCD4),
                      icon: Icons.person_outline,
                      onTap: () {
                        if (widget.onNavigateToTab != null) {
                          widget.onNavigateToTab!(2); // Navigate to My Patients tab
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: t('Booked', 'محجوز'),
                      value: '$bookedSlots',
                      color: AppTheme.cyan,
                      icon: Icons.event_available,
                      onTap: () {
                        if (bookedAppointments.isNotEmpty) {
                          _showBookingsDialog(bookedAppointments, isDark);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(t('No upcoming appointments', 'لا توجد مواعيد قادمة')),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // Booked Appointments Section
          Text(
            t('Upcoming Appointments', 'المواعيد القادمة'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.text(isDark),
            ),
          ),
          const SizedBox(height: 12),

          // Booked Appointments List
          ListenableBuilder(
            listenable: _manager,
            builder: (context, _) {
              final bookedAppointments = _manager.bookedAppointments
                  .where((appointment) =>
                      appointment.dateTime.isAfter(DateTime.now()) &&
                      appointment.status != 'completed')
                  .toList()
                ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

              if (bookedAppointments.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.card(isDark),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 40,
                          color: AppTheme.sub(isDark).withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      Text(
                        t('No upcoming appointments', 'لا توجد مواعيد قادمة'),
                        style: TextStyle(
                            color: AppTheme.sub(isDark)),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: bookedAppointments.take(3).map((appointment) {
                  return _buildBookedAppointmentCard(
                    context,
                    appointment,
                    isDark,
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 24),

          // Available Slots Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  t('Your Available Slots', 'مواعيدك المتاحة'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text(isDark),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  // Clear any editing state and navigate to availability tab
                  _manager.clearEditingIndex();
                  if (widget.onNavigateToTab != null) {
                    widget.onNavigateToTab!(1);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t('Go to Availability tab to add slots',
                            'انتقل إلى تبويب التوفر لإضافة مواعيد')),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: Text(t('Add', 'إضافة')),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00BCD4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_manager.slots.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.card(isDark),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.event_busy,
                      size: 40,
                      color: AppTheme.sub(isDark).withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  Text(
                    t('No availability slots set', 'لم يتم تعيين مواعيد متاحة'),
                    style: TextStyle(
                        color: AppTheme.sub(isDark)),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_manager.slots.length, (index) {
              final slot = _manager.slots[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.card(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.border(isDark)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.event_available,
                          color: Color(0xFF00BCD4), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(slot.date),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppTheme.text(isDark),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.access_time,
                                  size: 12,
                                  color: AppTheme.sub(isDark)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${_formatTime(slot.timeFrom)} - ${_formatTime(slot.timeTo)}',
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
                    IconButton(
                      onPressed: () => _editSlot(index),
                      icon: const Icon(Icons.edit_outlined,
                          color: Color(0xFF00BCD4), size: 20),
                      tooltip: t('Edit', 'تعديل'),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                    IconButton(
                      onPressed: () => _removeSlot(index),
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 20),
                      tooltip: t('Remove', 'حذف'),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border(isDark)),
        ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.sub(isDark))),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Text(
                    value,
                    key: ValueKey<String>(value),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}
