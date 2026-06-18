import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/api_config.dart';

class ClinicalChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final String? imageBase64; // Non-null when AI returned a graph

  const ClinicalChatMessage({
    required this.role,
    required this.content,
    this.imageBase64,
  });

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class SqlClinicalChatService {
  Future<ClinicalChatMessage> sendMessage({
    required String message,
    required Map<String, dynamic> sessionData,
    required List<ClinicalChatMessage> history,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/doctor/clinical-chat'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'message': message,
          'session_data': sessionData,
          'conversation_history': history.map((m) => m.toJson()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final type = data['type'] as String? ?? 'text';
        final content = data['content'] as String? ?? '';
        final imageBase64 = type == 'graph' ? data['image'] as String? : null;

        return ClinicalChatMessage(
          role: 'assistant',
          content: content,
          imageBase64: imageBase64,
        );
      } else {
        throw Exception('Chat failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }
}
