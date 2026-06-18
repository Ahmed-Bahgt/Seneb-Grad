// =============================================================================
// DOCTOR DASHBOARD - MAIN NAVIGATION HUB
// =============================================================================
// This is the main entry point for doctor-side functionality.
// It provides bottom navigation between 5 main sections:
// 1. Home - Dashboard with summary and quick access
// 2. Availability - Manage time slots for appointments
// 3. Patients - Manage patient list and profiles
// 4. Medical Chatbot - AI assistant for medical queries
// 5. X-Ray - Upload and analyze X-ray images
// =============================================================================

import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import '../../utils/availability_manager.dart';
import '../../utils/patient_manager.dart';
import '../../utils/dev_mode_service.dart';
import 'doctor_home_screen.dart';
import 'set_availability_screen.dart';
import 'patient_management_screen.dart';
import 'xray_screen.dart';
import 'medical_chatbot_screen.dart';
import '../common/settings_screen.dart';

/// Doctor Dashboard - Main navigation hub with bottom navigation and menu
class DoctorDashboard extends StatefulWidget {
  final VoidCallback? onLogout;
  final ThemeProvider? themeProvider;
  final VoidCallback? onBackToWelcome;

  const DoctorDashboard(
      {super.key, this.onLogout, this.themeProvider, this.onBackToWelcome});

  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    if (DevModeService().isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) DevModeService().refreshDoctorData();
      });
    } else {
      _syncAllDataFromFirestore();
    }
  }

  /// Sync all doctor data from Firestore on app startup
  Future<void> _syncAllDataFromFirestore() async {
    try {
      debugPrint('[DoctorDashboard] Syncing all data from Firestore...');
      await Future.wait([
        AvailabilityManager().syncAllData(),
        PatientManager().syncAllData(),
      ]);
      debugPrint('[DoctorDashboard] All data synced successfully');
    } catch (e) {
      debugPrint('[DoctorDashboard] Error syncing data: $e');
    }
  }

  void _onNavItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  List<Widget> _getScreens() {
    return [
      DoctorHomeScreen(
          onBack: null, onNavigateToTab: _onNavItemTapped),
      SetAvailabilityScreen(onBack: () => _onNavItemTapped(0)),
      PatientManagementScreen(onBack: () => _onNavItemTapped(0)),
      const MedicalChatbotScreen(),
      XrayScreen(onBack: () => _onNavItemTapped(0)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = AppTheme.bg(isDark);
    final screens = _getScreens();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          screens[_selectedIndex],
          Positioned(
            top: 12,
            right: 12,
            child: PopupMenuButton<String>(
              color: AppTheme.card(isDark),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                if (value == 'settings') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        themeProvider: widget.themeProvider,
                        onBack: () => Navigator.pop(context),
                      ),
                    ),
                  );
                } else if (value == 'theme') {
                  widget.themeProvider?.toggleTheme();
                } else if (value == 'language') {
                  _showLanguageDialog(context);
                } else if (value == 'logout') {
                  widget.onLogout?.call();
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<String>(
                  value: 'settings',
                  child: Row(
                    children: [
                      const Icon(Icons.settings,
                          color: Color(0xFF00BCD4), size: 20),
                      const SizedBox(width: 12),
                      Text('Settings',
                          style: TextStyle(
                              color: AppTheme.text(isDark))),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'theme',
                  child: Row(
                    children: [
                      Icon(
                        widget.themeProvider?.isDarkMode == true
                            ? Icons.light_mode
                            : Icons.dark_mode,
                        color: const Color(0xFF00BCD4),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.themeProvider?.isDarkMode == true
                            ? 'Light Mode'
                            : 'Dark Mode',
                        style: TextStyle(
                            color: AppTheme.text(isDark)),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'language',
                  child: Row(
                    children: [
                      const Icon(Icons.language,
                          color: Color(0xFF00BCD4), size: 20),
                      const SizedBox(width: 12),
                      Text('Language',
                          style: TextStyle(
                              color: AppTheme.text(isDark))),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.redAccent, size: 20),
                      SizedBox(width: 12),
                      Text('Logout', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.card(isDark),
                  border: Border.all(color: const Color(0xFF00BCD4), width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.menu, color: Color(0xFF00BCD4), size: 24),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.card(isDark),
        selectedItemColor: AppTheme.cyan,
        unselectedItemColor: AppTheme.sub(isDark),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.schedule),
            label: 'Availability',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Patients',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Medical Chatbot',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt_outlined),
            label: 'X-Ray',
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card(isDark),
        title: const Text('Select Language'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('English'),
              onTap: () {
                widget.themeProvider?.setLanguage('en');
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('العربية'),
              onTap: () {
                widget.themeProvider?.setLanguage('ar');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
