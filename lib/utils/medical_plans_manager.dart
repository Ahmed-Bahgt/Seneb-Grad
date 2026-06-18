import 'package:flutter/material.dart';

/// Singleton to manage patient medical plans
class MedicalPlansManager {
  static final MedicalPlansManager _instance = MedicalPlansManager._internal();

  factory MedicalPlansManager() {
    return _instance;
  }

  MedicalPlansManager._internal() {
    _initializeTestPlans();
  }

  final List<MedicalPlan> _plans = [];
  final List<VoidCallback> _listeners = [];

  List<MedicalPlan> get plans => List.unmodifiable(_plans);
  MedicalPlan? get activePlan {
    if (_plans.isEmpty) return null;
    return _plans.firstWhere(
      (p) => p.isActive,
      orElse: () => _plans.first,
    );
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

  void updatePlanProgress(int index, double progress) {
    if (index >= 0 && index < _plans.length) {
      _plans[index].progress = progress.clamp(0.0, 100.0);
      _notifyListeners();
    }
  }

  void addPlan(MedicalPlan plan) {
    _plans.add(plan);
    _notifyListeners();
  }

  void _initializeTestPlans() {
    _plans.add(MedicalPlan(
      id: 'plan_1',
      name: 'Squat Rehabilitation Plan',
      description: 'A comprehensive plan to strengthen your lower body and improve mobility through guided squats and supporting exercises.',
      progress: 0.0, // Will be calculated from sessions
      totalSessions: 12,
      completedSessions: 0,
      isActive: true,
      startDate: DateTime.now().subtract(const Duration(days: 7)),
      duration: 6, // weeks
      exercises: ['Bodyweight Squats', 'Wall Squats', 'Leg Press', 'Range of Motion Work'],
    ));

    _plans.add(MedicalPlan(
      id: 'plan_2',
      name: 'Lower Back Pain Management',
      description: 'Evidence-based exercises to strengthen core and reduce lower back pain.',
      progress: 0.0, // Will be calculated from sessions
      totalSessions: 16,
      completedSessions: 0,
      isActive: false,
      startDate: DateTime.now().subtract(const Duration(days: 30)),
      duration: 8,
      exercises: ['Core Planks', 'Bird Dog', 'Bridge Hold', 'Cat-Cow Stretch'],
    ));
  }
}

class MedicalPlan {
  final String id;
  final String name;
  final String description;
  double progress; // 0-100 (can be overridden, but calculated by default)
  final int totalSessions;
  final int completedSessions;
  final bool isActive;
  final DateTime startDate;
  final int duration; // in weeks
  final List<String> exercises;

  MedicalPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.progress,
    required this.totalSessions,
    required this.completedSessions,
    required this.isActive,
    required this.startDate,
    required this.duration,
    required this.exercises,
  });

  /// Calculate progress based on completed sessions vs total sessions
  double get calculatedProgress {
    if (totalSessions <= 0) return 0.0;
    return ((completedSessions / totalSessions) * 100).clamp(0.0, 100.0);
  }
}
