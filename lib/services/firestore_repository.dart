import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/squat_logic.dart';

/// Centralized Firestore operations for roles, slots, and session logging.
class FirestoreRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Save patient profile in `patients/{uid}`.
  Future<void> savePatientProfile({
    required String uid,
    required String fullName,
    required String phone,
    required String email,
  }) async {
    await _db.collection('patients').doc(uid).set({
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Save doctor profile in `doctors/{uid}` with isVerified flag.
  Future<void> saveDoctorProfile({
    required String uid,
    required String fullName,
    required String phone,
    required String email,
    String? graduationYear,
    String? certificateUrl,
    String? additionalQualifications,
  }) async {
    await _db.collection('doctors').doc(uid).set({
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'graduationYear': graduationYear,
      'certificateUrl': certificateUrl,
      'additionalQualifications': additionalQualifications,
      'isVerified': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Doctors add available slots to `available_slots`.
  Future<String> addAvailableSlot({
    required DateTime startTime,
    required DateTime endTime,
    String? note,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in user to add available slot');
    }
    final doc = await _db.collection('available_slots').add({
      'doctorId': user.uid,
      'startTime': Timestamp.fromDate(startTime.toUtc()),
      'endTime': Timestamp.fromDate(endTime.toUtc()),
      'note': note,
      'isBooked': false,
      'patientId': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Patients book a slot by marking it booked and attaching their uid.
  Future<void> bookSlot({required String slotId}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in user to book a slot');
    }
    final ref = _db.collection('available_slots').doc(slotId);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      final data = snap.data();
      if (data == null) {
        throw StateError('Slot not found');
      }
      if ((data['isBooked'] as bool?) == true) {
        throw StateError('Slot already booked');
      }
      txn.update(ref, {
        'isBooked': true,
        'patientId': user.uid,
        'bookedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Log squat session results under `users/{uid}/squat_sessions/{autoId}`.
  Future<void> logSquatSession({
    required SquatResult result,
    int? targetSets,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      // If no user is signed in, skip logging silently.
      return;
    }
    final totalReps = result.correctReps + result.incorrectReps;
    final accuracy = totalReps > 0
        ? (result.correctReps / totalReps * 100)
        : 0.0;

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('squat_sessions')
        .add({
      'correctReps': result.correctReps,
      'incorrectReps': result.incorrectReps,
      'totalReps': totalReps,
      'accuracy': accuracy,
      'currentSet': result.currentSet,
      'feedback': result.feedback,
      'sessionComplete': result.sessionComplete,
      'kneeAngle': result.kneeAngle,
      'hipAngle': result.hipAngle,
      'ankleAngle': result.ankleAngle,
      'targetSets': targetSets,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
