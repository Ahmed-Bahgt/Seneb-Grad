import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_form_field.dart';
import 'forgot_password_screen.dart';

/// Doctor Login Screen
class DoctorLoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  final VoidCallback onRegister;
  final VoidCallback onBack;
  final VoidCallback onPendingVerification;

  const DoctorLoginScreen({
    super.key,
    required this.onLoginSuccess,
    required this.onRegister,
    required this.onBack,
    required this.onPendingVerification,
  });

  @override
  State<DoctorLoginScreen> createState() => _DoctorLoginScreenState();
}

class _DoctorLoginScreenState extends State<DoctorLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );
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

    if (email.isEmpty) {
      _showSnack(t('Please enter your email.', 'يرجى إدخال البريد الإلكتروني.'));
      return;
    }

    if (!_emailRegex.hasMatch(email)) {
      _showSnack(
        t(
          'Enter a valid email format like name@example.com.',
          'أدخل بريدًا بصيغة صحيحة مثل name@example.com.',
        ),
      );
      return;
    }

    if (password.isEmpty) {
      _showSnack(t('Please enter your password.', 'يرجى إدخال كلمة المرور.'));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Load user profile data
      await globalThemeProvider.loadUserProfile();

      // Check if doctor is verified
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doctorDoc = await FirebaseFirestore.instance
            .collection('doctors')
            .doc(user.uid)
            .get();

        if (!doctorDoc.exists) {
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          _showSnack(t(
            'This account is not registered as a doctor.',
            'هذا الحساب غير مسجل كطبيب.',
          ));
          setState(() => _isLoading = false);
          return;
        }

        final data = doctorDoc.data()!;
        final isVerified = data['isVerified'] as bool? ?? false;
        final isActive  = data['isActive']  as bool? ?? true;

        if (!mounted) return;

        if (!isActive) {
          await FirebaseAuth.instance.signOut();
          _showSnack(t(
            'Your account has been disabled. Contact support.',
            'تم تعطيل حسابك. تواصل مع الدعم.',
          ));
          setState(() => _isLoading = false);
          return;
        }

        if (!isVerified) {
          widget.onPendingVerification();
          return;
        }
      }

      if (!mounted) return;
      widget.onLoginSuccess();
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found') {
        message = t('No account found with this email. Please register first.', 'لم يتم العثور على حساب. يرجى التسجيل أولاً.');
      } else if (e.code == 'wrong-password') {
        message = t('Incorrect password', 'كلمة مرور خاطئة');
      } else if (e.code == 'invalid-email') {
        message = t('Invalid email address', 'بريد إلكتروني غير صالح');
      } else if (e.code == 'invalid-credential') {
        message = t('Invalid email or password. Please check and try again.', 'بريد إلكتروني أو كلمة مرور خاطئة.');
      } else {
        message = e.message ?? t('Login failed', 'فشل تسجيل الدخول');
      }
      _showSnack(message);
    } catch (e) {
      _showSnack(t('An error occurred. Please try again.', 'حدث خطأ. يرجى المحاولة مرة أخرى.'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _openForgotPassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          roleTitle: t('Doctor', 'الطبيب'),
          accentColor: const Color(0xFF00BCD4),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: CustomAppBar(
        title: t('Doctor Login', 'تسجيل دخول الطبيب'),
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
                  Icons.medical_services_rounded,
                  size: ResponsiveUtils.iconSize(context, 80),
                  color: const Color(0xFF00BCD4),
                ),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 30)),
                Text(
                  t('Welcome Doctor', 'مرحباً دكتور'),
                  style: TextStyle(
                    fontSize: ResponsiveUtils.fontSize(context, 28),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text(isDark),
                  ),
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 10)),
                Text(
                  t('Login to manage your patients', 'تسجيل الدخول لإدارة مرضاك'),
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
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading ? null : _openForgotPassword,
                    child: Text(
                      t('Forgot password?', 'هل نسيت كلمة المرور؟'),
                      style: TextStyle(
                        color: const Color(0xFF00BCD4),
                        fontSize: ResponsiveUtils.fontSize(context, 13),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: ResponsiveUtils.verticalSpacing(context, 30)),
                SizedBox(
                  height: ResponsiveUtils.buttonHeight(context),
                  child: GradientButton(
                    text: _isLoading ? t('Logging in...', 'جاري تسجيل الدخول...') : t('Login', 'تسجيل الدخول'),
                    onPressed: _isLoading ? () {} : _handleLogin,
                  ),
                ),
                SizedBox(height: ResponsiveUtils.spacing(context, 20)),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      t('Don\'t have an account? ', 'ليس لديك حساب؟ '),
                      style: TextStyle(
                        color: AppTheme.sub(isDark),
                        fontSize: ResponsiveUtils.fontSize(context, 14),
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onRegister,
                      child: Text(
                        t('Register', 'التسجيل'),
                        style: TextStyle(
                          color: const Color(0xFF00BCD4),
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                          fontSize: ResponsiveUtils.fontSize(context, 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
