import 'package:cloud_firestore/cloud_firestore.dart';
import 'custom_exercise_config.dart';

/// Threshold overrides for a single exercise — only non-null values are applied.
class ExerciseThresholdOverrides {
  // Squat
  final double? hipAngleMin;
  final double? hipAngleMax;
  final double? ankleAngle;
  final double? squatDepthMin;

  // Shoulder Abduction
  final double? armsTooHigh;
  final double? elbowBentMin;
  final double? asymmetryMax;
  final double? backSwayMax;

  // Internal Rotation
  final double? elbowFlareMax;
  final double? wristAlignMax;
  final double? torsoTwistMin;

  // Lateral Raise
  final double? lateralArmsTooHigh;
  final double? lateralAsymmetryMax;

  const ExerciseThresholdOverrides({
    this.hipAngleMin,
    this.hipAngleMax,
    this.ankleAngle,
    this.squatDepthMin,
    this.armsTooHigh,
    this.elbowBentMin,
    this.asymmetryMax,
    this.backSwayMax,
    this.elbowFlareMax,
    this.wristAlignMax,
    this.torsoTwistMin,
    this.lateralArmsTooHigh,
    this.lateralAsymmetryMax,
  });

  bool get isEmpty =>
      hipAngleMin == null &&
      hipAngleMax == null &&
      ankleAngle == null &&
      squatDepthMin == null &&
      armsTooHigh == null &&
      elbowBentMin == null &&
      asymmetryMax == null &&
      backSwayMax == null &&
      elbowFlareMax == null &&
      wristAlignMax == null &&
      torsoTwistMin == null &&
      lateralArmsTooHigh == null &&
      lateralAsymmetryMax == null;

  Map<String, dynamic> toMap() => {
        if (hipAngleMin != null) 'hipAngleMin': hipAngleMin,
        if (hipAngleMax != null) 'hipAngleMax': hipAngleMax,
        if (ankleAngle != null) 'ankleAngle': ankleAngle,
        if (squatDepthMin != null) 'squatDepthMin': squatDepthMin,
        if (armsTooHigh != null) 'armsTooHigh': armsTooHigh,
        if (elbowBentMin != null) 'elbowBentMin': elbowBentMin,
        if (asymmetryMax != null) 'asymmetryMax': asymmetryMax,
        if (backSwayMax != null) 'backSwayMax': backSwayMax,
        if (elbowFlareMax != null) 'elbowFlareMax': elbowFlareMax,
        if (wristAlignMax != null) 'wristAlignMax': wristAlignMax,
        if (torsoTwistMin != null) 'torsoTwistMin': torsoTwistMin,
        if (lateralArmsTooHigh != null) 'lateralArmsTooHigh': lateralArmsTooHigh,
        if (lateralAsymmetryMax != null) 'lateralAsymmetryMax': lateralAsymmetryMax,
      };

  factory ExerciseThresholdOverrides.fromMap(Map<String, dynamic> m) =>
      ExerciseThresholdOverrides(
        hipAngleMin: (m['hipAngleMin'] as num?)?.toDouble(),
        hipAngleMax: (m['hipAngleMax'] as num?)?.toDouble(),
        ankleAngle: (m['ankleAngle'] as num?)?.toDouble(),
        squatDepthMin: (m['squatDepthMin'] as num?)?.toDouble(),
        armsTooHigh: (m['armsTooHigh'] as num?)?.toDouble(),
        elbowBentMin: (m['elbowBentMin'] as num?)?.toDouble(),
        asymmetryMax: (m['asymmetryMax'] as num?)?.toDouble(),
        backSwayMax: (m['backSwayMax'] as num?)?.toDouble(),
        elbowFlareMax: (m['elbowFlareMax'] as num?)?.toDouble(),
        wristAlignMax: (m['wristAlignMax'] as num?)?.toDouble(),
        torsoTwistMin: (m['torsoTwistMin'] as num?)?.toDouble(),
        lateralArmsTooHigh: (m['lateralArmsTooHigh'] as num?)?.toDouble(),
        lateralAsymmetryMax: (m['lateralAsymmetryMax'] as num?)?.toDouble(),
      );
}

/// One exercise within a program (type + parameters + optional threshold overrides).
/// When [type] == 'custom', [customConfig] holds the full exercise definition.
class ProgramExercise {
  final String type;
  final int targetReps;
  final int targetSets;
  final String mode;
  final ExerciseThresholdOverrides thresholds;
  /// Full config for doctor-built custom exercises (type == 'custom').
  final CustomExerciseConfig? customConfig;

  const ProgramExercise({
    required this.type,
    required this.targetReps,
    required this.targetSets,
    this.mode = 'Beginner',
    this.thresholds = const ExerciseThresholdOverrides(),
    this.customConfig,
  });

  ProgramExercise copyWith({
    String? type,
    int? targetReps,
    int? targetSets,
    String? mode,
    ExerciseThresholdOverrides? thresholds,
    CustomExerciseConfig? customConfig,
  }) =>
      ProgramExercise(
        type: type ?? this.type,
        targetReps: targetReps ?? this.targetReps,
        targetSets: targetSets ?? this.targetSets,
        mode: mode ?? this.mode,
        thresholds: thresholds ?? this.thresholds,
        customConfig: customConfig ?? this.customConfig,
      );

  Map<String, dynamic> toMap() => {
        'type': type,
        'targetReps': targetReps,
        'targetSets': targetSets,
        'mode': mode,
        'thresholds': thresholds.toMap(),
        if (customConfig != null) 'customConfig': customConfig!.toMap(),
      };

  factory ProgramExercise.fromMap(Map<String, dynamic> m) => ProgramExercise(
        type: m['type'] as String? ?? 'Squat',
        targetReps: (m['targetReps'] as num?)?.toInt() ?? 10,
        targetSets: (m['targetSets'] as num?)?.toInt() ?? 3,
        mode: m['mode'] as String? ?? 'Beginner',
        thresholds: m['thresholds'] != null
            ? ExerciseThresholdOverrides.fromMap(
                Map<String, dynamic>.from(m['thresholds'] as Map))
            : const ExerciseThresholdOverrides(),
        customConfig: m['customConfig'] != null
            ? CustomExerciseConfig.fromMap(
                Map<String, dynamic>.from(m['customConfig'] as Map))
            : null,
      );
}

/// A full multi-exercise program assigned to a patient.
class ExerciseProgram {
  final String name;
  final List<ProgramExercise> exercises;
  final String assignedBy;
  final DateTime assignedAt;

  const ExerciseProgram({
    required this.name,
    required this.exercises,
    this.assignedBy = '',
    required this.assignedAt,
  });

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'exercises': exercises.map((e) => e.toMap()).toList(),
        'assignedBy': assignedBy,
        'assignedAt': Timestamp.fromDate(assignedAt),
      };

  factory ExerciseProgram.fromFirestore(Map<String, dynamic> data) {
    DateTime dt = DateTime.now();
    if (data['assignedAt'] is Timestamp) {
      dt = (data['assignedAt'] as Timestamp).toDate();
    }
    return ExerciseProgram(
      name: data['name'] as String? ?? 'Program',
      exercises: (data['exercises'] as List<dynamic>? ?? [])
          .map((e) => ProgramExercise.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      assignedBy: data['assignedBy'] as String? ?? '',
      assignedAt: dt,
    );
  }
}
