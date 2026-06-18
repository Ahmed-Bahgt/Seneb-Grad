import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Dart port of process_frame_squat.py / thresholds.py / utils.py
/// Updated to match Python ProcessFrameSquat class logic with improved state handling
class SquatLogic {
  final SquatMode mode;
  final int targetReps;
  final int targetSets;

  late final SquatThresholds _thresholds;

  // Counters
  int _setCount = 0;
  int _squatCount = 0; // correct reps
  int _improperCount = 0; // incorrect reps

  // State machine
  List<String> _stateSeq = [];
  String? _currentState;
  String? _prevState;

  // Freeze/reset logic
  bool _waitingForReset = false;
  int _messageTimer = 0; // frames (~30fps, Python uses 90)
  String? _freezeMessage;
  int _effectiveSetCount = 0; // sets with accuracy >= 70%
  double _lastSetAccuracy = 0.0;

  // Feedback flags with frame counting (matching Python's COUNT_FRAMES)
  Map<int, bool> _displayText = {0: false, 1: false, 2: false, 3: false};
  Map<int, int> _countFrames = {0: 0, 1: 0, 2: 0, 3: 0}; // For feedback persistence
  bool _lowerHips = false;
  bool _incorrectPosture = false;

  // Inactivity tracking (both front and side view)
  DateTime _startInactiveTime = DateTime.now();
  DateTime _startInactiveTimeFront = DateTime.now();
  double _inactiveTime = 0.0;
  double _inactiveTimeFront = 0.0;
  static const double inactiveThresh = 5.0; // seconds

  // Display message
  String _displayMessage = '';

  SquatLogic({
    required this.mode,
    required this.targetReps,
    required this.targetSets,
  }) {
    _thresholds = mode == SquatMode.beginner
        ? SquatThresholds.beginner()
        : SquatThresholds.pro();
  }

  int get effectiveSetCount => _effectiveSetCount;

  void reset() {
    _setCount = 0;
    _squatCount = 0;
    _improperCount = 0;
    _effectiveSetCount = 0;
    _lastSetAccuracy = 0.0;
    _stateSeq = [];
    _currentState = null;
    _prevState = null;
    _waitingForReset = false;
    _messageTimer = 0;
    _freezeMessage = null;
    _displayText = {0: false, 1: false, 2: false, 3: false};
    _countFrames = {0: 0, 1: 0, 2: 0, 3: 0};
    _lowerHips = false;
    _incorrectPosture = false;
    _displayMessage = '';
    _inactiveTime = 0.0;
    _inactiveTimeFront = 0.0;
    _startInactiveTime = DateTime.now();
    _startInactiveTimeFront = DateTime.now();
  }

  SquatResult processFrame(Pose pose) {
    final lm = pose.landmarks;
    if (lm.isEmpty) {
      _displayMessage = 'No person detected';
      return _emptyResult(jointsDetected: false, displayMessage: _displayMessage);
    }

    // === 1. HANDLE RESET FREEZE LOGIC (Global Timer) ===
    if (_waitingForReset) {
      if (_messageTimer > 0) {
        _messageTimer -= 1;
      }
      // If Timer finishes, tally effective set then reset for next set
      if (_messageTimer <= 0) {
        if (_lastSetAccuracy >= 70.0) _effectiveSetCount++;
        _waitingForReset = false;
        _squatCount = 0;
        _improperCount = 0;
        _setCount = (_setCount + 1).clamp(0, targetSets);
      }
    }

    // Get landmarks
    final leftShoulder = lm[PoseLandmarkType.leftShoulder];
    final rightShoulder = lm[PoseLandmarkType.rightShoulder];
    final leftHip = lm[PoseLandmarkType.leftHip];
    final rightHip = lm[PoseLandmarkType.rightHip];
    final leftKnee = lm[PoseLandmarkType.leftKnee];
    final rightKnee = lm[PoseLandmarkType.rightKnee];
    final leftAnkle = lm[PoseLandmarkType.leftAnkle];
    final rightAnkle = lm[PoseLandmarkType.rightAnkle];
    final leftFoot = lm[PoseLandmarkType.leftFootIndex];
    final rightFoot = lm[PoseLandmarkType.rightFootIndex];
    final nose = lm[PoseLandmarkType.nose];

    if ([
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
      leftKnee,
      rightKnee,
      leftAnkle,
      rightAnkle,
      leftFoot,
      rightFoot,
      nose,
    ].any((e) => e == null)) {
      _displayMessage = 'Full body not visible';
      return _emptyResult(jointsDetected: false, displayMessage: _displayMessage);
    }

    // Calculate offset angle (posture alignment)
    final offsetAngle = _findAngle(
      _Point(leftShoulder!.x, leftShoulder.y),
      _Point(rightShoulder!.x, rightShoulder.y),
      _Point(nose!.x, nose.y),
    );

    // === BRANCH A: CAMERA NOT ALIGNED (User turning away or inactive) ===
    if (offsetAngle > _thresholds.offsetThresh) {
      // Inactivity Logic (Front View)
      final now = DateTime.now();
      _inactiveTimeFront += now.difference(_startInactiveTimeFront).inMilliseconds / 1000;
      _startInactiveTimeFront = now;

      if (_inactiveTimeFront >= inactiveThresh) {
        _squatCount = 0;
        _improperCount = 0;
        _inactiveTimeFront = 0.0;
        _startInactiveTimeFront = DateTime.now();
      }

      // Reset state tracking for misaligned posture
      _prevState = null;
      _currentState = null;
      _incorrectPosture = false;
      _stateSeq = [];
      _displayText = {0: false, 1: false, 2: false, 3: false};
      _countFrames = {0: 0, 1: 0, 2: 0, 3: 0};
      _startInactiveTime = DateTime.now();

      _displayMessage = 'POSTURE NOT ALIGNED PROPERLY!!! (TURN LEFT or RIGHT)';
      return _buildResult(
        hipAngle: 0,
        kneeAngle: 0,
        ankleAngle: 0,
        jointsDetected: true,
        displayMessage: _displayMessage,
        repCounted: false,
        sessionComplete: _setCount >= targetSets,
      );
    }

    // === BRANCH B: CAMERA ALIGNED (Active Training) ===
    _inactiveTimeFront = 0.0;
    _startInactiveTimeFront = DateTime.now();

    // Choose side with bigger shoulder-to-foot span
    final leftSpan = (leftFoot!.y - leftShoulder.y).abs();
    final rightSpan = (rightFoot!.y - rightShoulder.y).abs();
    final useLeft = leftSpan >= rightSpan;

    final shoulder = useLeft ? leftShoulder : rightShoulder;
    final hip = useLeft ? leftHip! : rightHip!;
    final knee = useLeft ? leftKnee! : rightKnee!;
    final ankle = useLeft ? leftAnkle! : rightAnkle!;

    // Calculate angles (vertical reference)
    final hipAngle = _findAngle(
      _Point(shoulder.x, shoulder.y),
      _Point(hip.x, 0),
      _Point(hip.x, hip.y),
    );
    final kneeAngle = _findAngle(
      _Point(hip.x, hip.y),
      _Point(knee.x, 0),
      _Point(knee.x, knee.y),
    );
    final ankleAngle = _findAngle(
      _Point(knee.x, knee.y),
      _Point(ankle.x, 0),
      _Point(ankle.x, ankle.y),
    );

    // === 2. UPDATE STATE ===
    _currentState = _getState(kneeAngle.toInt());
    _updateStateSequence(_currentState);

    // === 3. CHECK FEEDBACK & POSTURE (Runs EVERY frame) ===
    if (hipAngle > _thresholds.hipThreshMax) {
      _displayText[0] = true; // BEND FORWARD
    } else if (hipAngle < _thresholds.hipThreshMin &&
        _stateSeq.where((s) => s == 's2').length == 1) {
      _displayText[1] = true; // BEND BACKWARDS
    }

    if (kneeAngle > _thresholds.kneeThreshMin &&
        kneeAngle < _thresholds.kneeThreshMid &&
        _stateSeq.where((s) => s == 's2').length == 1) {
      _lowerHips = true;
    } else if (kneeAngle > _thresholds.kneeThreshMax) {
      _displayText[3] = true; // SQUAT TOO DEEP
      _incorrectPosture = true;
    }

    if (ankleAngle > _thresholds.ankleThresh) {
      _displayText[2] = true; // KNEE FALLING OVER TOE
      _incorrectPosture = true;
    }

    // === 4. COUNTING LOGIC (Only runs if active) ===
    bool repCounted = false;
    if (!_waitingForReset) {
      if (_currentState == 's1') {
        // Valid Rep: complete sequence without posture issues
        if (_stateSeq.length == 3 && !_incorrectPosture) {
          _squatCount += 1;
          repCounted = true;
          debugPrint('[SquatLogic] ✅ CORRECT REP #$_squatCount');
        }
        // Invalid Rep cases
        else if (_stateSeq.contains('s2') && _stateSeq.length == 1) {
          _improperCount += 1;
          repCounted = true;
          debugPrint('[SquatLogic] ❌ INCORRECT (incomplete) #$_improperCount');
        } else if (_incorrectPosture) {
          _improperCount += 1;
          repCounted = true;
          debugPrint('[SquatLogic] ❌ INCORRECT (posture) #$_improperCount');
        }

        // Reset all flags for the NEXT REP
        _stateSeq = [];
        _incorrectPosture = false;
        _lowerHips = false;
        _displayText = {0: false, 1: false, 2: false, 3: false};
        _countFrames = {0: 0, 1: 0, 2: 0, 3: 0};

        // Check limit / sets
        final totalReps = _squatCount + _improperCount;
        if (totalReps >= targetReps) {
          _lastSetAccuracy = totalReps > 0 ? (_squatCount / totalReps * 100) : 0.0;
          _waitingForReset = true;
          _messageTimer = 90; // ~3 seconds at 30 fps
          final nextSet = _setCount + 1;
          if (nextSet >= targetSets) {
            _freezeMessage = 'Whole Training is Done!';
          } else {
            _freezeMessage = 'Well Done! Set $nextSet Finished';
          }
          debugPrint('[SquatLogic] 🔄 FREEZE: totalReps=$totalReps');
        }
      }
    }

    // === 5. INACTIVITY CHECK (Side view) ===
    bool displayInactivity = false;
    if (_currentState == _prevState) {
      final now = DateTime.now();
      _inactiveTime += now.difference(_startInactiveTime).inMilliseconds / 1000;
      _startInactiveTime = now;

      if (_inactiveTime >= inactiveThresh) {
        _squatCount = 0;
        _improperCount = 0;
        displayInactivity = true;
      }
    } else {
      _startInactiveTime = DateTime.now();
      _inactiveTime = 0.0;
    }

    if (displayInactivity) {
      _startInactiveTime = DateTime.now();
      _inactiveTime = 0.0;
    }

    // Clear LOWER_HIPS if in s3
    if (_stateSeq.contains('s3')) {
      _lowerHips = false;
    }

    // Update frame count for feedback persistence — clear after 30 frames
    for (int i = 0; i < 4; i++) {
      if (_displayText[i] == true) {
        _countFrames[i] = (_countFrames[i]! + 1);
        if (_countFrames[i]! > 30) {
          _displayText[i] = false;
          _countFrames[i] = 0;
        }
      }
    }

    // Update previous state
    if (_currentState != null) {
      _prevState = _currentState;
    }

    final sessionComplete = _setCount >= targetSets && !_waitingForReset;
    final message = _waitingForReset ? _freezeMessage : _displayMessage;

    return _buildResult(
      hipAngle: hipAngle,
      kneeAngle: kneeAngle,
      ankleAngle: ankleAngle,
      jointsDetected: true,
      displayMessage: message,
      repCounted: repCounted,
      sessionComplete: sessionComplete,
    );
  }

  SquatResult _emptyResult({
    required bool jointsDetected,
    String? displayMessage,
  }) {
    return SquatResult(
      correctReps: _squatCount,
      incorrectReps: _improperCount,
      currentSet: _setCount,
      effectiveSetCount: _effectiveSetCount,
      feedback: _generateFeedback(),
      isRepCounted: false,
      hipAngle: 0,
      kneeAngle: 0,
      ankleAngle: 0,
      currentState: _currentState,
      sessionComplete: _setCount >= targetSets,
      jointsDetected: jointsDetected,
      displayMessage: displayMessage,
      waitingForReset: _waitingForReset,
      messageTimer: _messageTimer,
    );
  }

  SquatResult _buildResult({
    required double hipAngle,
    required double kneeAngle,
    required double ankleAngle,
    required bool jointsDetected,
    String? displayMessage,
    required bool repCounted,
    required bool sessionComplete,
  }) {
    return SquatResult(
      correctReps: _squatCount,
      incorrectReps: _improperCount,
      currentSet: _setCount,
      effectiveSetCount: _effectiveSetCount,
      feedback: _generateFeedback(),
      isRepCounted: repCounted,
      hipAngle: hipAngle,
      kneeAngle: kneeAngle,
      ankleAngle: ankleAngle,
      currentState: _currentState,
      sessionComplete: sessionComplete,
      jointsDetected: jointsDetected,
      displayMessage: displayMessage,
      waitingForReset: _waitingForReset,
      messageTimer: _messageTimer,
    );
  }

  String? _getState(int kneeAngle) {
    if (kneeAngle >= _thresholds.normalMin && kneeAngle <= _thresholds.normalMax) {
      return 's1';
    } else if (kneeAngle >= _thresholds.transMin && kneeAngle <= _thresholds.transMax) {
      return 's2';
    } else if (kneeAngle >= _thresholds.passMin && kneeAngle <= _thresholds.passMax) {
      return 's3';
    }
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

  double _findAngle(_Point p1, _Point p2, _Point refPt) {
    final p1Ref = _Point(p1.x - refPt.x, p1.y - refPt.y);
    final p2Ref = _Point(p2.x - refPt.x, p2.y - refPt.y);

    final dot = p1Ref.x * p2Ref.x + p1Ref.y * p2Ref.y;
    final norm1 = sqrt(p1Ref.x * p1Ref.x + p1Ref.y * p1Ref.y);
    final norm2 = sqrt(p2Ref.x * p2Ref.x + p2Ref.y * p2Ref.y);
    if (norm1 == 0 || norm2 == 0) return 0;

    final cosTheta = (dot / (norm1 * norm2)).clamp(-1.0, 1.0);
    return (180 / pi) * acos(cosTheta);
  }

  String _generateFeedback() {
    // Check which feedback is active (based on _countFrames for persistence)
    for (int i = 0; i < 4; i++) {
      if (_countFrames[i]! > 0) {
        switch (i) {
          case 0:
            return 'BEND FORWARD';
          case 1:
            return 'BEND BACKWARDS';
          case 2:
            return 'KNEE FALLING OVER TOE';
          case 3:
            return 'SQUAT TOO DEEP';
        }
      }
    }
    
    if (_lowerHips) return 'LOWER YOUR HIPS';
    if (_waitingForReset && _freezeMessage != null) return _freezeMessage!;
    return 'Good form';
  }
}

class SquatResult {
  final int correctReps;
  final int incorrectReps;
  final int currentSet;
  final int effectiveSetCount;
  final String feedback;
  final bool isRepCounted;
  final double kneeAngle;
  final double hipAngle;
  final double ankleAngle;
  final String? currentState;
  final bool sessionComplete;
  final bool jointsDetected;
  final String? displayMessage;
  final bool waitingForReset;
  final int messageTimer;

  const SquatResult({
    required this.correctReps,
    required this.incorrectReps,
    required this.currentSet,
    required this.effectiveSetCount,
    required this.feedback,
    required this.isRepCounted,
    required this.kneeAngle,
    required this.hipAngle,
    required this.ankleAngle,
    required this.currentState,
    required this.sessionComplete,
    required this.jointsDetected,
    required this.displayMessage,
    required this.waitingForReset,
    required this.messageTimer,
  });

  /// Converts to a map suitable for Firestore workout logging.
  /// timestamp is intentionally omitted — DatabaseService adds FieldValue.serverTimestamp().
  Map<String, dynamic> toWorkoutMap({int? targetSets}) {
    final totalReps = correctReps + incorrectReps;
    final accuracy = totalReps > 0 ? (correctReps / totalReps * 100) : 0.0;
    return {
      'correctReps': correctReps,
      'incorrectReps': incorrectReps,
      'totalReps': totalReps,
      'accuracy': accuracy,
      'currentSet': currentSet,
      'effectiveSets': effectiveSetCount,
      'feedback': feedback,
      'sessionComplete': sessionComplete,
      'kneeAngle': kneeAngle,
      'hipAngle': hipAngle,
      'ankleAngle': ankleAngle,
      'targetSets': targetSets,
    };
  }
}

class SquatThresholds {
  final int normalMin, normalMax;
  final int transMin, transMax;
  final int passMin, passMax;
  final int hipThreshMin, hipThreshMax;
  final int ankleThresh;
  final int kneeThreshMin, kneeThreshMid, kneeThreshMax;
  final double offsetThresh;

  SquatThresholds.beginner()
      : normalMin = 0,
        normalMax = 30,
        transMin = 35,
        transMax = 65,
        passMin = 70,
        passMax = 95,
        hipThreshMin = 10,
        hipThreshMax = 60,
        ankleThresh = 45,
        kneeThreshMin = 50,
        kneeThreshMid = 70,
        kneeThreshMax = 95,
        offsetThresh = 50;

  SquatThresholds.pro()
      : normalMin = 0,
        normalMax = 30,
        transMin = 35,
        transMax = 65,
        passMin = 80,
        passMax = 95,
        hipThreshMin = 15,
        hipThreshMax = 50,
        ankleThresh = 30,
        kneeThreshMin = 50,
        kneeThreshMid = 80,
        kneeThreshMax = 95,
        offsetThresh = 50;
}

enum SquatMode { beginner, pro }

class _Point {
  final double x, y;
  const _Point(this.x, this.y);
}
