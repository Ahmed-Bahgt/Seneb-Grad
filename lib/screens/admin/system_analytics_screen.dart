import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';

/// System Analytics Screen - Display system statistics
class SystemAnalyticsScreen extends StatefulWidget {
  const SystemAnalyticsScreen({super.key});

  @override
  State<SystemAnalyticsScreen> createState() => _SystemAnalyticsScreenState();
}

class _SystemAnalyticsScreenState extends State<SystemAnalyticsScreen> {
  final _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        title: Text(t('System Analytics', 'الإحصائيات')),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(ResponsiveUtils.padding(context, 16)),
        child: Column(
          children: [
            _buildAnalyticsCard(
              context,
              title: t('Total Doctors', 'إجمالي الأطباء'),
              query: _firestore.collection('doctors'),
              icon: Icons.medical_services_rounded,
              color: const Color(0xFF00BCD4),
              isDark: isDark,
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 16)),
            _buildAnalyticsCard(
              context,
              title: t('Pending Doctors', 'أطباء قيد الانتظار'),
              query: _firestore
                  .collection('doctors')
                  .where('isVerified', isEqualTo: false)
                  .where('approvalStatus', isEqualTo: 'pending'),
              icon: Icons.schedule_rounded,
              color: Colors.amber,
              isDark: isDark,
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 16)),
            _buildAnalyticsCard(
              context,
              title: t('Approved Doctors', 'أطباء موافق عليهم'),
              query: _firestore
                  .collection('doctors')
                  .where('isVerified', isEqualTo: true),
              icon: Icons.verified_user_rounded,
              color: Colors.green,
              isDark: isDark,
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 16)),
            _buildAnalyticsCard(
              context,
              title: t('Total Patients', 'إجمالي المرضى'),
              query: _firestore.collection('patients'),
              icon: Icons.people_rounded,
              color: const Color(0xFF4DD0E1),
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsCard(
    BuildContext context, {
    required String title,
    required Query query,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            color: isDark ? Colors.grey[900] : Colors.white,
            child: Padding(
              padding: EdgeInsets.all(ResponsiveUtils.padding(context, 20)),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
          );
        }

        final count = snapshot.data?.docs.length ?? 0;

        return Card(
          color: isDark ? Colors.grey[900] : Colors.white,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(ResponsiveUtils.padding(context, 20)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: ResponsiveUtils.fontSize(context, 16),
                            fontWeight: FontWeight.w600,
                            color: AppTheme.text(isDark),
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.all(ResponsiveUtils.spacing(context, 8)),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          icon,
                          color: color,
                          size: ResponsiveUtils.iconSize(context, 24),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveUtils.spacing(context, 12)),
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: ResponsiveUtils.fontSize(context, 40),
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String t(String enText, String arText) {
  return globalThemeProvider.language == 'ar' ? arText : enText;
}
