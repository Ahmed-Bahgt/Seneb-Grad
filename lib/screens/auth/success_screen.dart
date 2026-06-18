import 'package:flutter/material.dart';
import '../../utils/theme_provider.dart';
import '../../widgets/gradient_button.dart';

/// Success Screen - Generic Success Page
class SuccessScreen extends StatelessWidget {
  final String title;
  final String message;
  final String buttonText;
  final VoidCallback onReturn;

  const SuccessScreen({
    super.key,
    required this.title,
    required this.message,
    required this.buttonText,
    required this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle,
                size: 100,
                color: Color(0xFF8BC34A),
              ),
              const SizedBox(height: 30),
              Text(
                title,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text(isDark),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              Text(
                message,
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.sub(isDark),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 50),
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  text: buttonText,
                  onPressed: onReturn,
                  startColor: const Color(0xFF8BC34A),
                  endColor: const Color(0xFF689F38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
