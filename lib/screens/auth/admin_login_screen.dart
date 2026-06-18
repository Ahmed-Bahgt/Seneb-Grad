import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_form_field.dart';
import '../../services/sql_service.dart';

const String _bootstrapAdminUid = 'Uk9DCjBkZcWN8R3JFXzK6w6i8aG3';

/// Admin Login Screen
class AdminLoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  final VoidCallback onBack;

  const AdminLoginScreen({
    super.key,
    required this.onLoginSuccess,
    required this.onBack,
  });

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnack(t('Please enter email and password', 'الرجاء إدخال البريد وكلمة المرور'));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final sqlService = SqlService();
      final result = await sqlService.adminLogin(email, password);

      if (result['status'] == 'success') {
        debugPrint('🔥 SQL Admin: Login successful');
        
        // Load some basic admin info into the provider (mocking for now since it's admin)
        await globalThemeProvider.loadUserProfile();
        
        if (!mounted) return;
        widget.onLoginSuccess();
      } else {
        _showSnack(t('Invalid admin credentials', 'بيانات الدخول غير صحيحة'));
      }
    } catch (e) {
      debugPrint('⚠️ SQL Admin: Login failed - $e');
      _showSnack(t('Login failed: ${e.toString()}', 'فشل تسجيل الدخول: ${e.toString()}'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: CustomAppBar(
        title: t('Admin Login', 'تسجيل دخول الإدمن'),
        onBack: widget.onBack,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: ResponsiveUtils.horizontalPadding(context).copyWith(
            top: ResponsiveUtils.verticalSpacing(context, 24),
            bottom: ResponsiveUtils.verticalSpacing(context, 24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveUtils.maxContentWidth(context),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.admin_panel_settings_rounded,
                  size: ResponsiveUtils.iconSize(context, 80),
                  color: const Color(0xFF00BCD4),
                ),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 30)),
                Text(
                  t('Welcome Admin', 'مرحباً إدمن'),
                  style: TextStyle(
                    fontSize: ResponsiveUtils.fontSize(context, 28),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text(isDark),
                  ),
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 10)),
                Text(
                  t('Login to manage the platform', 'تسجيل الدخول لإدارة المنصة'),
                  style: TextStyle(
                    fontSize: ResponsiveUtils.fontSize(context, 16),
                    color: AppTheme.sub(isDark),
                  ),
                ),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 40)),
                CustomFormField(
                  t('Email', 'البريد الإلكتروني'),
                  keyboardType: TextInputType.emailAddress,
                  controller: _emailCtrl,
                ),
                CustomFormField(
                  t('Password', 'كلمة المرور'),
                  isPassword: true,
                  obscureText: !_showPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                      color: isDark ? Colors.white54 : Colors.grey,
                    ),
                    onPressed: () {
                      setState(() => _showPassword = !_showPassword);
                    },
                  ),
                  controller: _passwordCtrl,
                ),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 30)),
                SizedBox(
                  height: ResponsiveUtils.buttonHeight(context),
                  child: GradientButton(
                    text: _isLoading ? t('Logging in...', 'جاري تسجيل الدخول...') : t('Login', 'تسجيل الدخول'),
                    onPressed: _isLoading ? () {} : _handleLogin,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String t(String enText, String arText) {
  return globalThemeProvider.language == 'ar' ? arText : enText;
}
