import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'database_service.dart';
import 'sql_service.dart';

/// Registration role options.
enum RegistrationRole { patient, doctor }

/// Accumulates registration data across steps before final submit.
class RegistrationData {
  RegistrationRole role;
  String firstName;
  String lastName;
  String get fullName => '$firstName $lastName'.trim();
  String email;
  String password;
  String phoneNumber;
  String? graduationDate;
  String? additionalQualifications; // optional legacy text field
  File? certificateFile;
  List<QualificationInput>? qualifications; // structured list (name + file)

  RegistrationData({
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
    required this.phoneNumber,
    this.graduationDate,
    this.additionalQualifications,
    this.certificateFile,
    this.qualifications,
  });

  Map<String, dynamic> toMap({String? certificateUrl}) {
    return {
      'role': role.name,
      'fullName': fullName,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phoneNumber': phoneNumber,
      'graduationDate': graduationDate,
      'additionalQualifications': additionalQualifications,
      'certificateUrl': certificateUrl,
      'phoneVerified': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

/// Input model for a qualification item before upload.
class QualificationInput {
  final String name;
  final File? file;

  QualificationInput({required this.name, this.file});
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final DatabaseService _dbService = DatabaseService();

  AuthService() {
    // Simplify testing on emulators: disable app verification so Firebase
    // Console test numbers work without Play Integrity / reCAPTCHA.
    if (kDebugMode) {
      try {
        _auth.setSettings(appVerificationDisabledForTesting: true);
        debugPrint('🔥 FirebaseAuth: appVerificationDisabledForTesting enabled (debug)');
      } catch (e) {
        debugPrint('⚠️ FirebaseAuth: setSettings not available or failed: $e');
      }
    }
  }

  /// Starts phone verification and returns verificationId via [onCodeSent].
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(PhoneAuthCredential credential) onAutoVerified,
    required void Function(FirebaseAuthException error) onVerificationFailed,
  }) async {
    // Normalize Egyptian phone: remove leading 0 and prepend +20
    String normalizedPhone = _normalizeEgyptianPhone(phoneNumber);
    debugPrint('🔥 Firebase: Sending OTP to $normalizedPhone');
    await _auth.verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) {
        debugPrint('🔥 Firebase: Phone auto-verified');
        onAutoVerified(credential);
      },
      verificationFailed: (error) {
        debugPrint('🔥 Firebase: Verification failed - ${error.code}: ${error.message}');
        onVerificationFailed(error);
      },
      codeSent: (verificationId, resendToken) {
        debugPrint('🔥 Firebase: OTP sent successfully');
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (_) {
        debugPrint('🔥 Firebase: Auto-retrieval timeout');
      },
    );
  }

  /// Sign in existing users via OTP (after code is sent with [sendOtp]).
  Future<UserCredential> signInWithOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  /// Confirms OTP, creates the email/password user, links the phone credential, uploads certificate if any, and saves Firestore profile.
  Future<UserCredential> confirmOtpAndCreateAccount({
    required String verificationId,
    required String smsCode,
    required RegistrationData data,
  }) async {
    debugPrint('🔥 Firebase: Confirming OTP and creating account...');
    
    // Validate phone first.
    final phoneCredential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    // Sign in with phone to ensure OTP is correct, then sign out to avoid conflicts.
    debugPrint('🔥 Firebase: Validating phone credential...');
    await _auth.signInWithCredential(phoneCredential);
    await _auth.signOut();

    // Create email/password account after OTP succeeds, or sign in if email exists.
    debugPrint('🔥 Firebase: Creating email/password account for ${data.email}');
    UserCredential emailCred;
    try {
      emailCred = await _auth.createUserWithEmailAndPassword(
        email: data.email,
        password: data.password,
      );
      debugPrint('🔥 Firebase: User created with UID: ${emailCred.user!.uid}');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        debugPrint('⚠️ Firebase: Email already in use. Signing in existing user.');
        emailCred = await _auth.signInWithEmailAndPassword(
          email: data.email,
          password: data.password,
        );
        debugPrint('🔥 Firebase: Signed in existing user UID: ${emailCred.user!.uid}');
      } else {
        rethrow;
      }
    }

    // Link phone to the created user so both credentials work.
    debugPrint('🔥 Firebase: Linking phone credential...');
    try {
      await emailCred.user?.linkWithCredential(phoneCredential);
    } on FirebaseAuthException catch (e) {
      // If already linked, continue.
      if (e.code == 'provider-already-linked' || e.code == 'credential-already-in-use') {
        debugPrint('⚠️ Firebase: Phone credential already linked. Continuing.');
      } else {
        rethrow;
      }
    }

    // Upload doctor certificate if present.
    String? certificateUrl;
    if (data.role == RegistrationRole.doctor && data.certificateFile != null) {
      debugPrint('🔥 Firebase: Uploading doctor certificate...');
      certificateUrl = await uploadCertificate(
        file: data.certificateFile!,
        uid: emailCred.user!.uid,
      );
      debugPrint('🔥 Firebase: Certificate uploaded to: $certificateUrl');
    }

    // Persist profile in Firestore.
    debugPrint('🔥 Firebase: Saving user profile to Firestore...');
    await _firestore.collection('users').doc(emailCred.user!.uid).set(
      data.toMap(certificateUrl: certificateUrl),
      SetOptions(merge: true),
    );
    // Upload qualifications (if any) to Storage and collect URLs
    List<Map<String, String>>? uploadedQualifications;
    if (data.role == RegistrationRole.doctor && (data.qualifications?.isNotEmpty ?? false)) {
      uploadedQualifications = [];
      for (final q in data.qualifications!) {
        String? url;
        if (q.file != null) {
          url = await uploadQualificationFile(file: q.file!, uid: emailCred.user!.uid, name: q.name);
        }
        uploadedQualifications.add({
          'name': q.name,
          if (url != null) 'url': url,
        });
      }
    }

    await saveProfile(
      uid: emailCred.user!.uid,
      data: data,
      certificateUrl: certificateUrl,
      qualifications: uploadedQualifications,
    );

    // --- SYNC TO SQL BACKEND (Production-Like) ---
    try {
      final sqlService = SqlService();
      await sqlService.syncUser(
        uid: emailCred.user!.uid,
        email: data.email,
        fullName: data.fullName,
        phone: data.phoneNumber,
        role: data.role.name,
      );
      debugPrint('🔥 SQL: ✅ User synced to PostgreSQL');
    } catch (e) {
      debugPrint('⚠️ SQL: Sync failed - $e');
      // We don't block registration if SQL sync fails, but we log it.
    }

    debugPrint('🔥 Firebase: ✅ Registration complete for ${data.fullName} (${data.role.name})');

    return emailCred;
  }

  Future<String> uploadCertificate({required File file, required String uid}) async {
    if (!file.existsSync()) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'file-missing',
        message: 'Certificate file not found on device',
      );
    }
    final fileName = 'doctorCertificates/$uid/${DateTime.now().millisecondsSinceEpoch}_${file.uri.pathSegments.last}';
    debugPrint('🔥 Firebase Storage: Uploading to $fileName');
    final ref = _storage.ref(fileName);
    final uploadTask = ref.putFile(file);
    final snapshot = await uploadTask;
    if (snapshot.state != TaskState.success) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'upload-failed',
        message: 'Certificate upload failed',
      );
    }
    final url = await snapshot.ref.getDownloadURL();
    debugPrint('🔥 Firebase Storage: Upload complete');
    return url;
  }

  Future<void> saveProfile({
    required String uid,
    required RegistrationData data,
    String? certificateUrl,
    List<Map<String, String>>? qualifications,
  }) async {
    if (data.role == RegistrationRole.patient) {
      await _dbService.savePatientProfile(
        uid: uid,
        fullName: data.fullName,
        phone: data.phoneNumber,
        email: data.email,
        firstName: data.firstName,
        lastName: data.lastName,
      );
      return;
    }

    // Doctor profile
    final graduationYear = _extractGraduationYear(data.graduationDate);
    await _dbService.saveDoctorProfile(
      uid: uid,
      fullName: data.fullName,
      phone: data.phoneNumber,
      email: data.email,
      degree: graduationYear,
      graduationDate: data.graduationDate,
      certificateUrl: certificateUrl,
      additionalQualifications: data.additionalQualifications,
      firstName: data.firstName,
      lastName: data.lastName,
      qualifications: qualifications,
    );
  }

  String? _extractGraduationYear(String? graduationDate) {
    if (graduationDate == null || graduationDate.isEmpty) return null;
    // DD/MM/YYYY format
    if (graduationDate.contains('/')) {
      final parts = graduationDate.split('/');
      return parts.length == 3 ? parts.last : graduationDate;
    }
    // YYYY-MM-DD format (legacy)
    final parts = graduationDate.split('-');
    if (parts.isEmpty) return null;
    return parts.first;
  }

  /// Normalize Egyptian phone number: converts 0123456789 to +201023456789
  String _normalizeEgyptianPhone(String phoneNumber) {
    String normalized = phoneNumber.trim();
    // Remove any spaces or dashes
    normalized = normalized.replaceAll(RegExp(r'[\s\-]'), '');
    // If it starts with 0, replace with +20
    if (normalized.startsWith('0')) {
      normalized = '+20${normalized.substring(1)}';
    }
    // If it doesn't start with +, prepend +20
    else if (!normalized.startsWith('+')) {
      normalized = '+20$normalized';
    }
    return normalized;
  }

  Future<String> uploadQualificationFile({required File file, required String uid, required String name}) async {
    if (!file.existsSync()) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'file-missing',
        message: 'Qualification file not found on device',
      );
    }
    final safeName = name.replaceAll(RegExp(r"[^a-zA-Z0-9_\-]"), '_');
    final fileName = 'doctorQualifications/$uid/${DateTime.now().millisecondsSinceEpoch}_${safeName}_${file.uri.pathSegments.last}';
    final ref = _storage.ref(fileName);
    final uploadTask = ref.putFile(file);
    final snapshot = await uploadTask;
    if (snapshot.state != TaskState.success) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'upload-failed',
        message: 'Qualification upload failed',
      );
    }
    return snapshot.ref.getDownloadURL();
  }
}
