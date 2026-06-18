import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/api_config.dart';

class SqlClinicalService {
  Future<Map<String, dynamic>> analyzeSession(Map<String, dynamic> sessionData) async {
    try {
      // Sanitize sessionData to remove non-encodable objects like Firestore Timestamps
      final sanitizedData = _sanitizeMap(sessionData);

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/doctor/analyze-session'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(sanitizedData),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Clinical analysis failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  /// Recursively convert non-encodable types (like Firestore Timestamps) to strings
  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (value is Map<String, dynamic>) {
        return MapEntry(key, _sanitizeMap(value));
      } else if (value is List) {
        return MapEntry(key, value.map((e) {
          if (e is Map<String, dynamic>) return _sanitizeMap(e);
          return _isEncodable(e) ? e : e.toString();
        }).toList());
      } else {
        return MapEntry(key, _isEncodable(value) ? value : value.toString());
      }
    });
  }

  bool _isEncodable(dynamic value) {
    return value == null || value is num || value is bool || value is String;
  }
}
