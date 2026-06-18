import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';

/// Complaints Management Screen - Placeholder for future complaints system
class ComplaintsManagementScreen extends StatefulWidget {
  const ComplaintsManagementScreen({super.key});

  @override
  State<ComplaintsManagementScreen> createState() =>
      _ComplaintsManagementScreenState();
}

class _ComplaintsManagementScreenState extends State<ComplaintsManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        title: Text(t('Complaints - Management', 'إدارة الشكاوى')),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.report_problem_rounded,
              size: ResponsiveUtils.iconSize(context, 80),
              color: Colors.amber,
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 16)),
            Text(
              t('Complaints System', 'نظام الشكاوى'),
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, 24),
                fontWeight: FontWeight.bold,
                color: AppTheme.text(isDark),
              ),
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 8)),
            Text(
              t('Coming Soon', 'قريباً'),
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, 16),
                color: AppTheme.sub(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String t(String enText, String arText) {
  return globalThemeProvider.language == 'ar' ? arText : enText;
}
