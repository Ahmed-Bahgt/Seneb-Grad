import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/theme_provider.dart';
import '../../utils/responsive_utils.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_form_field.dart';
import '../../widgets/gradient_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String roleTitle;
  final Color accentColor;

  const ForgotPasswordScreen({
    super.key,
    required this.roleTitle,
    required this.accentColor,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const int _emailCooldownSeconds = 60;
  static const int _maxResetEmailsPerHour = 5;

  final _emailCtrl = TextEditingController();
  final Map<String, List<DateTime>> _resetRequestsByEmail = {};

  bool _sending = false;
  bool _emailSent = false;
  int _resendCooldownLeft = 0;
  Timer? _cooldownTimer;

  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) => _emailRegex.hasMatch(email);
  bool _isOnCooldown() => _resendCooldownLeft > 0;

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldownLeft = _emailCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_resendCooldownLeft <= 1) {
        timer.cancel();
        setState(() => _resendCooldownLeft = 0);
      } else {
        setState(() => _resendCooldownLeft -= 1);
      }
    });
  }

  List<DateTime> _recentAttemptsForEmail(String email) {
    final normalized = email.toLowerCase();
    final attempts = _resetRequestsByEmail.putIfAbsent(normalized, () => []);
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    attempts.removeWhere((a) => a.isBefore(cutoff));
    return attempts;
  }

  bool _hasReachedHourlyLimit(String email) =>
      _recentAttemptsForEmail(email).length >= _maxResetEmailsPerHour;

  void _recordAttempt(String email) =>
      _recentAttemptsForEmail(email).add(DateTime.now());

  Future<void> _sendResetEmail() async {
    final email = _emailCtrl.text.trim();

    if (_isOnCooldown()) {
      _showSnack(t(
        'Please wait $_resendCooldownLeft seconds before requesting again.',
        'يرجى الانتظار $_resendCooldownLeft ثانية قبل إعادة الطلب.',
      ));
      return;
    }
    if (email.isEmpty) {
      _showSnack(t('Please enter your email address.', 'يرجى إدخال البريد الإلكتروني.'));
      return;
    }
    if (!_isValidEmail(email)) {
      _showSnack(t(
        'Enter a valid email format like name@example.com.',
        'أدخل بريدًا بصيغة صحيحة مثل name@example.com.',
      ));
      return;
    }
    if (_hasReachedHourlyLimit(email)) {
      _showSnack(t(
        'Too many reset requests for this email. Please try again after one hour.',
        'طلبات إعادة التعيين كثيرة على هذا البريد. يرجى المحاولة بعد ساعة.',
      ));
      return;
    }

    setState(() => _sending = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _recordAttempt(email);
      _startCooldown();
      if (!mounted) return;
      setState(() => _emailSent = true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnack(_mapFirebaseError(e.code));
    } catch (_) {
      if (!mounted) return;
      _showSnack(t('An error occurred. Please try again.', 'حدث خطأ. يرجى المحاولة مرة أخرى.'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'user-not-found':
      case 'invalid-email':
        return t(
          'No account found with this email address.',
          'لا يوجد حساب مرتبط بهذا البريد الإلكتروني.',
        );
      case 'too-many-requests':
        return t(
          'Too many requests. Please wait a moment and try again.',
          'طلبات كثيرة. يرجى الانتظار والمحاولة مرة أخرى.',
        );
      default:
        return t('An error occurred. Please try again.', 'حدث خطأ. يرجى المحاولة مرة أخرى.');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: CustomAppBar(
        title: t('Forgot Password', 'نسيت كلمة المرور'),
        onBack: () => Navigator.of(context).pop(),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: ResponsiveUtils.horizontalPadding(context).copyWith(
            top: ResponsiveUtils.verticalSpacing(context, 20),
            bottom: ResponsiveUtils.verticalSpacing(context, 20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ResponsiveUtils.maxContentWidth(context)),
            child: _emailSent ? _buildSuccessView(isDark) : _buildFormView(isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView(bool isDark) {
    final cardColor = AppTheme.card(isDark);
    final borderColor = AppTheme.border(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Icon header
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: widget.accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_reset_rounded, size: 36, color: widget.accentColor),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            t('Reset your password', 'إعادة تعيين كلمة المرور'),
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, 18),
              fontWeight: FontWeight.w700,
              color: AppTheme.text(isDark),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Steps card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('How it works:', 'كيف تعمل العملية:'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: ResponsiveUtils.fontSize(context, 13),
                  color: widget.accentColor,
                ),
              ),
              const SizedBox(height: 10),
              _StepRow(
                number: '1',
                color: widget.accentColor,
                icon: Icons.alternate_email_rounded,
                text: t('Enter your account email below', 'أدخل بريد حسابك في الحقل أدناه'),
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _StepRow(
                number: '2',
                color: widget.accentColor,
                icon: Icons.send_rounded,
                text: t('We send you a reset link instantly', 'سنرسل لك رابط إعادة التعيين فورًا'),
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _StepRow(
                number: '3',
                color: widget.accentColor,
                icon: Icons.mail_outline_rounded,
                text: t('Open the email and tap the link', 'افتح الإيميل واضغط على الرابط'),
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _StepRow(
                number: '4',
                color: widget.accentColor,
                icon: Icons.lock_open_rounded,
                text: t('Set your new password', 'قم بتعيين كلمة مرور جديدة'),
                isDark: isDark,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Email field
        CustomFormField(
          t('Email', 'البريد الإلكتروني'),
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),

        // Send button
        SizedBox(
          height: ResponsiveUtils.buttonHeight(context),
          child: GradientButton(
            text: _sending
                ? t('Sending...', 'جارٍ الإرسال...')
                : (_isOnCooldown()
                    ? t('Retry in $_resendCooldownLeft s', 'إعادة المحاولة خلال $_resendCooldownLeft ث')
                    : t('Send Reset Link', 'إرسال رابط إعادة التعيين')),
            onPressed: (_sending || _isOnCooldown()) ? () {} : _sendResetEmail,
            startColor: widget.accentColor,
            endColor: widget.accentColor.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView(bool isDark) {
    final cardColor = AppTheme.card(isDark);
    final borderColor = AppTheme.border(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success icon
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mark_email_read_outlined, size: 36, color: Colors.green),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            t('Email sent!', 'تم إرسال الإيميل!'),
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, 18),
              fontWeight: FontWeight.w700,
              color: AppTheme.text(isDark),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            _emailCtrl.text.trim(),
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, 13),
              color: widget.accentColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Next steps card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('Next steps:', 'الخطوات التالية:'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: ResponsiveUtils.fontSize(context, 13),
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 10),
              _StepRow(
                number: '1',
                color: Colors.green,
                icon: Icons.inbox_rounded,
                text: t('Open your email inbox', 'افتح صندوق الوارد في بريدك'),
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _StepRow(
                number: '2',
                color: Colors.green,
                icon: Icons.touch_app_rounded,
                text: t('Tap the reset link in the email', 'اضغط على رابط إعادة التعيين'),
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _StepRow(
                number: '3',
                color: Colors.green,
                icon: Icons.lock_open_rounded,
                text: t('Create a strong new password', 'أنشئ كلمة مرور جديدة قوية'),
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _StepRow(
                number: '4',
                color: Colors.green,
                icon: Icons.login_rounded,
                text: t('Come back and log in', 'ارجع وسجّل الدخول'),
                isDark: isDark,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Resend
        Center(
          child: TextButton.icon(
            onPressed: (_sending || _isOnCooldown()) ? null : _sendResetEmail,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(
              _isOnCooldown()
                  ? t('Resend in $_resendCooldownLeft s', 'إعادة الإرسال خلال $_resendCooldownLeft ث')
                  : t('Resend Link', 'إعادة إرسال الرابط'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final String number;
  final Color color;
  final IconData icon;
  final String text;
  final bool isDark;

  const _StepRow({
    required this.number,
    required this.color,
    required this.icon,
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 16, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.sub(isDark),
            ),
          ),
        ),
      ],
    );
  }
}
