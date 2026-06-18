import 'dart:math';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'abduction_logic.dart' show ExerciseResult, ExerciseMode;
import '../models/exercise_program.dart';

/// Dart port of process_frame_internal_rotation.py
/// Tracks shoulder internal rotation: elbow fixed at side, wrist sweeps inward across torso
class InternalRotationLogic {
  final ExerciseMode mode;
  final int targetReps;
  final int targetSets;

  late final _IRThresholds _t;

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

  // 3 feedback flags: 0=ELBOW_FLARE, 1=WRIST_ALIGNMENT, 2=TORSO_TWIST
  Map<int, bool> _displayText = {0: false, 1: false, 2: false};
  Map<int, int> _countFrames = {0: 0, 1: 0, 2: 0};

  String? _activeArm; // 'left' or 'right'
  double? _baseShoulderWidth;

  DateTime _startInactiveTime = DateTime.now();
  double _inactiveTime = 0.0;
  static const double _inactiveThresh = 15.0;

  InternalRotationLogic({
    required this.mode,
    required this.targetReps,
    required this.targetSets,
    ExerciseThresholdOverrides? thresholds,
  }) {
    _t = _IRThresholds(
      overrideElbowFlare: thresholds?.elbowFlareMax,
      overrideWristAlign: thresholds?.wristAlignMax,
      overrideTorsoTwist: thresholds?.torsoTwistMin,
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
    _displayText = {0: false, 1: false, 2: false};
    _countFrames = {0: 0, 1: 0, 2: 0};
    _activeArm = null;
    _baseShoulderWidth = null;
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

    if ([leftShoulder, rightShoulder, leftElbow, rightElbow,
         leftWrist, rightWrist].any((e) => e == null)) {
      return _emptyResult(jointsDetected: false, message: 'Upper body not visible');
    }

    final ls = leftShoulder!;
    final rs = rightShoulder!;
    final le = leftElbow!;
    final re = rightElbow!;
    final lw = leftWrist!;
    final rw = rightWrist!;

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
        _activeArm = null;
      }
    }

    // === 2. SHOULDER WIDTH + ARM LOCK ===
    final shoulderWidth = (rs.x - ls.x).abs().clamp(1.0, double.infinity);

    if (_currentState == 's1' || _baseShoulderWidth == null) {
      _baseShoulderWidth = shoulderWidth;
    }

    final leftElbowAngle = _angle(_pt(ls), _pt(lw), _pt(le));
    final rightElbowAngle = _angle(_pt(rs), _pt(rw), _pt(re));

    _activeArm ??= (90 - leftElbowAngle).abs() < (90 - rightElbowAngle).abs()
          ? 'left'
          : 'right';

    double rotationRatio;
    double elbowFlareRatio;
    double wristYDiff;
    if (_activeArm == 'left') {
      elbowFlareRatio = (le.x - ls.x) / shoulderWidth;
      rotationRatio = (lw.x - le.x) / shoulderWidth;
      wristYDiff = (le.y - lw.y).abs();
    } else {
      elbowFlareRatio = (rs.x - re.x) / shoulderWidth;
      rotationRatio = (re.x - rw.x) / shoulderWidth;
      wristYDiff = (re.y - rw.y).abs();
    }

    // === 3. UPDATE STATE ===
    _currentState = _getState(rotationRatio);
    _updateStateSequence(_currentState);

    // === 4. FEEDBACK CHECKS ===
    if (elbowFlareRatio > _t.elbowFlareThresh) {
      _displayText[0] = true;
      if (_currentState != 's1') _incorrectPosture = true;
    }
    // Wrist alignment: forearm should be roughly horizontal (elbow.y ≈ wrist.y).
    // Python normalises wristYDiff by frame_height. We don't have frame height
    // here, so use ~3× shoulder width as a stable torso-height proxy. This puts
    // the threshold ratio in the same scale Python's was tuned for.
    final heightProxy = shoulderWidth * 3.0;
    if (wristYDiff / heightProxy > _t.wristAlignmentThresh) {
      _displayText[1] = true;
      if (_currentState != 's1') _incorrectPosture = true;
    }
    final widthRatio = shoulderWidth / (_baseShoulderWidth ?? shoulderWidth);
    if (widthRatio < _t.torsoTwistThresh) {
      _displayText[2] = true;
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
        _activeArm = null;
        _inactiveTime = 0.0;
        _startInactiveTime = DateTime.now();
      }
    } else {
      _startInactiveTime = DateTime.now();
      _inactiveTime = 0.0;
    }

    // === 7. FEEDBACK PERSISTENCE ===
    for (int i = 0; i < 3; i++) {
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
      primaryAngle: rotationRatio,
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

  String? _getState(double ratio) {
    if (ratio >= _t.normalMin && ratio <= _t.normalMax) return 's1';
    if (ratio >= _t.transMin && ratio <= _t.transMax) return 's2';
    if (ratio >= _t.passMin && ratio <= _t.passMax) return 's3';
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
    for (int i = 0; i < 3; i++) {
      if (_countFrames[i]! > 0) {
        switch (i) {
          case 0: return 'ELBOW LEFT YOUR SIDE';
          case 1: return 'KEEP FOREARM LEVEL';
          case 2: return "DON'T TWIST TORSO";
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

class _IRThresholds {
  final double normalMin, normalMax, transMin, transMax, passMin, passMax;
  final double elbowFlareThresh, wristAlignmentThresh, torsoTwistThresh;

  _IRThresholds({
    double? overrideElbowFlare,
    double? overrideWristAlign,
    double? overrideTorsoTwist,
  })  : normalMin = -0.05, normalMax = 1.0,
        transMin = -0.25, transMax = -0.05,
        passMin = -1.0, passMax = -0.25,
        elbowFlareThresh = overrideElbowFlare ?? 0.4,
        wristAlignmentThresh = overrideWristAlign ?? 0.22,
        torsoTwistThresh = overrideTorsoTwist ?? 0.85;
}

class _Point {
  final double x, y;
  const _Point(this.x, this.y);
}
