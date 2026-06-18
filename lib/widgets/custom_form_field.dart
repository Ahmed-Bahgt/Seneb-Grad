import 'package:flutter/material.dart';
import '../utils/theme_provider.dart';

class CustomFormField extends StatelessWidget {
  final String labelText;
  final bool isPassword;
  final TextInputType keyboardType;
  final Widget? suffixIcon;
  final String? initialValue;
  final TextEditingController? controller;
  final bool? obscureText;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const CustomFormField(
    this.labelText, {
    super.key,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
    this.initialValue,
    this.controller,
    this.obscureText,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: TextFormField(
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        keyboardType: keyboardType,
        obscureText: obscureText ?? isPassword,
        validator: validator,
        onChanged: onChanged,
        style: TextStyle(color: AppTheme.text(isDark), fontSize: 15),
        cursorColor: AppTheme.cyan,
        decoration: InputDecoration(
          labelText: labelText,
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: AppTheme.card(isDark),
          labelStyle: TextStyle(color: AppTheme.sub(isDark), fontSize: 14),
          floatingLabelStyle: const TextStyle(color: AppTheme.cyan, fontSize: 13),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.border(isDark)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.cyan, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
