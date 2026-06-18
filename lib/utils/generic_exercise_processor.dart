/// Universal exercise processor — Dart port of generic_processor.py.
/// Accepts a CustomExerciseConfig (analogous to the YAML) and processes
/// ML Kit Pose frames using all 14 measurement types.
library;

import 'dart:math';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/custom_exercise_config.dart';
import 'abduction_logic.dart'; // ExerciseResult (shared result class)

class GenericExerciseProcessor {
  final CustomExerciseConfig config;
  final int targetSets;
  final int repsPerSet;

  // ── Per-session state ──────────────────────────────────────────────────────
  List<String> _stateSeq = [];
  List<bool> _displayText = [];
  bool _incorrectPosture = false;
  String? _currState;
  int _repCount = 0;
  int _improperRep = 0;
  int _setCount = 0;
  int _effectiveSetCount = 0;
  bool _waitingForReset = false;
  int _messageTimer = 0; // frames left in rest display
  bool _isInitializing = true;
  int _romWarningTimer = 0;
  int _sessionCorrectReps = 0;
  int _sessionImproperReps = 0;
  String? _activeArm;
  double? _baseShoulderWidth;
  DateTime? _holdStartTime;
  double _holdProgress = 0.0;
  String? _displayMessage;

  static const int _restFrames = 90; // ~3 s at 30 fps

  GenericExerciseProcessor({
    required this.config,
    required this.targetSets,
    required this.repsPerSet,
  }) {
    _displayText = List.filled(config.formChecks.length, false);
  }

  void reset() {
    _stateSeq = [];
    _displayText = List.filled(config.formChecks.length, false);
    _incorrectPosture = false;
    _currState = null;
    _repCount = 0;
    _improperRep = 0;
    _setCount = 0;
    _effectiveSetCount = 0;
    _waitingForReset = false;
    _messageTimer = 0;
    _isInitializing = true;
    _romWarningTimer = 0;
    _sessionCorrectReps = 0;
    _sessionImproperReps = 0;
    _activeArm = null;
    _baseShoulderWidth = null;
    _holdStartTime = null;
    _holdProgress = 0.0;
    _displayMessage = null;
  }

  int get effectiveSetCount => _effectiveSetCount;
  int get totalCorrectReps => _sessionCorrectReps;
  int get totalIncorrectReps => _sessionImproperReps;

  /// Compute only the primary measurement (used by calibration step in the builder).
  double? computePrimary(Pose pose) {
    final ctx = _buildContext(pose);
    if (ctx == null) return null;
    return _compute(config.primaryMeasurement, pose, ctx);
  }

  // ── Main entry point ───────────────────────────────────────────────────────

  ExerciseResult processFrame(Pose pose) {
    if (pose.landmarks.isEmpty) {
      return _emptyResult(false, 'No person detected');
    }

    // ── Rest timer (waiting between sets) ─────────────────────────────────
    if (_waitingForReset) {
      _messageTimer--;
      if (_messageTimer <= 0) {
        final total = _repCount + _improperRep;
        final acc = total > 0 ? _repCount / total : 0.0;
        if (acc >= 0.7) _effectiveSetCount++;
        _waitingForReset = false;
        _repCount = 0;
        _improperRep = 0;
        _setCount++;
        _stateSeq = [];
        _incorrectPosture = false;
        _activeArm = null;
        _isInitializing = true;
      }
      return ExerciseResult(
        correctReps: _sessionCorrectReps,
        incorrectReps: _sessionImproperReps,
        currentSet: _setCount,
        effectiveSetCount: _effectiveSetCount,
        feedback: _displayMessage ?? 'Rest...',
        isRepCounted: false,
        sessionComplete: false,
        jointsDetected: true,
        displayMessage: _displayMessage,
        waitingForReset: true,
        messageTimer: _messageTimer,
        primaryAngle: 0,
      );
    }

    // ── Clear frame-persistence feedback at start of frame ────────────────
    if (config.feedbackPersistence == 'frame') {
      _displayText = List.filled(config.formChecks.length, false);
    }

    // ── Build per-frame context ────────────────────────────────────────────
    final ctx = _buildContext(pose);
    if (ctx == null) {
      return _emptyResult(true, 'Body not fully visible');
    }

    // ── Primary measurement → state ────────────────────────────────────────
    final primaryVal = _compute(config.primaryMeasurement, pose, ctx);
    if (primaryVal == null) {
      return _emptyResult(true, 'Cannot measure exercise position');
    }

    final currentState = _getState(primaryVal);
    _currState = currentState;
    if (currentState != null) _updateStateSeq(currentState);

    // ── Form checks ────────────────────────────────────────────────────────
    _runChecks(pose, currentState, ctx);

    // ── Initialization grace (don't count until first s1 is reached) ──────
    if (_isInitializing) {
      if (currentState == 's1') _isInitializing = false;
      _stateSeq = [];
      _incorrectPosture = false;
    }

    // ── Rep / hold counting ────────────────────────────────────────────────
    bool repCounted = false;
    if (config.mode == 'hold') {
      repCounted = _onHold(currentState, primaryVal);
    } else if (!_waitingForReset && currentState == 's1') {
      repCounted = _onS1();
    }


    final sessionComplete = _setCount >= targetSets && !_waitingForReset;

    return ExerciseResult(
      correctReps: _sessionCorrectReps,
      incorrectReps: _sessionImproperReps,
      currentSet: _setCount,
      effectiveSetCount: _effectiveSetCount,
      feedback: _activeFeedback(),
      isRepCounted: repCounted,
      sessionComplete: sessionComplete,
      jointsDetected: true,
      displayMessage: _waitingForReset ? _displayMessage : null,
      waitingForReset: _waitingForReset,
      messageTimer: _messageTimer,
      primaryAngle: primaryVal,
    );
  }

  // ── Context builder ────────────────────────────────────────────────────────

  Map<String, dynamic>? _buildContext(Pose pose) {
    final ctx = <String, dynamic>{};

    if (config.view == 'front') {
      final ls = _lm(pose, 'left_shoulder');
      final rs = _lm(pose, 'right_shoulder');
      if (ls == null || rs == null) return null;

      ctx['left_shoulder'] = ls;
      ctx['right_shoulder'] = rs;
      ctx['left_elbow'] = _lm(pose, 'left_elbow');
      ctx['right_elbow'] = _lm(pose, 'right_elbow');
      ctx['left_wrist'] = _lm(pose, 'left_wrist');
      ctx['right_wrist'] = _lm(pose, 'right_wrist');
      ctx['left_hip'] = _lm(pose, 'left_hip');
      ctx['right_hip'] = _lm(pose, 'right_hip');

      final sw = (rs.x - ls.x).abs();
      ctx['shoulder_width'] = sw > 0 ? sw : 0.01;

      // Arm lock: auto-detect dominant arm (closest elbow angle to 90°)
      if (config.armLock) {
        if (_activeArm == null) {
          final le = _lm(pose, 'left_elbow');
          final lw = _lm(pose, 'left_wrist');
          final re = _lm(pose, 'right_elbow');
          final rw = _lm(pose, 'right_wrist');
          if (le != null && lw != null && re != null && rw != null) {
            final la = _findAngle(ls, lw, le);
            final ra = _findAngle(rs, rw, re);
            _activeArm = (la - 90).abs() < (ra - 90).abs() ? 'left' : 'right';
          }
        }
        if (_activeArm != null) {
          ctx['active_arm'] = _activeArm;
          ctx['active_shoulder'] = _lm(pose, '${_activeArm}_shoulder');
          ctx['active_elbow'] = _lm(pose, '${_activeArm}_elbow');
          ctx['active_wrist'] = _lm(pose, '${_activeArm}_wrist');
        }
      }

      // Torso-twist baseline (calibrated at s1)
      if (_baseShoulderWidth == null || _currState == 's1') {
        _baseShoulderWidth = ctx['shoulder_width'] as double;
      }
      ctx['base_shoulder_width'] = _baseShoulderWidth;
    } else {
      // Side view — detect which side faces camera (larger foot-shoulder span)
      final ls = _lm(pose, 'left_shoulder');
      final rs = _lm(pose, 'right_shoulder');
      final lf = _lm(pose, 'left_foot');
      final rf = _lm(pose, 'right_foot');
      if (ls == null || rs == null) return null;

      ctx['left_shoulder'] = ls;
      ctx['right_shoulder'] = rs;

      final lSpan = lf != null ? (lf.y - ls.y).abs() : 0.0;
      final rSpan = rf != null ? (rf.y - rs.y).abs() : 0.0;
      final side = lSpan > rSpan ? 'left' : 'right';
      ctx['side'] = side;

      ctx['shoulder'] = _lm(pose, '${side}_shoulder');
      ctx['elbow'] = _lm(pose, '${side}_elbow');
      ctx['wrist'] = _lm(pose, '${side}_wrist');
      ctx['hip'] = _lm(pose, '${side}_hip');
      ctx['knee'] = _lm(pose, '${side}_knee');
      ctx['ankle'] = _lm(pose, '${side}_ankle');
      ctx['foot'] = _lm(pose, '${side}_foot');
    }

    return ctx;
  }

  // ── Measurement computation ────────────────────────────────────────────────

  double? _compute(
      MeasurementConfig meas, Pose pose, Map<String, dynamic> ctx) {
    switch (meas.type) {
      case 'angle':
        final p1 = _lmByName(pose, meas.p1, ctx);
        final v = _lmByName(pose, meas.vertex, ctx);
        final p3 = _lmByName(pose, meas.p3, ctx);
        if (p1 == null || v == null || p3 == null) return null;
        return _findAngle(p1, v, p3);

      case 'vertical_angle':
        final p1 = _lmByName(pose, meas.p1, ctx);
        final v = _lmByName(pose, meas.vertex, ctx);
        if (p1 == null || v == null) return null;
        // angle at (v.x, 0) between p1 and v = lean from vertical
        return _findAngle(p1, _P(v.x, 0), v);

      case 'bilateral_avg_angle':
      case 'bilateral_max_angle':
      case 'bilateral_min_angle':
      case 'bilateral_diff_angle':
        if (meas.left == null || meas.right == null) return null;
        final la = _simpleAngle(meas.left!, pose);
        final ra = _simpleAngle(meas.right!, pose);
        if (la == null || ra == null) return null;
        return switch (meas.type) {
          'bilateral_avg_angle' => (la + ra) / 2,
          'bilateral_max_angle' => max(la, ra),
          'bilateral_min_angle' => min(la, ra),
          _ => (la - ra).abs(), // bilateral_diff_angle
        };

      case 'torso_angle':
        final ls = ctx['left_shoulder'] as _P?;
        final rs = ctx['right_shoulder'] as _P?;
        final lh = ctx['left_hip'] as _P? ?? _lm(pose, 'left_hip');
        final rh = ctx['right_hip'] as _P? ?? _lm(pose, 'right_hip');
        if (ls == null || rs == null || lh == null || rh == null) return null;
        final midS = _P((ls.x + rs.x) / 2, (ls.y + rs.y) / 2);
        final midH = _P((lh.x + rh.x) / 2, (lh.y + rh.y) / 2);
        return _findAngle(midS, _P(midH.x, 0), midH);

      case 'lateral_trunk_angle':
        final ls = ctx['left_shoulder'] as _P? ?? _lm(pose, 'left_shoulder');
        final rs = ctx['right_shoulder'] as _P? ?? _lm(pose, 'right_shoulder');
        final lh = ctx['left_hip'] as _P? ?? _lm(pose, 'left_hip');
        final rh = ctx['right_hip'] as _P? ?? _lm(pose, 'right_hip');
        if (ls == null || rs == null || lh == null || rh == null) return null;
        final midS = _P((ls.x + rs.x) / 2, (ls.y + rs.y) / 2);
        final midH = _P((lh.x + rh.x) / 2, (lh.y + rh.y) / 2);
        final dx = midS.x - midH.x;
        final dy = midH.y - midS.y; // positive = hip below shoulder (normal)
        return (180 / pi) * atan2(dx.abs(), max(dy, 1e-4));

      case 'rotation_ratio':
        final arm = ctx['active_arm'] as String?;
        final aw = ctx['active_wrist'] as _P?;
        final ae = ctx['active_elbow'] as _P?;
        final sw = (ctx['shoulder_width'] as double?) ?? 0.1;
        if (arm == null || aw == null || ae == null) return null;
        return arm == 'left' ? (aw.x - ae.x) / sw : (ae.x - aw.x) / sw;

      case 'wrist_y_diff':
        final ae = ctx['active_elbow'] as _P?;
        final aw = ctx['active_wrist'] as _P?;
        if (ae == null || aw == null) return null;
        return (ae.y - aw.y).abs(); // normalized coords → already in 0-1 range

      case 'elbow_flare_ratio':
        final ae = ctx['active_elbow'] as _P?;
        final as_ = ctx['active_shoulder'] as _P?;
        final sw = (ctx['shoulder_width'] as double?) ?? 0.1;
        final arm = ctx['active_arm'] as String?;
        if (ae == null || as_ == null || arm == null) return null;
        return arm == 'left' ? (ae.x - as_.x) / sw : (as_.x - ae.x) / sw;

      case 'ratio_vs_baseline':
        final sw = (ctx['shoulder_width'] as double?) ?? 0.1;
        final bsw = (ctx['base_shoulder_width'] as double?) ?? sw;
        return sw / (bsw > 0 ? bsw : 0.001);

      case 'distance_ratio':
        final p1 = _lm(pose, meas.p1!);
        final p2 = _lm(pose, meas.p2!);
        final sw = (ctx['shoulder_width'] as double?) ?? 0.1;
        if (p1 == null || p2 == null) return null;
        final dx = p1.x - p2.x;
        final dy = p1.y - p2.y;
        return sqrt(dx * dx + dy * dy) / max(sw, 1e-4);

      case 'knee_valgus_ratio':
        final sw = (ctx['shoulder_width'] as double?) ?? 0.1;
        final side = meas.side ?? 'bilateral_max';

        double? valgusOne(String sn) {
          final k = _lm(pose, '${sn}_knee');
          final a = _lm(pose, '${sn}_ankle');
          final h = _lm(pose, '${sn}_hip');
          if (k == null || a == null || h == null) return null;
          final t = (k.y - h.y) / max((a.y - h.y).abs(), 1e-6);
          final midX = h.x + t * (a.x - h.x);
          final sign = sn == 'left' ? 1.0 : -1.0;
          return sign * (k.x - midX) / max(sw, 1e-4);
        }

        if (side == 'bilateral_max') {
          final lv = valgusOne('left');
          final rv = valgusOne('right');
          if (lv == null && rv == null) return null;
          return max(lv ?? double.negativeInfinity,
              rv ?? double.negativeInfinity);
        }
        return valgusOne(side);

      default:
        return null;
    }
  }

  double? _simpleAngle(MeasurementConfig meas, Pose pose) {
    final p1 = _lm(pose, meas.p1!);
    final v = _lm(pose, meas.vertex!);
    final p3 = _lm(pose, meas.p3!);
    if (p1 == null || v == null || p3 == null) return null;
    return _findAngle(p1, v, p3);
  }

  // ── Form checks ────────────────────────────────────────────────────────────

  void _runChecks(
      Pose pose, String? currentState, Map<String, dynamic> ctx) {
    for (int i = 0; i < config.formChecks.length; i++) {
      final chk = config.formChecks[i];
      if (chk.skipInStates.contains(currentState)) continue;
      if (chk.requireS2Seen && !_stateSeq.contains('s2')) continue;

      final val = _compute(chk.measurement, pose, ctx);
      if (val == null) continue;

      bool fires = _evalCond(val, chk.condition);

      // Compound AND condition
      if (fires && chk.measurementB != null && chk.conditionB != null) {
        final valB = _compute(chk.measurementB!, pose, ctx);
        fires = valB != null && _evalCond(valB, chk.conditionB!);
      }

      if (fires) {
        _displayText[i] = true;
        if (chk.affectsRep && currentState != 's1') {
          _incorrectPosture = true;
        }
      }
    }
  }

  // ── Condition evaluator ────────────────────────────────────────────────────

  bool _evalCond(double value, String condition) {
    condition = condition.trim();
    // Range: "N < value < M"
    final rangeRe = RegExp(r'^(-?\d+\.?\d*)\s*<\s*value\s*<\s*(-?\d+\.?\d*)$');
    final rm = rangeRe.firstMatch(condition);
    if (rm != null) {
      return double.parse(rm.group(1)!) < value &&
          value < double.parse(rm.group(2)!);
    }
    // Simple: "value > N"
    final opRe = RegExp(r'^value\s*(>=|<=|>|<)\s*(-?\d+\.?\d*)$');
    final om = opRe.firstMatch(condition);
    if (om != null) {
      final op = om.group(1)!;
      final num = double.parse(om.group(2)!);
      return switch (op) {
        '>' => value > num,
        '<' => value < num,
        '>=' => value >= num,
        '<=' => value <= num,
        _ => false,
      };
    }
    return false;
  }

  // ── State machine ──────────────────────────────────────────────────────────

  String? _getState(double value) {
    final s1 = config.states['s1'];
    final s2 = config.states['s2'];
    final s3 = config.states['s3'];
    if (s1 != null && value >= s1[0] && value <= s1[1]) return 's1';
    if (s2 != null && value >= s2[0] && value <= s2[1]) return 's2';
    if (s3 != null && value >= s3[0] && value <= s3[1]) return 's3';
    return null;
  }

  void _updateStateSeq(String state) {
    if (state == 's2') {
      if ((!_stateSeq.contains('s3') && !_stateSeq.contains('s2')) ||
          (_stateSeq.contains('s3') &&
              _stateSeq.where((s) => s == 's2').length == 1)) {
        _stateSeq.add(state);
      }
    } else if (state == 's3') {
      if (!_stateSeq.contains(state) && _stateSeq.contains('s2')) {
        _stateSeq.add(state);
      }
    }
  }

  // ── Rep counting ───────────────────────────────────────────────────────────

  bool _onS1() {
    final seq = _stateSeq;
    bool repCounted = false;

    if (seq.length == 3 && !_incorrectPosture) {
      _repCount++;
      _sessionCorrectReps++;
      repCounted = true;
    } else if (seq.contains('s2') && seq.length == 1) {
      _improperRep++;
      _sessionImproperReps++;
      _romWarningTimer = 45;
      repCounted = true;
    } else if (_incorrectPosture && seq.isNotEmpty) {
      _improperRep++;
      _sessionImproperReps++;
      repCounted = true;
    }

    _stateSeq = [];
    _incorrectPosture = false;
    if (config.feedbackPersistence == 'rep') {
      _displayText = List.filled(config.formChecks.length, false);
    }

    final total = _repCount + _improperRep;
    if (total >= repsPerSet) {
      final acc = total > 0 ? _repCount / total : 0.0;
      _waitingForReset = true;
      _messageTimer = _restFrames;
      final nextSet = _setCount + 1;
      final isFinal = nextSet >= targetSets;
      _displayMessage = isFinal
          ? (acc >= 0.7 ? 'Excellent! Training Complete!' : 'Training Complete!')
          : (acc >= 0.7 ? 'Excellent! Set $nextSet Done!' : 'Set $nextSet Done!');
    }

    return repCounted;
  }

  bool _onHold(String? currentState, double primaryVal) {
    if (currentState == 's3' && !_waitingForReset) {
      _holdStartTime ??= DateTime.now();
      final holdDuration = config.holdDuration ?? 30.0;
      final elapsed =
          DateTime.now().difference(_holdStartTime!).inMilliseconds / 1000.0;
      _holdProgress = min(elapsed / holdDuration, 1.0);

      if (elapsed >= holdDuration) {
        _repCount++;
        _sessionCorrectReps++;
        _holdStartTime = null;
        _holdProgress = 0.0;
        _incorrectPosture = false;

        final total = _repCount + _improperRep;
        if (total >= repsPerSet) {
          _waitingForReset = true;
          _messageTimer = _restFrames;
          _displayMessage =
              (_setCount + 1) >= targetSets ? 'Training Complete!' : 'Set Done!';
        }
        return true;
      }
    } else if (_holdStartTime != null) {
      final holdDuration = config.holdDuration ?? 30.0;
      final elapsed =
          DateTime.now().difference(_holdStartTime!).inMilliseconds / 1000.0;
      if (elapsed < holdDuration * 0.5) {
        _improperRep++;
        _sessionImproperReps++;
        final total = _repCount + _improperRep;
        if (total >= repsPerSet) {
          _waitingForReset = true;
          _messageTimer = _restFrames;
          _displayMessage = 'Set Done!';
        }
      }
      _holdStartTime = null;
      _holdProgress = 0.0;
      _incorrectPosture = false;
      _stateSeq = [];
    }
    return false;
  }

  // ── Feedback text ──────────────────────────────────────────────────────────

  String _activeFeedback() {
    for (int i = 0; i < config.formChecks.length; i++) {
      if (i < _displayText.length && _displayText[i]) {
        return config.formChecks[i].labelEn;
      }
    }
    if (_romWarningTimer > 0) {
      _romWarningTimer--;
      return 'INCOMPLETE ROM';
    }
    if (_waitingForReset) return _displayMessage ?? 'Rest...';
    if (config.mode == 'hold' && _holdProgress > 0) {
      return 'HOLD: ${(_holdProgress * 100).toInt()}%';
    }
    return 'Good form';
  }

  // ── Landmark helpers ───────────────────────────────────────────────────────

  static const _nameToType = <String, PoseLandmarkType>{
    'nose': PoseLandmarkType.nose,
    'left_shoulder': PoseLandmarkType.leftShoulder,
    'right_shoulder': PoseLandmarkType.rightShoulder,
    'left_elbow': PoseLandmarkType.leftElbow,
    'right_elbow': PoseLandmarkType.rightElbow,
    'left_wrist': PoseLandmarkType.leftWrist,
    'right_wrist': PoseLandmarkType.rightWrist,
    'left_hip': PoseLandmarkType.leftHip,
    'right_hip': PoseLandmarkType.rightHip,
    'left_knee': PoseLandmarkType.leftKnee,
    'right_knee': PoseLandmarkType.rightKnee,
    'left_ankle': PoseLandmarkType.leftAnkle,
    'right_ankle': PoseLandmarkType.rightAnkle,
    'left_foot': PoseLandmarkType.leftFootIndex,
    'right_foot': PoseLandmarkType.rightFootIndex,
  };

  _P? _lm(Pose pose, String name) {
    final type = _nameToType[name];
    if (type == null) return null;
    final lm = pose.landmarks[type];
    if (lm == null) return null;
    return _P(lm.x, lm.y);
  }

  /// Resolve a landmark name that may be bare ('shoulder') prefixed by active side,
  /// or fully qualified ('left_shoulder').
  _P? _lmByName(Pose pose, String? name, Map<String, dynamic> ctx) {
    if (name == null) return null;
    if (name.contains('_')) return _lm(pose, name);
    // Short name — try ctx first, then side-prefix
    final side = ctx['side'] as String? ?? 'right';
    return _lm(pose, '${side}_$name');
  }

  double _findAngle(_P a, _P b, _P c) {
    final abx = a.x - b.x, aby = a.y - b.y;
    final cbx = c.x - b.x, cby = c.y - b.y;
    final dot = abx * cbx + aby * cby;
    final n1 = sqrt(abx * abx + aby * aby);
    final n2 = sqrt(cbx * cbx + cby * cby);
    if (n1 == 0 || n2 == 0) return 0;
    return (180 / pi) * acos((dot / (n1 * n2)).clamp(-1.0, 1.0));
  }

  ExerciseResult _emptyResult(bool jointsDetected, String message) =>
      ExerciseResult(
        correctReps: _sessionCorrectReps,
        incorrectReps: _sessionImproperReps,
        currentSet: _setCount,
        effectiveSetCount: _effectiveSetCount,
        feedback: message,
        isRepCounted: false,
        sessionComplete: false,
        jointsDetected: jointsDetected,
        displayMessage: null,
        waitingForReset: false,
        messageTimer: 0,
        primaryAngle: 0,
      );
}

class _P {
  final double x, y;
  const _P(this.x, this.y);
}
