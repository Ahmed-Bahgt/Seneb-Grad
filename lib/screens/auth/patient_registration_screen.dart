import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_form_field.dart';

/// Patient Registration Screen - Single Page
class PatientRegistrationScreen extends StatelessWidget {
  final VoidCallback onSuccess;
  final VoidCallback onReturnToLogin;
  final VoidCallback onBack;

  const PatientRegistrationScreen({
    super.key,
    required this.onSuccess,
    required this.onReturnToLogin,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: CustomAppBar(
        title: t('Patient Registration', 'تسجيل المريض'),
        onBack: onBack,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: CustomFormField(t('First Name', 'الاسم الأول'))),
                const SizedBox(width: 16),
                Expanded(child: CustomFormField(t('Last Name', 'اسم العائلة'))),
              ],
            ),
            CustomFormField(
                t('Email', 'البريد الإلكتروني'), keyboardType: TextInputType.emailAddress),
            CustomFormField(
                t('Phone Number', 'رقم الهاتف'), keyboardType: TextInputType.phone),
            CustomFormField(t('Password', 'كلمة المرور'), isPassword: true),
            CustomFormField(t('Confirm Password', 'تأكيد كلمة المرور'), isPassword: true),
            const SizedBox(height: 32),
            GradientButton(
              text: t('Register', 'التسجيل'),
              onPressed: onSuccess,
              startColor: const Color(0xFF8BC34A),
              endColor: const Color(0xFF689F38),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  t('Already have an account? ', 'هل لديك حساب بالفعل؟ '),
                  style: TextStyle(color: AppTheme.sub(isDark)),
                ),
                GestureDetector(
                  onTap: onReturnToLogin,
                  child: Text(
                    t('Login', 'تسجيل الدخول'),
                    style: const TextStyle(
                      color: Color(0xFF8BC34A),
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
