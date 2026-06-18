import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';

/// Screen shown to doctors with pending approval status
class DoctorPendingVerificationScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onApproved; // Called when admin approves

  const DoctorPendingVerificationScreen({
    super.key,
    required this.onLogout,
    required this.onApproved,
  });

  @override
  State<DoctorPendingVerificationScreen> createState() =>
      _DoctorPendingVerificationScreenState();
}

class _DoctorPendingVerificationScreenState
    extends State<DoctorPendingVerificationScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  late Future<DocumentSnapshot> _doctorFuture;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _doctorFuture = _fetchDoctorData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<DocumentSnapshot> _fetchDoctorData() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in user');
    return _firestore.collection('doctors').doc(user.uid).get();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _doctorFuture = _fetchDoctorData());
      }
    });
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      globalThemeProvider.clearUserData();
      if (mounted) {
        widget.onLogout();
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        title: Text(t('Account Verification', 'تحقق من الحساب')),
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppTheme.bg(isDark),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _doctorFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
            );
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text(
                t('Error loading profile', 'خطأ في تحميل الملف الشخصي'),
              ),
            );
          }

          final doctorData = snapshot.data!.data() as Map<String, dynamic>?;
          if (doctorData == null) {
            return Center(
              child: Text(t('Doctor not found', 'الطبيب غير موجود')),
            );
          }

          final approvalStatus = doctorData['approvalStatus'] as String? ?? 'pending';
          final isVerified = doctorData['isVerified'] as bool? ?? false;

          // If approved, automatically navigate
          if (isVerified && approvalStatus == 'approved') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onApproved();
            });
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(ResponsiveUtils.padding(context, 20)),
            child: Column(
              children: [
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 30)),
                _buildStatusIcon(approvalStatus, isDark),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 30)),
                _buildStatusContent(approvalStatus, doctorData, isDark, context),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 40)),
                _buildDoctorInfo(doctorData, isDark, context),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 40)),
                SizedBox(
                  width: double.infinity,
                  height: ResponsiveUtils.buttonHeight(context),
                  child: ElevatedButton(
                    onPressed: _handleLogout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                    ),
                    child: Text(
                      t('Logout', 'تسجيل الخروج'),
                      style: TextStyle(
                        color: AppTheme.text(isDark),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusIcon(String status, bool isDark) {
    if (status == 'pending') {
      return Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.amber.withValues(alpha: 0.2),
        ),
        child: const Icon(
          Icons.schedule_rounded,
          size: 50,
          color: Colors.amber,
        ),
      );
    } else if (status == 'rejected') {
      return Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red.withValues(alpha: 0.2),
        ),
        child: const Icon(
          Icons.close_rounded,
          size: 50,
          color: Colors.red,
        ),
      );
    }
    return Container();
  }

  Widget _buildStatusContent(
    String status,
    Map<String, dynamic> doctorData,
    bool isDark,
    BuildContext context,
  ) {
    if (status == 'pending') {
      return Column(
        children: [
          Text(
            t('Awaiting Approval', 'في انتظار الموافقة'),
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, 24),
              fontWeight: FontWeight.bold,
              color: AppTheme.text(isDark),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveUtils.spacing(context, 16)),
          Text(
            t(
              'Your registration is under review by our admin team. Please wait 2-3 business days. You will receive a notification once approved.',
              'يتم مراجعة طلب التسجيل من قبل فريق الإدارة. يرجى الانتظار 2-3 أيام عمل. ستتلقى إشعاراً عند الموافقة.',
            ),
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, 15),
              color: AppTheme.sub(isDark),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else if (status == 'rejected') {
      final reason = doctorData['rejectionReason'] as String? ?? 'No reason provided';
      return Column(
        children: [
          Text(
            t('Application Not Approved', 'لم يتم الموافقة على الطلب'),
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, 24),
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveUtils.spacing(context, 16)),
          Text(
            t(
              'Unfortunately, your registration application was not approved at this time.',
              'للأسف، لم يتم الموافقة على طلب التسجيل في الوقت الحالي.',
            ),
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, 15),
              color: AppTheme.sub(isDark),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveUtils.spacing(context, 12)),
          Container(
            padding: EdgeInsets.all(ResponsiveUtils.padding(context, 12)),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Reason:', 'السبب:'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text(isDark),
                  ),
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 6)),
                Text(
                  reason,
                  style: TextStyle(
                    color: AppTheme.sub(isDark),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveUtils.spacing(context, 12)),
          Text(
            t(
              'You can re-register with updated information.',
              'يمكنك إعادة التسجيل بمعلومات محدثة.',
            ),
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, 14),
              color: Colors.amber[700],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return Container();
  }

  Widget _buildDoctorInfo(
    Map<String, dynamic> doctorData,
    bool isDark,
    BuildContext context,
  ) {
    final firstName = doctorData['firstName'] as String? ?? '';
    final lastName = doctorData['lastName'] as String? ?? '';
    final email = doctorData['email'] as String? ?? '';
    final degree = doctorData['degree'] as String? ?? '';

    return Container(
      padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('Your Information', 'معلوماتك'),
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, 16),
              fontWeight: FontWeight.bold,
              color: AppTheme.text(isDark),
            ),
          ),
          SizedBox(height: ResponsiveUtils.spacing(context, 12)),
          _buildInfoRow(
            label: t('Name:', 'الاسم:'),
            value: '$firstName $lastName'.trim(),
            isDark: isDark,
            context: context,
          ),
          SizedBox(height: ResponsiveUtils.spacing(context, 10)),
          _buildInfoRow(
            label: t('Email:', 'البريد:'),
            value: email,
            isDark: isDark,
            context: context,
          ),
          if (degree.isNotEmpty) ...[
            SizedBox(height: ResponsiveUtils.spacing(context, 10)),
            _buildInfoRow(
              label: t('Graduation Year:', 'سنة التخرج:'),
              value: degree,
              isDark: isDark,
              context: context,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required bool isDark,
    required BuildContext context,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.sub(isDark),
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(width: ResponsiveUtils.spacing(context, 8)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: AppTheme.text(isDark),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

String t(String enText, String arText) {
  return globalThemeProvider.language == 'ar' ? arText : enText;
}
