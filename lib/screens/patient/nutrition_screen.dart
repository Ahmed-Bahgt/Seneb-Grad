import 'package:flutter/material.dart';

import 'nutrition_chatbot_screen.dart';

class NutritionScreen extends StatelessWidget {
  final VoidCallback? onBack;
  const NutritionScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return NutritionChatbotScreen(onBack: onBack);
  }
}
