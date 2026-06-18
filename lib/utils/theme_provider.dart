import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  String _language = 'en';
  String _displayName = '';
  String _userRole = '';
  bool _isLoading = false;

  bool get isDarkMode => _isDarkMode;
  String get language => _language;
  String get displayName => _displayName;
  String get userRole => _userRole;
  bool get isLoading => _isLoading;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void setDarkMode(bool value) {
    _isDarkMode = value;
    notifyListeners();
  }

  void setLanguage(String lang) {
    _language = lang;
    notifyListeners();
  }

  void setDisplayName(String name) {
    _displayName = name.trim();
    notifyListeners();
  }

  void setUserRole(String role) {
    _userRole = role;
    notifyListeners();
  }

  /// Load user profile data from Firestore
  Future<void> loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _displayName = '';
      _userRole = '';
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Try to fetch from admins collection first (highest priority)
      final adminDoc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(user.uid)
          .get();

      if (adminDoc.exists) {
        final data = adminDoc.data()!;
        final firstName = data['firstName'] as String? ?? '';
        final lastName = data['lastName'] as String? ?? '';
        _displayName = firstName.isNotEmpty && lastName.isNotEmpty
            ? '$firstName $lastName'
            : data['fullName'] as String? ?? 'Admin';
        _userRole = 'admin';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Try to fetch from doctors collection
      final doctorDoc = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(user.uid)
          .get();

      if (doctorDoc.exists) {
        final data = doctorDoc.data()!;
        final firstName = data['firstName'] as String? ?? '';
        final lastName = data['lastName'] as String? ?? '';
        _displayName = firstName.isNotEmpty && lastName.isNotEmpty
            ? '$firstName $lastName'
            : data['fullName'] as String? ?? 'Doctor';
        
        // Check if doctor is verified
        final isVerified = data['isVerified'] as bool? ?? false;
        if (!isVerified) {
          _userRole = 'doctor_pending';
        } else {
          _userRole = 'doctor';
        }
      } else {
        // Try patients collection
        final patientDoc = await FirebaseFirestore.instance
            .collection('patients')
            .doc(user.uid)
            .get();

        if (patientDoc.exists) {
          final data = patientDoc.data()!;
          final firstName = data['firstName'] as String? ?? '';
          final lastName = data['lastName'] as String? ?? '';
          _displayName = firstName.isNotEmpty && lastName.isNotEmpty
              ? '$firstName $lastName'
              : data['fullName'] as String? ?? 'Patient';
          _userRole = 'patient';
        } else {
          _displayName = user.displayName ?? user.email?.split('@').first ?? 'User';
          _userRole = 'unknown';
        }
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
      _displayName = user.displayName ?? user.email?.split('@').first ?? 'User';
      _userRole = 'unknown';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear user data on logout
  void clearUserData() {
    _displayName = '';
    _userRole = '';
    notifyListeners();
  }
}

/// Global instance used across the app for localization helper `t()`
final ThemeProvider globalThemeProvider = ThemeProvider();

/// Set to true by DevModeService.activate() so managers skip Firestore loads.
bool appDevMode = false;

String t(String enText, String arText) {
  return globalThemeProvider.language == 'ar' ? arText : enText;
}

Color colorWithOpacity(Color color, double opacity) => color.withValues(alpha: opacity);

// ─────────────────────────────────────────────────────────────────────────────
//  DESIGN SYSTEM — matches the welcome screen palette
// ─────────────────────────────────────────────────────────────────────────────

class AppTheme {
  // ── Brand ──────────────────────────────────────────────────────────────────
  static const Color cyan      = Color(0xFF00BCD4);
  static const Color cyanLight = Color(0xFF4DD0E1);

  // ── Dark palette (mirrors welcome_screen.dart) ─────────────────────────────
  static const Color dBg   = Color(0xFF0A1628);
  static const Color dCard = Color(0xFF0F2A3F);
  static const Color dSub  = Color(0xFFB0BEC5);

  // ── Light palette ──────────────────────────────────────────────────────────
  static const Color lBg   = Color(0xFFF0F7F9);
  static const Color lCard = Color(0xFFFFFFFF);
  static const Color lText = Color(0xFF0A1628);
  static const Color lSub  = Color(0xFF546E7A);

  // ── Token helpers ──────────────────────────────────────────────────────────
  static Color bg(bool isDark)   => isDark ? dBg   : lBg;
  static Color card(bool isDark) => isDark ? dCard : lCard;
  static Color text(bool isDark) => isDark ? Colors.white : lText;
  static Color sub(bool isDark)  => isDark ? dSub  : lSub;
  static Color border(bool isDark) =>
      isDark ? cyan.withValues(alpha: 0.20) : cyan.withValues(alpha: 0.16);

  // ── Card decoration helper ─────────────────────────────────────────────────
  static BoxDecoration cardDeco(bool isDark, {double radius = 16}) =>
      BoxDecoration(
        color: card(isDark),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border(isDark)),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
      );

  // ── Full ThemeData objects ─────────────────────────────────────────────────

  static ThemeData light() => ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: cyan,
          secondary: cyanLight,
          surface: lCard,
        ),
        scaffoldBackgroundColor: lBg,
        appBarTheme: AppBarTheme(
          backgroundColor: lCard,
          foregroundColor: lText,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          iconTheme: const IconThemeData(color: cyan),
          titleTextStyle: const TextStyle(
            color: lText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        cardTheme: CardThemeData(
          color: lCard,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cyan.withValues(alpha: 0.16)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: lCard,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cyan, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 2),
          ),
          labelStyle: const TextStyle(color: lSub),
          floatingLabelStyle: const TextStyle(color: cyan),
          hintStyle: TextStyle(color: lSub.withValues(alpha: 0.7)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: cyan,
            foregroundColor: Colors.white,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: cyan,
            side: const BorderSide(color: cyan),
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        textButtonTheme:
            TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: cyan)),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: lCard,
          selectedItemColor: cyan,
          unselectedItemColor: lSub,
          elevation: 8,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: lCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: 4,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
        dividerTheme:
            DividerThemeData(color: Colors.grey.shade200, thickness: 1),
        popupMenuTheme: PopupMenuThemeData(
          color: lCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 4,
        ),
        textTheme: const TextTheme(
          titleLarge:
              TextStyle(color: lText, fontWeight: FontWeight.w700),
          titleMedium:
              TextStyle(color: lText, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: lText),
          bodyMedium: TextStyle(color: lText),
          bodySmall: TextStyle(color: lSub),
          labelLarge:
              TextStyle(color: lText, fontWeight: FontWeight.w600),
        ),
      );

  static ThemeData dark() => ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: cyan,
          secondary: cyanLight,
          surface: dCard,
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: dBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: dBg,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: cyan),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        cardTheme: CardThemeData(
          color: dCard,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cyan.withValues(alpha: 0.20)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: dCard,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cyan, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 2),
          ),
          labelStyle: const TextStyle(color: dSub),
          floatingLabelStyle: const TextStyle(color: cyan),
          hintStyle: TextStyle(color: dSub.withValues(alpha: 0.7)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: cyan,
            foregroundColor: Colors.white,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: cyan,
            side: const BorderSide(color: cyan),
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        textButtonTheme:
            TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: cyan)),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: dCard,
          selectedItemColor: cyan,
          unselectedItemColor: dSub,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: dCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
        dividerTheme:
            const DividerThemeData(color: Colors.white10, thickness: 1),
        popupMenuTheme: PopupMenuThemeData(
          color: dCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: dSub),
          labelLarge: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
      );
}
