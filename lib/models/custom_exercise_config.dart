/// Data model for a custom exercise created via the Exercise Builder wizard.
/// Stored inline in ProgramExercise.customConfig (Firestore map field).
library;

// ── Measurement config ───────────────────────────────────────────────────────

class MeasurementConfig {
  final String type;
  // For angle / vertical_angle
  final String? p1;
  final String? vertex;
  final String? p3;
  // For distance_ratio
  final String? p2;
  // For knee_valgus_ratio
  final String? side; // 'left' | 'right' | 'bilateral_max'
  // For bilateral_* types
  final MeasurementConfig? left;
  final MeasurementConfig? right;

  const MeasurementConfig({
    required this.type,
    this.p1,
    this.vertex,
    this.p3,
    this.p2,
    this.side,
    this.left,
    this.right,
  });

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{'type': type};
    if (p1 != null) m['p1'] = p1;
    if (vertex != null) m['vertex'] = vertex;
    if (p3 != null) m['p3'] = p3;
    if (p2 != null) m['p2'] = p2;
    if (side != null) m['side'] = side;
    if (left != null) m['left'] = left!.toMap();
    if (right != null) m['right'] = right!.toMap();
    return m;
  }

  factory MeasurementConfig.fromMap(Map<String, dynamic> m) => MeasurementConfig(
        type: (m['type'] as String?) ?? 'angle',
        p1: m['p1'] as String?,
        vertex: m['vertex'] as String?,
        p3: m['p3'] as String?,
        p2: m['p2'] as String?,
        side: m['side'] as String?,
        left: m['left'] != null
            ? MeasurementConfig.fromMap(Map<String, dynamic>.from(m['left'] as Map))
            : null,
        right: m['right'] != null
            ? MeasurementConfig.fromMap(Map<String, dynamic>.from(m['right'] as Map))
            : null,
      );

  /// Human-readable summary for doctor UI.
  String get summary {
    switch (type) {
      case 'angle':
        return 'Angle: $p1 → $vertex → $p3';
      case 'vertical_angle':
        return 'Vertical angle: $p1 at $vertex';
      case 'bilateral_avg_angle':
        return 'Bilateral avg angle (L/R)';
      case 'bilateral_max_angle':
        return 'Bilateral max angle (worst side)';
      case 'bilateral_min_angle':
        return 'Bilateral min angle (weakest side)';
      case 'bilateral_diff_angle':
        return 'Left–right asymmetry';
      case 'torso_angle':
        return 'Forward torso lean';
      case 'lateral_trunk_angle':
        return 'Lateral trunk lean';
      case 'distance_ratio':
        return 'Distance ratio: $p1 to $p2';
      case 'knee_valgus_ratio':
        return 'Knee valgus ($side)';
      case 'rotation_ratio':
        return 'Forearm rotation ratio';
      case 'wrist_y_diff':
        return 'Wrist vertical offset';
      case 'elbow_flare_ratio':
        return 'Elbow flare ratio';
      case 'ratio_vs_baseline':
        return 'Shoulder width ratio vs baseline';
      default:
        return type;
    }
  }
}

// ── Form check ────────────────────────────────────────────────────────────────

class FormCheckConfig {
  final String id;
  final String labelEn;
  final String labelAr;
  final List<int> color; // [R, G, B]
  final int displayY;
  final MeasurementConfig measurement;
  /// E.g. "value > 20.0" or "value < 140.0"
  final String condition;
  final bool affectsRep;
  final List<String> skipInStates;
  final bool requireS2Seen;
  final MeasurementConfig? measurementB;
  final String? conditionB;

  const FormCheckConfig({
    required this.id,
    required this.labelEn,
    required this.labelAr,
    required this.color,
    required this.displayY,
    required this.measurement,
    required this.condition,
    this.affectsRep = false,
    this.skipInStates = const [],
    this.requireS2Seen = false,
    this.measurementB,
    this.conditionB,
  });

  double get threshold {
    final op = condition.contains('>') ? '>' : '<';
    return double.tryParse(condition.split(op).last.trim()) ?? 20.0;
  }

  String get conditionOp => condition.contains('>') ? '>' : '<';

  FormCheckConfig copyWith({
    String? labelEn,
    String? labelAr,
    double? threshold,
    String? conditionOp,
    bool? affectsRep,
  }) {
    final newOp = conditionOp ?? this.conditionOp;
    final newThr = threshold ?? this.threshold;
    return FormCheckConfig(
      id: id,
      labelEn: labelEn ?? this.labelEn,
      labelAr: labelAr ?? this.labelAr,
      color: color,
      displayY: displayY,
      measurement: measurement,
      condition: 'value $newOp $newThr',
      affectsRep: affectsRep ?? this.affectsRep,
      skipInStates: skipInStates,
      requireS2Seen: requireS2Seen,
      measurementB: measurementB,
      conditionB: conditionB,
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'id': id,
      'labelEn': labelEn,
      'labelAr': labelAr,
      'color': color,
      'displayY': displayY,
      'measurement': measurement.toMap(),
      'condition': condition,
      'affectsRep': affectsRep,
    };
    if (skipInStates.isNotEmpty) m['skipInStates'] = skipInStates;
    if (requireS2Seen) m['requireS2Seen'] = true;
    if (measurementB != null) m['measurementB'] = measurementB!.toMap();
    if (conditionB != null) m['conditionB'] = conditionB;
    return m;
  }

  factory FormCheckConfig.fromMap(Map<String, dynamic> m) => FormCheckConfig(
        id: (m['id'] as String?) ?? 'CHECK',
        labelEn: (m['labelEn'] as String?) ?? '',
        labelAr: (m['labelAr'] as String?) ?? (m['labelEn'] as String?) ?? '',
        color: (m['color'] as List<dynamic>?)?.cast<int>() ?? [255, 80, 80],
        displayY: (m['displayY'] as num?)?.toInt() ?? 125,
        measurement: MeasurementConfig.fromMap(
            Map<String, dynamic>.from((m['measurement'] as Map?) ?? {})),
        condition: (m['condition'] as String?) ?? 'value > 20.0',
        affectsRep: m['affectsRep'] as bool? ?? false,
        skipInStates:
            (m['skipInStates'] as List<dynamic>?)?.cast<String>() ?? [],
        requireS2Seen: m['requireS2Seen'] as bool? ?? false,
        measurementB: m['measurementB'] != null
            ? MeasurementConfig.fromMap(
                Map<String, dynamic>.from(m['measurementB'] as Map))
            : null,
        conditionB: m['conditionB'] as String?,
      );
}

// ── Full exercise config ──────────────────────────────────────────────────────

class CustomExerciseConfig {
  final String name;
  final String description;
  final String view; // 'front' | 'side'
  final String mode; // 'rep' | 'hold'
  final double? holdDuration; // seconds (hold mode only)
  final double inactiveThresh; // seconds before timeout
  final String feedbackPersistence; // 'frame' | 'rep'
  final double offsetThresh; // side-view alignment tolerance
  final bool armLock; // auto-detect dominant arm
  final List<int> visibilityIndices; // MediaPipe landmark indices that must be visible
  /// State ranges: {'s1': [min, max], 's2': [min, max], 's3': [min, max]}
  final Map<String, List<double>> states;
  final MeasurementConfig primaryMeasurement;
  final List<FormCheckConfig> formChecks;

  const CustomExerciseConfig({
    required this.name,
    required this.description,
    required this.view,
    required this.mode,
    this.holdDuration,
    this.inactiveThresh = 15.0,
    this.feedbackPersistence = 'frame',
    this.offsetThresh = 50.0,
    this.armLock = false,
    required this.visibilityIndices,
    required this.states,
    required this.primaryMeasurement,
    required this.formChecks,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'view': view,
        'mode': mode,
        if (holdDuration != null) 'holdDuration': holdDuration,
        'inactiveThresh': inactiveThresh,
        'feedbackPersistence': feedbackPersistence,
        'offsetThresh': offsetThresh,
        'armLock': armLock,
        'visibilityIndices': visibilityIndices,
        'states': states.map((k, v) => MapEntry(k, v)),
        'primaryMeasurement': primaryMeasurement.toMap(),
        'formChecks': formChecks.map((c) => c.toMap()).toList(),
      };

  factory CustomExerciseConfig.fromMap(Map<String, dynamic> m) {
    final statesRaw = (m['states'] as Map?)?.cast<String, dynamic>() ?? {};
    final states = <String, List<double>>{};
    statesRaw.forEach((k, v) {
      states[k] =
          (v as List<dynamic>).map((e) => (e as num).toDouble()).toList();
    });

    return CustomExerciseConfig(
      name: (m['name'] as String?) ?? '',
      description: m['description'] as String? ?? '',
      view: m['view'] as String? ?? 'front',
      mode: m['mode'] as String? ?? 'rep',
      holdDuration: (m['holdDuration'] as num?)?.toDouble(),
      inactiveThresh: (m['inactiveThresh'] as num?)?.toDouble() ?? 15.0,
      feedbackPersistence: m['feedbackPersistence'] as String? ?? 'frame',
      offsetThresh: (m['offsetThresh'] as num?)?.toDouble() ?? 50.0,
      armLock: m['armLock'] as bool? ?? false,
      visibilityIndices:
          (m['visibilityIndices'] as List<dynamic>?)?.cast<int>() ?? [0, 11, 12],
      states: states,
      primaryMeasurement: MeasurementConfig.fromMap(
          Map<String, dynamic>.from(m['primaryMeasurement'] as Map)),
      formChecks: (m['formChecks'] as List<dynamic>? ?? [])
          .map((c) =>
              FormCheckConfig.fromMap(Map<String, dynamic>.from(c as Map)))
          .toList(),
    );
  }
}

// ── Constants used by the builder UI ─────────────────────────────────────────

/// All measurement types available in the generic processor.
const kMeasurementTypes = [
  'angle',
  'vertical_angle',
  'bilateral_avg_angle',
  'bilateral_max_angle',
  'bilateral_min_angle',
  'bilateral_diff_angle',
  'torso_angle',
  'lateral_trunk_angle',
  'distance_ratio',
  'knee_valgus_ratio',
  'rotation_ratio',
  'wrist_y_diff',
  'elbow_flare_ratio',
  'ratio_vs_baseline',
];

/// Types that need no extra landmark parameters.
const kParamFree = {
  'torso_angle',
  'lateral_trunk_angle',
  'rotation_ratio',
  'wrist_y_diff',
  'elbow_flare_ratio',
  'ratio_vs_baseline',
};

/// Types that need left + right sub-measurements.
const kBilateralTypes = {
  'bilateral_avg_angle',
  'bilateral_max_angle',
  'bilateral_min_angle',
  'bilateral_diff_angle',
};

const kLandmarkNames = [
  'nose',
  'left_shoulder',
  'right_shoulder',
  'left_elbow',
  'right_elbow',
  'left_wrist',
  'right_wrist',
  'left_hip',
  'right_hip',
  'left_knee',
  'right_knee',
  'left_ankle',
  'right_ankle',
  'left_foot',
  'right_foot',
];
