import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/custom_app_bar.dart';
import '../../utils/theme_provider.dart';
import '../../utils/patient_bookings_manager.dart';
import '../../utils/medical_plans_manager.dart';
import '../../utils/patient_profile_manager.dart';
import '../../utils/responsive_utils.dart';
import 'start_session_screen.dart';

/// Patient Home Screen with 4 sections
class PatientHomeScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PatientHomeScreen({super.key, this.onBack});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  late PatientBookingsManager _bookingsManager;
  late MedicalPlansManager _plansManager;
  late PatientProfileManager _profileManager;

  @override
  void initState() {
    super.initState();
    _bookingsManager = PatientBookingsManager();
    _plansManager = MedicalPlansManager();
    _profileManager = PatientProfileManager();
    _bookingsManager.addListener(_onBookingsChanged);
    _plansManager.addListener(_onPlansChanged);
    _profileManager.addListener(_onProfileChanged);
    // Ensure we get an initial snapshot even if listener is slow to fire
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bookingsManager.refresh();
    });
  }

  void _onBookingsChanged() {
    setState(() {});
  }

  void _onPlansChanged() {
    setState(() {});
  }

  void _onProfileChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _bookingsManager.removeListener(_onBookingsChanged);
    _plansManager.removeListener(_onPlansChanged);
    _profileManager.removeListener(_onProfileChanged);
    super.dispose();
  }

  // Accent color helpers: use AppTheme.cyan consistently
  Color _accentColor(bool isDark) => AppTheme.cyan;
  Color _accentAltColor(bool isDark) => AppTheme.cyan;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final patientName = globalThemeProvider.displayName.isNotEmpty
        ? globalThemeProvider.displayName
        : _profileManager.patientName;

    return Scaffold(
      appBar: CustomAppBar(title: t('Home', 'الرئيسية'), onBack: widget.onBack),
      backgroundColor: AppTheme.bg(isDark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              EdgeInsets.only(bottom: ResponsiveUtils.spacing(context, 24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section 1: Welcome Message (full-bleed)
              _buildWelcomeSection(context, isDark, patientName),

              // The rest of sections keep horizontal padding
              Padding(
                padding: ResponsiveUtils.horizontalPadding(context).copyWith(
                  top: ResponsiveUtils.verticalSpacing(context, 24),
                  bottom: ResponsiveUtils.verticalSpacing(context, 16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 2: Upcoming Bookings
                    _buildUpcomingBookingsSection(context, isDark),
                    SizedBox(
                        height: ResponsiveUtils.verticalSpacing(context, 24)),

                    // Section 3: Medical Plan
                    _buildMedicalPlanSection(context, isDark),
                    SizedBox(
                        height: ResponsiveUtils.verticalSpacing(context, 24)),

                    // Section 4: Doctor Notes
                    _buildDoctorNotesSection(context, isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection(
      BuildContext context, bool isDark, String patientName) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveUtils.padding(context, 20),
        vertical: ResponsiveUtils.verticalSpacing(context, 24),
      ),
      margin: ResponsiveUtils.horizontalPadding(context)
          .copyWith(top: 0, bottom: 0),
      // Remove fixed height to allow content to expand naturally
      // height: ResponsiveUtils.isMobile(context)
      //     ? 140
      //     : ResponsiveUtils.verticalSpacing(context, 160),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _accentColor(isDark),
            _accentAltColor(isDark),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('Welcome back,', 'أهلاً وسهلاً,'),
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, 16),
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 8)),
            Flexible(
              child: Text(
                patientName,
                style: TextStyle(
                  fontSize: ResponsiveUtils.fontSize(context, 32),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 12)),
            Text(
              t('Continue your recovery journey with us.',
                  'استمر في رحلة التعافي معنا.'),
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, 14),
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingBookingsSection(BuildContext context, bool isDark) {
    final upcomingBookings = _bookingsManager.upcomingBookings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('Upcoming Appointments', 'المواعيد القادمة'),
          style: TextStyle(
            fontSize: ResponsiveUtils.fontSize(context, 18),
            fontWeight: FontWeight.bold,
            color: AppTheme.text(isDark),
          ),
        ),
        SizedBox(height: ResponsiveUtils.spacing(context, 12)),
        if (upcomingBookings.isEmpty)
          Container(
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveUtils.spacing(context, 24),
            ),
            decoration: AppTheme.cardDeco(isDark, radius: 12),
            child: Center(
              child: Text(
                t('No upcoming appointments', 'لا توجد مواعيد قادمة'),
                style: TextStyle(
                  color: AppTheme.sub(isDark),
                  fontSize: ResponsiveUtils.fontSize(context, 14),
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: upcomingBookings.length,
            itemBuilder: (context, index) {
              final booking = upcomingBookings[index];
              return _buildBookingCard(context, booking, isDark);
            },
          ),
      ],
    );
  }

  Widget _buildBookingCard(
      BuildContext context, PatientBooking booking, bool isDark) {
    final dateFormat = DateFormat('EEE, MMM d');
    final dayFormat = DateFormat('EEEE');
    final timeFormat = DateFormat('h:mm a');
    final dayLabel = dayFormat.format(booking.dateTime);
    final dateLabel = dateFormat.format(booking.dateTime);
    final timeLabel =
        '${timeFormat.format(booking.dateTime)} - ${timeFormat.format(booking.endTime)}';

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveUtils.spacing(context, 12)),
      padding: EdgeInsets.all(ResponsiveUtils.spacing(context, 16)),
      decoration: AppTheme.cardDeco(isDark, radius: 12),
      child: Row(
        children: [
          Container(
            width: ResponsiveUtils.isMobile(context) ? 40 : 50,
            height: ResponsiveUtils.isMobile(context) ? 40 : 50,
            decoration: BoxDecoration(
              color: _accentColor(isDark).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                booking.doctorImage,
                style:
                    TextStyle(fontSize: ResponsiveUtils.fontSize(context, 24)),
              ),
            ),
          ),
          SizedBox(width: ResponsiveUtils.spacing(context, 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        booking.doctorName,
                        style: TextStyle(
                          fontSize: ResponsiveUtils.fontSize(context, 16),
                          fontWeight: FontWeight.bold,
                          color: AppTheme.text(isDark),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveUtils.spacing(context, 8),
                        vertical: ResponsiveUtils.spacing(context, 4),
                      ),
                      decoration: BoxDecoration(
                        color: (booking.status == 'cancelled'
                                ? Colors.redAccent
                                : booking.status == 'completed'
                                    ? _accentColor(isDark)
                                    : _accentAltColor(isDark))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: booking.status == 'cancelled'
                              ? Colors.redAccent.withValues(alpha: 0.6)
                              : (booking.status == 'completed'
                                      ? _accentColor(isDark)
                                      : _accentAltColor(isDark))
                                  .withValues(alpha: 0.6),
                        ),
                      ),
                      child: Text(
                        booking.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: ResponsiveUtils.fontSize(context, 11),
                          fontWeight: FontWeight.w700,
                          color: booking.status == 'cancelled'
                              ? Colors.redAccent
                              : (booking.status == 'completed'
                                  ? _accentColor(isDark)
                                  : _accentAltColor(isDark)),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 4)),
                Text(
                  booking.specialty,
                  style: TextStyle(
                    fontSize: ResponsiveUtils.fontSize(context, 12),
                    color: AppTheme.sub(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 10)),
                Wrap(
                  spacing: ResponsiveUtils.spacing(context, 8),
                  runSpacing: ResponsiveUtils.spacing(context, 6),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _infoChip(
                      context,
                      icon: Icons.event_available,
                      label: dayLabel,
                      isDark: isDark,
                    ),
                    _infoChip(
                      context,
                      icon: Icons.calendar_today,
                      label: dateLabel,
                      isDark: isDark,
                    ),
                    _infoChip(
                      context,
                      icon: Icons.access_time,
                      label: timeLabel,
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: t('Cancel booking', 'إلغاء الحجز'),
            icon: Icon(
              Icons.delete_outline,
              color: AppTheme.sub(isDark),
              size: ResponsiveUtils.iconSize(context, 20),
            ),
            onPressed: () => _confirmCancelBooking(booking),
          ),
        ],
      ),
    );
  }

  void _confirmCancelBooking(PatientBooking booking) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t('Cancel booking?', 'إلغاء الحجز؟')),
          content: Text(
            t(
              'Do you want to remove this appointment with ${booking.doctorName}?',
              'هل تريد إلغاء هذا الموعد مع ${booking.doctorName}؟',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Keep', 'ابقاء')),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _bookingsManager.cancelBooking(booking);
              },
              child: Text(
                t('Remove', 'إلغاء'),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoChip(BuildContext context,
      {required IconData icon, required String label, required bool isDark}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveUtils.spacing(context, 10),
        vertical: ResponsiveUtils.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF2F5F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE0E6ED),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: ResponsiveUtils.iconSize(context, 14),
            color: AppTheme.sub(isDark),
          ),
          SizedBox(width: ResponsiveUtils.spacing(context, 6)),
          Text(
            label,
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, 12),
              fontWeight: FontWeight.w600,
              color: AppTheme.text(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalPlanSection(BuildContext context, bool isDark) {
    // Pull the actual assigned plan from the profile manager (synced with the
    // doctor's ExerciseBuilder via Firestore). The MedicalPlansManager dummy
    // data is no longer used here.
    final planName = _profileManager.activePlanName;
    final exerciseType = _profileManager.activeExerciseType;
    final completed = _profileManager.completedSessions;
    final total = _profileManager.totalSessions;
    final progress = _profileManager.progressPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('Medical Plan', 'الخطة الطبية'),
          style: TextStyle(
            fontSize: ResponsiveUtils.fontSize(context, 18),
            fontWeight: FontWeight.bold,
            color: AppTheme.text(isDark),
          ),
        ),
        SizedBox(height: ResponsiveUtils.spacing(context, 12)),
        if (planName == null)
          Container(
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveUtils.spacing(context, 24),
            ),
            decoration: AppTheme.cardDeco(isDark, radius: 12),
            child: Center(
              child: Text(
                t('No plan assigned by your doctor yet',
                    'لم يحدد طبيبك خطة بعد'),
                style: TextStyle(
                  color: AppTheme.sub(isDark),
                  fontSize: ResponsiveUtils.fontSize(context, 14),
                ),
              ),
            ),
          )
        else
          Container(
            padding: EdgeInsets.all(ResponsiveUtils.spacing(context, 20)),
            decoration: AppTheme.cardDeco(isDark, radius: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            planName,
                            style: TextStyle(
                              fontSize: ResponsiveUtils.fontSize(context, 16),
                              fontWeight: FontWeight.bold,
                              color: AppTheme.text(isDark),
                            ),
                          ),
                          if (total > 0) ...[
                            SizedBox(height: ResponsiveUtils.spacing(context, 4)),
                            Text(
                              '${t('Session', 'الجلسة')} $completed/$total',
                              style: TextStyle(
                                fontSize: ResponsiveUtils.fontSize(context, 12),
                                color: AppTheme.sub(isDark),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (total > 0)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveUtils.spacing(context, 12),
                          vertical: ResponsiveUtils.spacing(context, 6),
                        ),
                        decoration: BoxDecoration(
                          color: _accentColor(isDark).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${progress.toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: _accentColor(isDark),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                if (total > 0) ...[
                  SizedBox(height: ResponsiveUtils.spacing(context, 16)),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      minHeight: 8,
                      backgroundColor:
                          isDark ? Colors.white12 : Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _accentColor(isDark),
                      ),
                    ),
                  ),
                ],
                SizedBox(height: ResponsiveUtils.spacing(context, 16)),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor(isDark),
                      padding: EdgeInsets.symmetric(
                        vertical: ResponsiveUtils.spacing(context, 12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StartSessionScreen(
                            planName: planName,
                            exerciseType: exerciseType,
                            onBack: () => Navigator.pop(context),
                          ),
                        ),
                      );
                    },
                    child: Text(
                      t('Start Today\'s Session', 'ابدأ جلسة اليوم'),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: ResponsiveUtils.fontSize(context, 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDoctorNotesSection(BuildContext context, bool isDark) {
    // Get doctor notes from patient data
    final doctorNotes = _profileManager.patientNotes.trim();

    // If no notes from doctor, show empty state
    if (doctorNotes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('Doctor\'s Notes', 'ملاحظات الطبيب'),
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, 18),
              fontWeight: FontWeight.bold,
              color: AppTheme.text(isDark),
            ),
          ),
          SizedBox(height: ResponsiveUtils.spacing(context, 12)),
          Container(
            padding: EdgeInsets.all(ResponsiveUtils.spacing(context, 16)),
            decoration: AppTheme.cardDeco(isDark, radius: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.note_outlined,
                  size: ResponsiveUtils.iconSize(context, 40),
                  color: AppTheme.sub(isDark).withValues(alpha: 0.5),
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                Text(
                  t('No notes yet', 'لا توجد ملاحظات بعد'),
                  style: TextStyle(
                    color: AppTheme.sub(isDark),
                    fontSize: ResponsiveUtils.fontSize(context, 14),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 6)),
                Text(
                  t('Your doctor will add notes here after reviewing your progress',
                      'سيضيف طبيبك ملاحظاته هنا بعد مراجعة تقدمك'),
                  style: TextStyle(
                    color: AppTheme.sub(isDark).withValues(alpha: 0.6),
                    fontSize: ResponsiveUtils.fontSize(context, 12),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }

    // If doctor has added notes, display them
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('Doctor\'s Notes', 'ملاحظات الطبيب'),
          style: TextStyle(
            fontSize: ResponsiveUtils.fontSize(context, 18),
            fontWeight: FontWeight.bold,
            color: AppTheme.text(isDark),
          ),
        ),
        SizedBox(height: ResponsiveUtils.spacing(context, 12)),
        Container(
          padding: EdgeInsets.all(ResponsiveUtils.spacing(context, 16)),
          decoration: AppTheme.cardDeco(isDark, radius: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin:
                    EdgeInsets.only(top: ResponsiveUtils.spacing(context, 4)),
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.cyan,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: ResponsiveUtils.spacing(context, 12)),
              Expanded(
                child: Text(
                  doctorNotes,
                  style: TextStyle(
                    color: AppTheme.text(isDark),
                    height: 1.6,
                    fontSize: ResponsiveUtils.fontSize(context, 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
