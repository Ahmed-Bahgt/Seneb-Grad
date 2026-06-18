import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import '../../utils/patient_bookings_manager.dart';
import '../../utils/patient_profile_manager.dart';
import 'patient_home_screen.dart';
import 'patient_book_screen.dart';
import 'nutrition_screen.dart';
import 'medical_hub_screen.dart';
import 'patient_chat_screen.dart';
// Squat live stream now accessed via dedicated page; dashboard has no extra FAB

/// Patient Dashboard - Main navigation hub with tab-based navigation
class PatientDashboard extends StatefulWidget {
  final VoidCallback? onLogout;
  final VoidCallback? onSettings;
  final ThemeProvider? themeProvider;
  final VoidCallback? onBackToWelcome;

  const PatientDashboard({
    super.key,
    this.onLogout,
    this.onSettings,
    this.themeProvider,
    this.onBackToWelcome,
  });

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  int _selectedIndex = 0;
  // Track which tabs have been opened so we only build them lazily
  final Set<int> _builtTabs = {0};

  @override
  void initState() {
    super.initState();
    _syncAllDataFromFirestore();
  }

  /// Sync all patient data from Firestore on app startup
  Future<void> _syncAllDataFromFirestore() async {
    try {
      debugPrint('[PatientDashboard] Syncing all data from Firestore...');
      await PatientBookingsManager().refresh();
      // Load patient profile including notes
      await PatientProfileManager().loadPatientProfile();
      debugPrint('[PatientDashboard] All data synced successfully');
    } catch (e) {
      debugPrint('[PatientDashboard] Error syncing data: $e');
    }
  }

  void _goToTab(int index) {
    setState(() {
      _selectedIndex = index;
      _builtTabs.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        automaticallyImplyLeading: false, // Don't show back button on dashboard root
        title: const Text('Patient Dashboard'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            onSelected: (value) {
              if (value == 'settings') {
                widget.onSettings?.call();
              } else if (value == 'logout') {
                _showLogoutDialog(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings,
                        color: AppTheme.sub(isDark)),
                    const SizedBox(width: 12),
                    Text(t('Settings', 'الإعدادات')),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.redAccent),
                    SizedBox(width: 12),
                    Text('Logout', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _builtTabs.contains(0) ? PatientHomeScreen(onBack: null) : const SizedBox.shrink(),
          _builtTabs.contains(1) ? PatientBookScreen(onBack: () => _goToTab(0)) : const SizedBox.shrink(),
          _builtTabs.contains(2) ? NutritionScreen(onBack: () => _goToTab(0)) : const SizedBox.shrink(),
          _builtTabs.contains(3) ? MedicalHubScreen(onBack: () => _goToTab(0)) : const SizedBox.shrink(),
          _builtTabs.contains(4) ? PatientChatScreen(onBack: () => _goToTab(0)) : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() {
          _builtTabs.add(index);
          _selectedIndex = index;
        }),
        backgroundColor: AppTheme.card(isDark),
        selectedItemColor: AppTheme.cyan,
        unselectedItemColor: AppTheme.sub(isDark),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: t('Home', 'الرئيسية'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.calendar_today),
            label: t('Book', 'حجز'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.restaurant_menu),
            label: t('Nutrition Bot', 'بوت التغذية'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.local_hospital_outlined),
            label: t('Medical Hub', 'المركز الطبي'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.chat_bubble_outline),
            label: t('Chat', 'المحادثة'),
          ),
        ],
      ),
      // Removed Squat Exercise FAB to keep UI focused and avoid extra buttons
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(t('Logout', 'تسجيل الخروج')),
          content: Text(
            t('Are you sure you want to logout?',
                'هل أنت متأكد أنك تريد تسجيل الخروج؟'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onLogout?.call();
              },
              child: Text(
                t('Logout', 'تسجيل الخروج'),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );
  }
}
