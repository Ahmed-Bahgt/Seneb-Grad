import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../models/exercise_program.dart';
import 'theme_provider.dart';

/// Singleton to manage patient profile data
class PatientProfileManager {
  static final PatientProfileManager _instance = PatientProfileManager._internal();

  factory PatientProfileManager() {
    return _instance;
  }

  PatientProfileManager._internal() {
    _patientName = 'Ahmed';
    _patientNotes = '';
    _exerciseType = '';
    _exerciseSets = 0;
    _exerciseReps = 0;
    _exerciseMode = '';
  }

  late String _patientName;
  late String _patientNotes;
  late String _exerciseType;
  late int _exerciseSets;
  late int _exerciseReps;
  late String _exerciseMode;
  int _totalSessions = 0;
  int _completedSessions = 0;
  ExerciseProgram? _exerciseProgram;
  final List<VoidCallback> _listeners = [];
  StreamSubscription<DocumentSnapshot>? _profileSub;

  String get patientName => _patientName;
  String get patientNotes => _patientNotes;
  String get exerciseType => _exerciseType;
  int get exerciseSets => _exerciseSets;
  int get exerciseReps => _exerciseReps;
  String get exerciseMode => _exerciseMode;
  int get totalSessions => _totalSessions;
  int get completedSessions => _completedSessions;
  ExerciseProgram? get exerciseProgram => _exerciseProgram;

  /// Derived display name for the patient's currently-assigned plan.
  /// Used by the home screen "Today's Session" card.
  String? get activePlanName {
    if (_exerciseProgram != null && _exerciseProgram!.name.isNotEmpty) {
      return _exerciseProgram!.name;
    }
    if (_exerciseType.isNotEmpty) return _exerciseType;
    return null;
  }

  /// Whichever single exercise type the trainer should run today (first item
  /// of the program, or the legacy single-plan field).
  String get activeExerciseType {
    if (_exerciseProgram != null && _exerciseProgram!.exercises.isNotEmpty) {
      return _exerciseProgram!.exercises.first.type;
    }
    return _exerciseType;
  }

  double get progressPercent {
    if (_totalSessions <= 0) return 0;
    return ((_completedSessions / _totalSessions) * 100).clamp(0, 100);
  }

  void setPatientName(String name) {
    _patientName = name;
    _notifyListeners();
  }

  void setPatientNotes(String notes) {
    _patientNotes = notes;
    _notifyListeners();
  }

  void setExercisePlan({required String type, required int sets, required int reps}) {
    _exerciseType = type;
    _exerciseSets = sets;
    _exerciseReps = reps;
    _notifyListeners();
  }

  void setExerciseMode(String mode) {
    _exerciseMode = mode;
    _notifyListeners();
  }

  void setSessionCounts({required int total, required int completed}) {
    _totalSessions = total;
    _completedSessions = completed;
    _notifyListeners();
  }

  /// Used by DevModeService to swap the active exercise on the fly without
  /// touching Firestore — drives both the home screen "Today's Session" card
  /// and the live trainer routing.
  void setExerciseProgram(ExerciseProgram? program) {
    _exerciseProgram = program;
    if (program != null && program.exercises.isNotEmpty) {
      final first = program.exercises.first;
      _exerciseType = first.type;
      _exerciseSets = first.targetSets;
      _exerciseReps = first.targetReps;
      _exerciseMode = first.mode;
    }
    _notifyListeners();
  }

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }

  /// Load patient profile data from Firebase and start a real-time listener
  /// so exercise assignment changes from the doctor appear immediately.
  Future<void> loadPatientProfile() async {
    if (appDevMode) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[PatientProfileManager] No user logged in, skipping profile load');
      return;
    }

    // Cancel any previous listener before starting a new one
    await _profileSub?.cancel();

    final ref = FirebaseFirestore.instance.collection('patients').doc(user.uid);

    // Do an immediate one-shot read so data is available before the stream fires
    try {
      final doc = await ref.get();
      if (doc.exists) _applySnapshot(doc.data() ?? {});
    } catch (e) {
      debugPrint('[PatientProfileManager] Initial load error: $e');
    }

    // Start real-time listener — updates exercise/notes whenever doctor changes them
    _profileSub = ref.snapshots().listen(
      (doc) {
        if (!doc.exists) return;
        _applySnapshot(doc.data() ?? {});
      },
      onError: (e) => debugPrint('[PatientProfileManager] Listener error: $e'),
    );
  }

  void _applySnapshot(Map<String, dynamic> data) {
    final firstName = data['firstName'] as String? ?? '';
    final lastName  = data['lastName']  as String? ?? '';
    _patientName = firstName.isNotEmpty && lastName.isNotEmpty
        ? '$firstName $lastName'
        : data['fullName'] as String? ?? 'Patient';
    _patientNotes = data['notes'] as String? ?? '';
    _exerciseType = data['assignedPlan'] as String? ?? '';
    _exerciseSets = (data['sets'] as num?)?.toInt() ?? 0;
    _exerciseReps = (data['reps'] as num?)?.toInt() ?? 0;
    _exerciseMode = data['assignedMode'] as String? ?? '';
    _totalSessions = (data['sessions'] as num?)?.toInt() ?? 0;
    _completedSessions = (data['completedSessions'] as num?)?.toInt() ?? 0;

    if (data['assignedProgram'] is Map) {
      _exerciseProgram = ExerciseProgram.fromFirestore(
        Map<String, dynamic>.from(data['assignedProgram'] as Map),
      );
      if (_exerciseProgram!.exercises.isNotEmpty) {
        final first = _exerciseProgram!.exercises.first;
        _exerciseType = first.type;
        _exerciseSets = first.targetSets;
        _exerciseReps = first.targetReps;
        _exerciseMode = first.mode;
      }
    } else {
      _exerciseProgram = null;
    }

    debugPrint('[PatientProfileManager] Profile updated: $_patientName, exercise: $_exerciseType');
    _notifyListeners();
  }
}
