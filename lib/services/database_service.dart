import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/radiology_report.dart';
import '../models/exercise_program.dart';
import '../utils/squat_logic.dart';

/// Centralized Firestore operations for roles, slots, and workout logging.
class DatabaseService {
  DatabaseService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Save patient profile in `patients/{uid}`.
  Future<void> savePatientProfile({
    required String uid,
    required String fullName,
    required String phone,
    required String email,
    String? firstName,
    String? lastName,
  }) async {
    await _db.collection('patients').doc(uid).set({
      'fullName': fullName,
      'phone': phone,
      'email': email,
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      'assignedDoctorId': '', // Initially no assigned doctor
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Save doctor profile in `doctors/{uid}` with isVerified and approvalStatus flags.
  Future<void> saveDoctorProfile({
    required String uid,
    required String fullName,
    required String phone,
    required String email,
    String? degree,
    String? graduationDate,
    String? certificateUrl,
    String? additionalQualifications,
    String? firstName,
    String? lastName,
    List<Map<String, String>>? qualifications,
  }) async {
    await _db.collection('doctors').doc(uid).set({
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'degree': degree,
      if (graduationDate != null && graduationDate.isNotEmpty) 'graduationDate': graduationDate,
      'certificateUrl': certificateUrl,
      'additionalQualifications': additionalQualifications,
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (qualifications != null) 'qualifications': qualifications,
      'isVerified': false,
      'approvalStatus': 'pending', // pending | rejected | approved
      'submittedAt': FieldValue.serverTimestamp(),
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
    if (user == null) throw StateError('No signed-in user');
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

  /// Patients book an available slot.
  Future<void> bookSlot({required String slotId}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in user');
    final ref = _db.collection('available_slots').doc(slotId);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      final data = snap.data();
      if (data == null) throw StateError('Slot not found');
      if ((data['isBooked'] as bool?) == true) throw StateError('Slot already booked');
      txn.update(ref, {
        'isBooked': true,
        'patientId': user.uid,
        'bookedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Save a radiology report under `patients/{patientId}/radiology_reports/{autoId}`.
  Future<String> saveRadiologyReport({
    required String patientId,
    required RadiologyReport report,
  }) async {
    final doc = await _db
        .collection('patients')
        .doc(patientId)
        .collection('radiology_reports')
        .add(report.toFirestore());
    return doc.id;
  }

  /// Save (or overwrite) an exercise program on a patient document.
  /// Stored as `patients/{patientId}.assignedProgram` (a map, not a subcollection).
  Future<void> saveExerciseProgram({
    required String patientId,
    required ExerciseProgram program,
  }) async {
    await _db.collection('patients').doc(patientId).set(
      {'assignedProgram': program.toFirestore()},
      SetOptions(merge: true),
    );
  }

  /// Log a workout session under `patients/{uid}/Sessions/{autoId}`.
  Future<void> logWorkout({
    required SquatResult result,
    int? targetSets,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final data = result.toWorkoutMap(targetSets: targetSets)
      ..['timestamp'] = FieldValue.serverTimestamp();
    await _db
        .collection('patients')
        .doc(user.uid)
        .collection('Sessions')
        .add(data);
  }
}
