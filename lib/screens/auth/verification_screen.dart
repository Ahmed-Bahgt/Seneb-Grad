import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_form_field.dart';

/// Verification Screen - SMS/Email Verification
class VerificationScreen extends StatefulWidget {
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  const VerificationScreen({
    super.key,
    required this.onSubmit,
    required this.onBack,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _resendCode() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('Code resent successfully', 'تم إعادة إرسال الرمز بنجاح')),
        duration: const Duration(seconds: 2),
      ),
    );
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: CustomAppBar(
        title: t('Verification', 'التحقق'),
        onBack: widget.onBack,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(
              Icons.sms_rounded,
              size: 80,
              color: Color(0xFF00BCD4),
            ),
            const SizedBox(height: 30),
            Text(
              t('Enter Verification Code', 'أدخل رمز التحقق'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.text(isDark),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              t('We sent a code to your phone number', 'أرسلنا رمزاً إلى رقم هاتفك'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.sub(isDark),
              ),
            ),
            const SizedBox(height: 40),
            CustomFormField(
              t('Verification Code', 'رمز التحقق'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 30),
            GradientButton(
              text: t('Submit', 'إرسال'),
              onPressed: widget.onSubmit,
            ),
            const SizedBox(height: 20),
            _secondsLeft > 0
                ? Text(
                    t(
                      'Resend code in $_secondsLeft s',
                      'إعادة الإرسال خلال $_secondsLeft ث',
                    ),
                    style: TextStyle(
                      color: AppTheme.sub(isDark).withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  )
                : TextButton(
                    onPressed: _resendCode,
                    child: Text(
                      t('Resend Code', 'إعادة إرسال الرمز'),
                      style: const TextStyle(
                        color: Color(0xFF00BCD4),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
