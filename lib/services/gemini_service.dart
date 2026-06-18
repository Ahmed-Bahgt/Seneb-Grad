import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:crypto/crypto.dart';
import '../utils/api_config.dart';

class GeminiService {
  GenerativeModel? _modelInstance;

  GenerativeModel get _model {
    if (_modelInstance == null) {
      final key = ApiConfig.geminiApiKey.trim();
      if (key == 'PASTE_YOUR_REAL_KEY_HERE' || key.isEmpty) {
        throw Exception('Please paste your real Gemini API Key in lib/utils/api_config.dart');
      }
      _modelInstance = GenerativeModel(
        model: ApiConfig.geminiModel,
        apiKey: key,
      );
    }
    return _modelInstance!;
  }

  final Map<String, String> _ingredientCache = {};
  GeminiService();

  String _generateImageHash(Uint8List imageBytes) {
    return md5.convert(imageBytes).toString();
  }

  Future<String> extractIngredientsFromImageFile(File file) async {
    try {
      final imageBytes = await file.readAsBytes();
      final hash = _generateImageHash(imageBytes);
      
      // DISABLED CACHE LOOKUP FOR TESTING PROMPT CHANGES
      // if (_ingredientCache.containsKey(hash)) return _ingredientCache[hash]!;

      const prompt = '''Analyze this food image and identify all ingredients with precise volume estimation.
Format: [quantity] [unit] [food_name]

CRITICAL RULES:
1. ALWAYS use digits for quantity (e.g., 0.25, 1.5, 2). NEVER use words like "a", "half", or "some".
2. Proportions: Base ingredients (rice/pasta/meat) should be larger (1-2 cups or 150g). Toppings/Garnishes (onions/sauces) should be small (0.1 to 0.25 cup).
3. Units: Use "cups" for rice/grains, "g" for meat, and "tbsp" for oils/small toppings.

Examples:
1.25 cups white rice
180 g grilled chicken
0.15 cup fried onions
2 tbsp tomato sauce

Return ONLY the plain list.''';

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      final response = await _model.generateContent(content);
      final text = response.text?.trim() ?? '';
      
      // Cache the result for future use (once prompt is stable)
      _ingredientCache[hash] = text;
      return text;
    } catch (e) {
      throw Exception('Gemini Error: $e');
    }
  }

  ChatSession startChat(String systemContext) {
    return _model.startChat(history: [Content.text(systemContext)]);
  }

  Future<String> sendChatMessage(ChatSession chat, String message) async {
    try {
      final response = await chat.sendMessage(Content.text(message));
      return response.text ?? 'No response';
    } catch (e) {
      throw Exception('Chat error: $e');
    }
  }
  Future<String> generateText(String prompt) async {
    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? '';
    } catch (e) {
      return '';
    }
  }
}
