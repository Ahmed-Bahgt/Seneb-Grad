import 'dart:math';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/exercise_program.dart';

/// Dart port of ProcessFrameAbduction.py
/// Tracks bilateral shoulder abduction: arms raise from sides to ~90°
class AbductionLogic {
  final ExerciseMode mode;
  final int targetReps;
  final int targetSets;

  late final _AbductionThresholds _t;

  int _setCount = 0;
  int _correctReps = 0;
  int _improperReps = 0;
  int _totalCorrectReps = 0;
  int _totalIncorrectReps = 0;
  int _effectiveSetCount = 0;
  double _lastSetAccuracy = 0.0;

  List<String> _stateSeq = [];
  String? _currentState;
  String? _prevState;

  bool _waitingForReset = false;
  int _messageTimer = 0;
  String? _freezeMessage;
  bool _incorrectPosture = false;

  // 4 feedback flags: 0=ARMS_TOO_HIGH, 1=KEEP_ARMS_STRAIGHT, 2=EVEN_ARMS, 3=DONT_SWAY_BACK
  Map<int, bool> _displayText = {0: false, 1: false, 2: false, 3: false};
  Map<int, int> _countFrames = {0: 0, 1: 0, 2: 0, 3: 0};

  DateTime _startInactiveTime = DateTime.now();
  double _inactiveTime = 0.0;
  static const double _inactiveThresh = 15.0;

  AbductionLogic({
    required this.mode,
    required this.targetReps,
    required this.targetSets,
    ExerciseThresholdOverrides? thresholds,
  }) {
    _t = _AbductionThresholds(
      overrideArmsTooHigh: thresholds?.armsTooHigh,
      overrideElbowBent: thresholds?.elbowBentMin,
      overrideAsymmetry: thresholds?.asymmetryMax,
      overrideBack: thresholds?.backSwayMax,
    );
  }

  int get effectiveSetCount => _effectiveSetCount;
  int get totalCorrectReps => _totalCorrectReps;
  int get totalIncorrectReps => _totalIncorrectReps;

  void reset() {
    _setCount = 0;
    _correctReps = 0;
    _improperReps = 0;
    _totalCorrectReps = 0;
    _totalIncorrectReps = 0;
    _effectiveSetCount = 0;
    _lastSetAccuracy = 0.0;
    _stateSeq = [];
    _currentState = null;
    _prevState = null;
    _waitingForReset = false;
    _messageTimer = 0;
    _freezeMessage = null;
    _incorrectPosture = false;
    _displayText = {0: false, 1: false, 2: false, 3: false};
    _countFrames = {0: 0, 1: 0, 2: 0, 3: 0};
    _inactiveTime = 0.0;
    _startInactiveTime = DateTime.now();
  }

  ExerciseResult processFrame(Pose pose) {
    final lm = pose.landmarks;
    if (lm.isEmpty) {
      return _emptyResult(jointsDetected: false, message: 'No person detected');
    }

    final leftShoulder = lm[PoseLandmarkType.leftShoulder];
    final rightShoulder = lm[PoseLandmarkType.rightShoulder];
    final leftElbow = lm[PoseLandmarkType.leftElbow];
    final rightElbow = lm[PoseLandmarkType.rightElbow];
    final leftWrist = lm[PoseLandmarkType.leftWrist];
    final rightWrist = lm[PoseLandmarkType.rightWrist];
    final leftHip = lm[PoseLandmarkType.leftHip];
    final rightHip = lm[PoseLandmarkType.rightHip];

    if ([leftShoulder, rightShoulder, leftElbow, rightElbow,
         leftWrist, rightWrist, leftHip, rightHip].any((e) => e == null)) {
      return _emptyResult(jointsDetected: false, message: 'Upper body not visible');
    }

    // === 1. FREEZE LOGIC ===
    if (_waitingForReset) {
      if (_messageTimer > 0) _messageTimer--;
      if (_messageTimer <= 0) {
        if (_lastSetAccuracy >= 70.0) _effectiveSetCount++;
        _waitingForReset = false;
        _correctReps = 0;
        _improperReps = 0;
        _setCount = (_setCount + 1).clamp(0, targetSets);
        _stateSeq = [];
        _incorrectPosture = false;
      }
    }

    // === 2. CALCULATE ANGLES ===
    // Shoulder abduction angle: angle at shoulder between hip, shoulder, elbow
    final leftAngle = _angle(
      _pt(leftHip!), _pt(leftShoulder!), _pt(leftElbow!),
    );
    final rightAngle = _angle(
      _pt(rightHip!), _pt(rightShoulder!), _pt(rightElbow!),
    );
    final avgAngle = (leftAngle + rightAngle) / 2;

    // Elbow angles (should stay straight)
    final leftElbowAngle = _angle(
      _pt(leftShoulder), _pt(leftWrist!), _pt(leftElbow),
    );
    final rightElbowAngle = _angle(
      _pt(rightShoulder), _pt(rightWrist!), _pt(rightElbow),
    );

    // Torso sway: angle between mid-shoulder vertical and mid-hip
    final midShldr = _Point(
      (leftShoulder.x + rightShoulder.x) / 2,
      (leftShoulder.y + rightShoulder.y) / 2,
    );
    final midHip = _Point(
      (leftHip.x + rightHip.x) / 2,
      (leftHip.y + rightHip.y) / 2,
    );
    final torsoAngle = _angle(midShldr, _Point(midHip.x, 0), midHip);

    // === 3. UPDATE STATE ===
    _currentState = _getState(avgAngle.toInt());
    _updateStateSequence(_currentState);

    // === 4. FEEDBACK CHECKS ===
    if (leftAngle > _t.armsTooHigh || rightAngle > _t.armsTooHigh) {
      _displayText[0] = true;
      _incorrectPosture = true;
    }
    if (leftElbowAngle < _t.elbowBentThresh || rightElbowAngle < _t.elbowBentThresh) {
      _displayText[1] = true;
    }
    if ((leftAngle - rightAngle).abs() > _t.asymmetryThresh) {
      _displayText[2] = true;
    }
    if (torsoAngle > _t.backThresh) {
      _displayText[3] = true;
    }

    // === 5. REP COUNTING ===
    bool repCounted = false;
    if (!_waitingForReset && _currentState == 's1') {
      if (_stateSeq.contains('s2') && _stateSeq.contains('s3') && !_incorrectPosture) {
        _correctReps++;
        _totalCorrectReps++;
        repCounted = true;
      } else if (_stateSeq.contains('s2') && !_stateSeq.contains('s3')) {
        _improperReps++;
        _totalIncorrectReps++;
        repCounted = true;
      } else if (_incorrectPosture && _stateSeq.isNotEmpty) {
        _improperReps++;
        _totalIncorrectReps++;
        repCounted = true;
      }

      _stateSeq = [];
      _incorrectPosture = false;

      final totalReps = _correctReps + _improperReps;
      if (totalReps >= targetReps) {
        _lastSetAccuracy = totalReps > 0 ? (_correctReps / totalReps * 100) : 0.0;
        _waitingForReset = true;
        _messageTimer = 90;
        final nextSet = _setCount + 1;
        _freezeMessage = nextSet >= targetSets
            ? 'Training Complete!'
            : 'Set $nextSet Done!';
      }
    }

    // === 6. INACTIVITY ===
    if (_currentState == _prevState) {
      final now = DateTime.now();
      _inactiveTime +=
          now.difference(_startInactiveTime).inMilliseconds / 1000.0;
      _startInactiveTime = now;
      if (_inactiveTime >= _inactiveThresh) {
        // Just reset the timer, don't wipe progress!
        _inactiveTime = 0.0;
        _startInactiveTime = DateTime.now();
      }
    } else {
      _startInactiveTime = DateTime.now();
      _inactiveTime = 0.0;
    }

    // === 7. FEEDBACK PERSISTENCE (30-frame hold) ===
    for (int i = 0; i < 4; i++) {
      if (_displayText[i] == true) {
        _countFrames[i] = _countFrames[i]! + 1;
        if (_countFrames[i]! > 30) {
          _displayText[i] = false;
          _countFrames[i] = 0;
        }
      }
    }

    if (_currentState != null) _prevState = _currentState;

    return ExerciseResult(
      correctReps: _correctReps,
      incorrectReps: _improperReps,
      currentSet: _setCount,
      effectiveSetCount: _effectiveSetCount,
      feedback: _generateFeedback(),
      isRepCounted: repCounted,
      sessionComplete: _setCount >= targetSets && !_waitingForReset,
      jointsDetected: true,
      displayMessage: _waitingForReset ? _freezeMessage : null,
      waitingForReset: _waitingForReset,
      messageTimer: _messageTimer,
      primaryAngle: avgAngle,
    );
  }

  ExerciseResult _emptyResult({required bool jointsDetected, String? message}) {
    return ExerciseResult(
      correctReps: _correctReps,
      incorrectReps: _improperReps,
      currentSet: _setCount,
      effectiveSetCount: _effectiveSetCount,
      feedback: message ?? 'Waiting...',
      isRepCounted: false,
      sessionComplete: _setCount >= targetSets,
      jointsDetected: jointsDetected,
      displayMessage: message,
      waitingForReset: _waitingForReset,
      messageTimer: _messageTimer,
      primaryAngle: 0,
    );
  }

  String? _getState(int angle) {
    if (angle >= _t.normalMin && angle <= _t.normalMax) return 's1';
    if (angle >= _t.transMin && angle <= _t.transMax) return 's2';
    if (angle >= _t.passMin && angle <= _t.passMax) return 's3';
    return null;
  }

  void _updateStateSequence(String? state) {
    if (state == null) return;
    if (state == 's2') {
      final s2Count = _stateSeq.where((s) => s == 's2').length;
      final hasS3 = _stateSeq.contains('s3');
      if ((!hasS3 && s2Count == 0) || (hasS3 && s2Count == 1)) {
        _stateSeq.add(state);
      }
    } else if (state == 's3') {
      if (!_stateSeq.contains(state) && _stateSeq.contains('s2')) {
        _stateSeq.add(state);
      }
    }
  }

  String _generateFeedback() {
    for (int i = 0; i < 4; i++) {
      if (_countFrames[i]! > 0) {
        switch (i) {
          case 0: return 'ARMS TOO HIGH';
          case 1: return 'KEEP ARMS STRAIGHT';
          case 2: return 'EVEN YOUR ARMS';
          case 3: return "DON'T SWAY YOUR BACK";
        }
      }
    }
    if (_waitingForReset && _freezeMessage != null) return _freezeMessage!;
    return 'Good form';
  }

  double _angle(_Point a, _Point b, _Point c) {
    final ab = _Point(a.x - b.x, a.y - b.y);
    final cb = _Point(c.x - b.x, c.y - b.y);
    final dot = ab.x * cb.x + ab.y * cb.y;
    final n1 = sqrt(ab.x * ab.x + ab.y * ab.y);
    final n2 = sqrt(cb.x * cb.x + cb.y * cb.y);
    if (n1 == 0 || n2 == 0) return 0;
    return (180 / pi) * acos((dot / (n1 * n2)).clamp(-1.0, 1.0));
  }

  _Point _pt(PoseLandmark lm) => _Point(lm.x, lm.y);
}

class _AbductionThresholds {
  final int normalMin, normalMax, transMin, transMax, passMin, passMax;
  final double armsTooHigh, elbowBentThresh, asymmetryThresh, backThresh;

  _AbductionThresholds({
    double? overrideArmsTooHigh,
    double? overrideElbowBent,
    double? overrideAsymmetry,
    double? overrideBack,
  })  : normalMin = 0, normalMax = 45,
        transMin = 45, transMax = 64,
        passMin = 64, passMax = 120,
        armsTooHigh = overrideArmsTooHigh ?? 125,
        elbowBentThresh = overrideElbowBent ?? 140,
        asymmetryThresh = overrideAsymmetry ?? 20,
        backThresh = overrideBack ?? 10;
}

// ── Shared result + enum used by all exercise logics ──────────────────────────

enum ExerciseMode { beginner, pro }

class ExerciseResult {
  final int correctReps;
  final int incorrectReps;
  final int currentSet;
  final int effectiveSetCount;
  final String feedback;
  final bool isRepCounted;
  final bool sessionComplete;
  final bool jointsDetected;
  final String? displayMessage;
  final bool waitingForReset;
  final int messageTimer;
  final double primaryAngle;

  const ExerciseResult({
    required this.correctReps,
    required this.incorrectReps,
    required this.currentSet,
    required this.effectiveSetCount,
    required this.feedback,
    required this.isRepCounted,
    required this.sessionComplete,
    required this.jointsDetected,
    required this.displayMessage,
    required this.waitingForReset,
    required this.messageTimer,
    required this.primaryAngle,
  });

  Map<String, dynamic> toWorkoutMap({int? targetSets, String? exerciseName}) {
    final totalReps = correctReps + incorrectReps;
    final accuracy = totalReps > 0 ? (correctReps / totalReps * 100) : 0.0;
    return {
      'exercise': exerciseName ?? 'Unknown',
      'correctReps': correctReps,
      'incorrectReps': incorrectReps,
      'totalReps': totalReps,
      'accuracy': accuracy,
      'currentSet': currentSet,
      'effectiveSets': effectiveSetCount,
      'sessionComplete': sessionComplete,
      'targetSets': targetSets,
    };
  }
}

class _Point {
  final double x, y;
  const _Point(this.x, this.y);
}
