import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';
import 'doctor_verification_screen.dart';
import 'user_management_screen.dart';
import 'system_analytics_screen.dart';
import 'admin_settings_screen.dart';

/// Admin Dashboard - Main admin interface with bottom navigation
class AdminDashboard extends StatefulWidget {
  final VoidCallback onLogout;
  final ThemeProvider themeProvider;

  const AdminDashboard({
    super.key,
    required this.onLogout,
    required this.themeProvider,
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const UserManagementScreen(),
    const SystemAnalyticsScreen(),
    const DoctorVerificationScreen(),
    AdminSettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        title: Text(
          t('Admin Dashboard', 'لوحة تحكم الإدمن'),
          style: TextStyle(
            fontSize: ResponsiveUtils.fontSize(context, 20),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppTheme.bg(isDark),
        actions: [
          IconButton(
            icon: Icon(Icons.logout_rounded),
            onPressed: _handleLogout,
            tooltip: t('Logout', 'تسجيل الخروج'),
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.card(isDark),
        selectedItemColor: AppTheme.cyan,
        unselectedItemColor: AppTheme.sub(isDark),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.people_rounded),
            label: t('Users', 'المستخدمون'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.bar_chart_rounded),
            label: t('Analytics', 'الإحصائيات'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.verified_user_rounded),
            label: t('Approvals', 'الموافقات'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_rounded),
            label: t('Settings', 'الإعدادات'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Confirm Logout', 'تأكيد تسجيل الخروج')),
        content: Text(t('Are you sure you want to logout?', 'هل تريد بالفعل تسجيل الخروج؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onLogout();
            },
            child: Text(t('Logout', 'تسجيل الخروج')),
          ),
        ],
      ),
    );
  }
}

String t(String enText, String arText) {
  return globalThemeProvider.language == 'ar' ? arText : enText;
}
