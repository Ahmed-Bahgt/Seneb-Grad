import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/api_config.dart';

class SqlMedicalService {
  Future<Map<String, dynamic>> chat(String question, {String type = 'general'}) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/medical/chat'),
        body: {
          'question': question,
          'context_type': type,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Medical Chat failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  void clearCache() {
    // Currently no local cache is maintained in this implementation.
  }
}
