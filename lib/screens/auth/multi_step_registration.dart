import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';
import '../../utils/theme_provider.dart';
import '../../utils/permission_helper.dart';

class MultiStepRegistrationPage extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onDoctorSuccess;
  final VoidCallback onPatientSuccess;
  final VoidCallback onDoctorLogin;
  final VoidCallback onPatientLogin;
  final RegistrationRole initialRole;

  const MultiStepRegistrationPage({
    super.key,
    required this.onBack,
    required this.onDoctorSuccess,
    required this.onPatientSuccess,
    required this.onDoctorLogin,
    required this.onPatientLogin,
    this.initialRole = RegistrationRole.patient,
  });

  @override
  State<MultiStepRegistrationPage> createState() => _MultiStepRegistrationPageState();
}

class _MultiStepRegistrationPageState extends State<MultiStepRegistrationPage> {
  final _authService = AuthService();
  final _coreFormKey = GlobalKey<FormState>();
  final _doctorFormKey = GlobalKey<FormState>();

  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _gradDateCtrl = TextEditingController();
  final _additionalQualCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  File? _certificateFile;

  RegistrationRole _role = RegistrationRole.patient;
  int _currentStep = 0;
  bool _sendingOtp = false;
  bool _submitting = false;
  bool _otpSent = false;
  String? _verificationId;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _gradDateCtrl.dispose();
    _additionalQualCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _changeStep(int step) {
    setState(() => _currentStep = step);
  }

  Future<void> _pickCertificate() async {
    final hasPermission = await checkAndRequestUploadPermission(
      context,
      isCamera: false,
    );
    if (!hasPermission) {
      _showSnack(t('Permission to access gallery is required', 'صلاحية الوصول لمعرض الصور مطلوبة'));
      return;
    }

    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200, maxHeight: 1200);
    if (picked != null) {
      setState(() => _certificateFile = File(picked.path));
    }
  }

  Future<void> _pickGraduationDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      _gradDateCtrl.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  Future<void> _sendOtp() async {
    if (_phoneCtrl.text.trim().isEmpty) {
      _showSnack(t('Please enter a phone number first', 'الرجاء إدخال رقم الهاتف أولاً'));
      return;
    }
    setState(() {
      _sendingOtp = true;
      _otpSent = false;
    });
    try {
      await _authService.sendOtp(
        phoneNumber: _phoneCtrl.text.trim(),
        onCodeSent: (verificationId, _) {
          setState(() {
            _verificationId = verificationId;
            _otpSent = true;
          });
          _showSnack(t('OTP sent. Check your phone.', 'تم إرسال رمز التحقق. تحقق من هاتفك.'));
        },
        onAutoVerified: (_) {
          _showSnack(t('Phone auto-verified', 'تم التحقق من الهاتف تلقائياً'));
        },
        onVerificationFailed: (e) {
          _showSnack('${t('OTP failed:', 'فشل رمز التحقق:')} ${e.message ?? e.code}');
        },
      );
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _submitFinal() async {
    if (_verificationId == null || _otpCtrl.text.trim().isEmpty) {
      _showSnack(t('Enter the OTP code sent to your phone.', 'أدخل رمز التحقق المرسل إلى هاتفك.'));
      return;
    }

    setState(() => _submitting = true);
    try {
      final fullName = _fullNameCtrl.text.trim();
      final parts = fullName.split(' ');
      final firstName = parts.isNotEmpty ? parts.first : fullName;
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      final data = RegistrationData(
        role: _role,
        firstName: firstName,
        lastName: lastName,
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        phoneNumber: _phoneCtrl.text.trim(),
        graduationDate: _gradDateCtrl.text.trim().isEmpty ? null : _gradDateCtrl.text.trim(),
        additionalQualifications: _additionalQualCtrl.text.trim().isEmpty ? null : _additionalQualCtrl.text.trim(),
        certificateFile: _certificateFile,
      );

      await _authService.confirmOtpAndCreateAccount(
        verificationId: _verificationId!,
        smsCode: _otpCtrl.text.trim(),
        data: data,
      );

      if (!mounted) return;
      if (_role == RegistrationRole.doctor) {
        widget.onDoctorSuccess();
      } else {
        widget.onPatientSuccess();
      }
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? e.code);
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onContinue() {
    switch (_currentStep) {
      case 0:
        _changeStep(1);
        break;
      case 1:
        if (_coreFormKey.currentState?.validate() ?? false) {
          _changeStep(2);
        }
        break;
      case 2:
        if (_role == RegistrationRole.doctor) {
          if ((_certificateFile == null)) {
            _showSnack(t('Please upload your graduation certificate.', 'يرجى تحميل شهادة التخرج.'));
            return;
          }
          if (_gradDateCtrl.text.isEmpty) {
            _showSnack(t('Please choose your graduation date.', 'يرجى اختيار تاريخ التخرج.'));
            return;
          }
        }
        _changeStep(3);
        break;
      case 3:
        _submitFinal();
        break;
    }
  }

  void _onCancel() {
    if (_currentStep == 0) {
      widget.onBack();
    } else {
      _changeStep(_currentStep - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('Create Account', 'إنشاء حساب')),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
      ),
      body: Stepper(
        currentStep: _currentStep,
        type: StepperType.vertical,
        onStepContinue: _onContinue,
        onStepCancel: _onCancel,
        controlsBuilder: (context, details) {
          return Row(
            children: [
              ElevatedButton(
                onPressed: _submitting || _sendingOtp ? null : details.onStepContinue,
                child: _submitting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_currentStep == 3 ? t('Submit', 'إرسال') : t('Next', 'التالي')),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: details.onStepCancel,
                child: Text(_currentStep == 0 ? t('Back', 'رجوع') : t('Previous', 'السابق')),
              ),
            ],
          );
        },
        steps: [
          Step(
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            title: Text(t('Role Selection', 'اختيار الدور')),
            content: _buildRoleSelection(isDark),
          ),
          Step(
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            title: Text(t('Core Info', 'المعلومات الأساسية')),
            content: _buildCoreInfo(isDark),
          ),
          Step(
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
            title: Text(t('Role Details', 'تفاصيل الدور')),
            content: _buildRoleSpecific(isDark),
          ),
          Step(
            isActive: _currentStep >= 3,
            state: _currentStep > 3 ? StepState.complete : StepState.indexed,
            title: Text(t('Security (OTP)', 'التحقق (OTP)')),
            content: _buildOtpStep(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('Choose your role to continue.', 'اختر دورك للمتابعة.'), style: TextStyle(color: AppTheme.sub(isDark))),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: [
            ChoiceChip(
              label: Text(t('Patient', 'مريض')),
              selected: _role == RegistrationRole.patient,
              onSelected: (_) => setState(() => _role = RegistrationRole.patient),
            ),
            ChoiceChip(
              label: Text(t('Doctor', 'طبيب')),
              selected: _role == RegistrationRole.doctor,
              onSelected: (_) => setState(() => _role = RegistrationRole.doctor),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCoreInfo(bool isDark) {
    return Form(
      key: _coreFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _fullNameCtrl,
            decoration: InputDecoration(labelText: t('Full Name', 'الاسم الكامل')),
            validator: (v) => (v == null || v.trim().length < 3) ? t('Enter a valid name', 'أدخل اسماً صالحاً') : null,
          ),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: t('Email', 'البريد الإلكتروني')),
            validator: (v) => (v == null || !v.contains('@')) ? t('Enter a valid email', 'أدخل بريدًا صالحًا') : null,
          ),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: InputDecoration(labelText: t('Password', 'كلمة المرور')),
            validator: (v) => (v == null || v.length < 6) ? t('Password must be 6+ chars', 'كلمة المرور يجب أن تكون 6 أحرف على الأقل') : null,
          ),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: t('Phone Number (with country code)', 'رقم الهاتف (مع رمز الدولة)')),
            validator: (v) => (v == null || v.trim().length < 8) ? t('Enter a valid phone number', 'أدخل رقم هاتف صالح') : null,
          ),
        ].map((w) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: w)).toList(),
      ),
    );
  }

  Widget _buildRoleSpecific(bool isDark) {
    if (_role == RegistrationRole.patient) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('No extra info needed for patients. Continue to OTP.', 'لا معلومات إضافية مطلوبة للمرضى. تابع إلى رمز التحقق.'), style: TextStyle(color: AppTheme.sub(isDark))),
        ],
      );
    }

    return Form(
      key: _doctorFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _gradDateCtrl,
            readOnly: true,
            onTap: _pickGraduationDate,
            decoration: InputDecoration(
              labelText: t('Graduation Date', 'تاريخ التخرج'),
              suffixIcon: const Icon(Icons.calendar_today),
            ),
          ),
          TextFormField(
            controller: _additionalQualCtrl,
            maxLines: 3,
            decoration: InputDecoration(labelText: t('Additional Qualifications', 'مؤهلات إضافية')),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(t('Graduation Certificate', 'شهادة التخرج'), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickCertificate,
            child: Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.card(isDark) : AppTheme.card(isDark),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _certificateFile != null ? Colors.green : (isDark ? Colors.white24 : Colors.grey[300]!)),
              ),
              child: _certificateFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(_certificateFile!, fit: BoxFit.cover),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_upload, size: 36, color: Colors.teal),
                        const SizedBox(height: 8),
                        Text(t('Tap to upload certificate', 'انقر لتحميل الشهادة'), style: TextStyle(color: AppTheme.sub(isDark))),
                        const SizedBox(height: 4),
                        Text(t('JPG/PNG, max ~5MB', 'JPG/PNG، بحد أقصى 5MB'), style: TextStyle(color: isDark ? Colors.white38 : Colors.grey[500], fontSize: 12)),
                      ],
                    ),
            ),
          ),
        ].map((w) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: w)).toList(),
      ),
    );
  }

  Widget _buildOtpStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('We will verify the phone number you entered. A code will be sent to it.', 'سنتحقق من رقم الهاتف الذي أدخلته. سيتم إرسال رمز إليه.'), style: TextStyle(color: AppTheme.sub(isDark))),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t('OTP Code', 'رمز التحقق')),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _sendingOtp ? null : _sendOtp,
              child: _sendingOtp
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_otpSent ? t('Resend OTP', 'إعادة الإرسال') : t('Send OTP', 'إرسال الرمز')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('${t('Phone:', 'الهاتف: ')} ${_phoneCtrl.text}', style: TextStyle(color: AppTheme.sub(isDark))),
      ],
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
