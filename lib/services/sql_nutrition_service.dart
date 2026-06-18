import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../utils/api_config.dart';

class SqlNutritionService {
  /// Analyzes a meal image using the FastAPI backend.
  /// Returns a map with 'detected_text' and 'analysis' (ingredients, total, health_score).
  Future<Map<String, dynamic>> analyzeMeal(File imageFile) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(ApiConfig.nutritionApiUrl));
      
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Failed to analyze meal');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  /// Sends a nutrition-related question to the backend chatbot.
  Future<String> chat(String question, Map<String, dynamic> mealData) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.nutritionChatEndpoint),
        body: {
          'question': question,
          'meal_data': json.encode(mealData),
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['response'] ?? 'No response from AI';
      } else {
        throw Exception('Failed to get chat response');
      }
    } catch (e) {
      throw Exception('Chat connection error: $e');
    }
  }
  /// Sends edited ingredients to recalculate nutrition.
  Future<Map<String, dynamic>> recalculate(List<dynamic> ingredients) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/nutrition/recalculate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'ingredients': ingredients}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Recalculation failed');
      }
    } catch (e) {
      throw Exception('Recalculation error: $e');
    }
  }
}

final sqlNutritionService = SqlNutritionService();
