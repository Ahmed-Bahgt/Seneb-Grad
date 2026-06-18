import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../utils/api_config.dart';

class SqlService {
  final String _baseUrl = ApiConfig.aiHubBaseUrl;

  // --- AUTH SYNC ---

  /// Syncs a Firebase user to the PostgreSQL backend.
  Future<void> syncUser({
    required String uid,
    required String email,
    required String fullName,
    required String phone,
    required String role,
  }) async {
    final url = Uri.parse('$_baseUrl/users/register');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'id': uid,
        'email': email,
        'full_name': fullName,
        'phone': phone,
        'role': role,
        'password': 'firebase_managed', // Placeholder since Firebase handles auth
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to sync user to SQL: ${response.body}');
    }
  }

  // --- PROFILE ---

  Future<Map<String, dynamic>> getProfile(String uid) async {
    final url = Uri.parse('$_baseUrl/profile/$uid');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Profile not found in SQL');
    }
  }

  // --- SLOTS & BOOKING ---

  Future<List<dynamic>> getAvailableSlots() async {
    final url = Uri.parse('$_baseUrl/slots/available');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    return [];
  }

  Future<void> createSlot({
    required String doctorId,
    required DateTime startTime,
    required DateTime endTime,
    String? note,
  }) async {
    final url = Uri.parse('$_baseUrl/slots?doctor_id=$doctorId');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'note': note ?? '',
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to create slot: ${response.body}');
    }
  }

  Future<void> deleteSlot(int slotId) async {
    final url = Uri.parse('$_baseUrl/slots/$slotId');
    final response = await http.delete(url);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete slot: ${response.body}');
    }
  }

  Future<void> deleteAllDoctorSlots(String doctorId) async {
    final url = Uri.parse('$_baseUrl/slots/doctor/$doctorId');
    final response = await http.delete(url);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete doctor slots: ${response.body}');
    }
  }

  Future<void> bookSlot(int slotId, String patientId) async {
    final url = Uri.parse('$_baseUrl/book-slot?slot_id=$slotId&patient_id=$patientId');
    final response = await http.post(url);
    if (response.statusCode != 200) {
      throw Exception('Booking failed: ${response.body}');
    }
  }

  // --- RADIOLOGY ---

  Future<Map<String, dynamic>> analyzeRadiology({
    required File imageFile,
    required String patientId,
    required String doctorId,
    String bodyPart = 'Wrist',
  }) async {
    final url = Uri.parse('$_baseUrl/radiology/predict');
    var request = http.MultipartRequest('POST', url);
    request.fields['patient_id'] = patientId;
    request.fields['doctor_id'] = doctorId;
    request.fields['body_part'] = bodyPart;
    request.fields['api_key'] = ApiConfig.openRouterApiKey;
    
    request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Radiology analysis failed');
    }
  }

  // --- SESSIONS ---

  Future<void> logSession({
    required String patientId,
    required int correct,
    required int incorrect,
    required int totalSets,
    String exerciseType = 'Squat',
    String mode = 'Beginner',
    String? accuracy,
    bool sessionComplete = false,
  }) async {
    final url = Uri.parse('$_baseUrl/sessions/log');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'patient_id': patientId,
        'correct_reps': correct,
        'incorrect_reps': incorrect,
        'total_sets': totalSets,
        'exercise_type': exerciseType,
        'mode': mode,
        'accuracy': accuracy,
        'session_complete': sessionComplete,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to log session: ${response.body}');
    }
  }

  // --- BOOKINGS ---

  Future<void> createBooking({
    required String bookingId,
    required String patientId,
    required String doctorId,
    required String doctorName,
    String? patientName,
    String? specialty,
    required DateTime dateTime,
    required DateTime endTime,
    String status = 'upcoming',
  }) async {
    final url = Uri.parse('$_baseUrl/bookings/create');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'id': bookingId,
        'patient_id': patientId,
        'doctor_id': doctorId,
        'doctor_name': doctorName,
        'patient_name': patientName,
        'specialty': specialty,
        'date_time': dateTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'status': status,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to create booking: ${response.body}');
    }
  }

  Future<void> cancelBooking(String bookingId) async {
    final url = Uri.parse('$_baseUrl/bookings/$bookingId');
    final response = await http.delete(url);
    if (response.statusCode != 200) {
      throw Exception('Failed to cancel booking: ${response.body}');
    }
  }

  // --- ADMIN METHODS ---

  Future<Map<String, dynamic>> adminLogin(String email, String password) async {
    final url = Uri.parse('$_baseUrl/admin/login');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
        'full_name': 'Admin',
        'phone': '000',
        'role': 'admin'
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Invalid admin credentials');
    }
  }

  /// Registers a new admin in the PostgreSQL backend (syncs from Firebase).
  Future<void> adminRegister({
    required String uid,
    required String email,
    required String password,
    required String fullName,
  }) async {
    final url = Uri.parse('$_baseUrl/admin/register');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'id': uid,
        'email': email,
        'password': password,
        'full_name': fullName,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to sync admin to SQL: ${response.body}');
    }
  }

  Future<List<dynamic>> getPendingDoctors() async {
    final url = Uri.parse('$_baseUrl/admin/pending-doctors');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    return [];
  }

  Future<void> approveDoctor(String doctorId, String status) async {
    final url = Uri.parse('$_baseUrl/admin/approve-doctor?doctor_id=$doctorId&status=$status');
    final response = await http.post(url);
    if (response.statusCode != 200) {
      throw Exception('Failed to update doctor status');
    }
  }
}
