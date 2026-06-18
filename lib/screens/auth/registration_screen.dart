import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

/// Basic multi-step registration using phone OTP.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _degreeCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  RegistrationRole _role = RegistrationRole.patient;
  String? _verificationId;
  bool _sendingOtp = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _degreeCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sendingOtp = true);
    try {
      await _auth.sendOtp(
        phoneNumber: _phoneCtrl.text.trim(),
        onCodeSent: (verificationId, _) {
          setState(() => _verificationId = verificationId);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OTP sent to phone')),
          );
        },
        onAutoVerified: (_) {},
        onVerificationFailed: (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? e.code)),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _submit() async {
    if (_verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Send OTP first')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final fullName = _nameCtrl.text.trim();
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
        graduationDate: _degreeCtrl.text.trim().isEmpty ? null : _degreeCtrl.text.trim(),
      );

      await _auth.confirmOtpAndCreateAccount(
        verificationId: _verificationId!,
        smsCode: _otpCtrl.text.trim(),
        data: data,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration complete')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Patient'),
                    selected: _role == RegistrationRole.patient,
                    onSelected: (_) => setState(() => _role = RegistrationRole.patient),
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('Doctor'),
                    selected: _role == RegistrationRole.doctor,
                    onSelected: (_) => setState(() => _role = RegistrationRole.doctor),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter name' : null,
              ),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter valid email' : null,
              ),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (+country code)'),
                validator: (v) => (v == null || v.trim().length < 8) ? 'Enter phone' : null,
              ),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) => (v == null || v.length < 6) ? 'Min 6 chars' : null,
              ),
              if (_role == RegistrationRole.doctor)
                TextFormField(
                  controller: _degreeCtrl,
                  decoration: const InputDecoration(labelText: 'Degree / Graduation Year'),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _sendingOtp ? null : _sendOtp,
                      child: _sendingOtp
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Send OTP'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      controller: _otpCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'OTP'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Complete Registration'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
