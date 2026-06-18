import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'pose_analyzer.dart';

/// Complete squat counting logic ported from Python process_frame_squat.py
/// Handles state machine, rep counting, and real-time feedback.
///
/// State machine: s1 (NORMAL) -> s2 (TRANS) -> s3 (PASS) -> s1 = 1 rep
class SquatProcessor {
  final PoseThresholdConfig thresholds;
  final int targetReps;
  final int targetSets;

  // State tracking
  int _currentSet = 1;
  int _correctReps = 0;
  int _incorrectReps = 0;
  int _totalCorrectReps = 0; // Track cumulative correct reps across all sets
  int _totalIncorrectReps =
      0; // Track cumulative incorrect reps across all sets
  List<String> _stateSequence = [];
  String? _currentState;

  // Feedback tracking
  bool _lowerHips = false;
  bool _incorrectPosture = false;
  Map<int, bool> _displayText = {0: false, 1: false, 2: false, 3: false};

  SquatProcessor({
    required this.thresholds,
    required this.targetReps,
    required this.targetSets,
  });

  int get correctReps => _correctReps;
  int get incorrectReps => _incorrectReps;
  int get totalCorrectReps => _totalCorrectReps;
  int get totalIncorrectReps => _totalIncorrectReps;
  int get currentSet => _currentSet;
  bool get sessionComplete => _currentSet > targetSets;

  void reset() {
    _currentSet = 1;
    _correctReps = 0;
    _incorrectReps = 0;
    _totalCorrectReps = 0;
    _totalIncorrectReps = 0;
    _stateSequence = [];
    _currentState = null;
    _lowerHips = false;
    _incorrectPosture = false;
    _displayText = {0: false, 1: false, 2: false, 3: false};
  }

  /// Process a single frame of pose data
  /// Input: Pose from google_mlkit_pose_detection
  /// Output: SquatProcessResult with counts and feedback
  SquatProcessResult processFrame(Pose pose) {
    final landmarks = pose.landmarks;
    if (landmarks.isEmpty) {
      return SquatProcessResult(
        correctReps: _correctReps,
        incorrectReps: _incorrectReps,
        currentSet: _currentSet,
        feedback: _generateFeedback(),
        isRepCounted: false,
      );
    }

    // Create landmark map from list (MediaPipe indices)
    final Map<int, PoseLandmark> lmMap = {};
    for (final lm in landmarks.values) {
      lmMap[lm.type.index] = lm;
    }

    // MediaPipe landmark indices
    final leftHip = lmMap[23];
    final leftKnee = lmMap[25];
    final leftAnkle = lmMap[27];
    final leftShoulder = lmMap[11];
    final rightHip = lmMap[24];
    final rightKnee = lmMap[26];
    final rightAnkle = lmMap[28];
    final rightShoulder = lmMap[12];

    // Choose side robustly: prefer side with both shoulder and ankle visible.
    // If only one side has required joints, use that side.
    final leftAvailable = leftShoulder != null &&
        leftAnkle != null &&
        leftHip != null &&
        leftKnee != null;
    final rightAvailable = rightShoulder != null &&
        rightAnkle != null &&
        rightHip != null &&
        rightKnee != null;

    if (!leftAvailable && !rightAvailable) {
      // Fallback: try any side with hip+knee+ankle (shoulder may be missing for angle calc at hip)
      final leftMinimal =
          leftHip != null && leftKnee != null && leftAnkle != null;
      final rightMinimal =
          rightHip != null && rightKnee != null && rightAnkle != null;
      if (!leftMinimal && !rightMinimal) {
        return SquatProcessResult(
          correctReps: _correctReps,
          incorrectReps: _incorrectReps,
          currentSet: _currentSet,
          feedback: 'No pose detected',
          isRepCounted: false,
        );
      }
    }

    // Determine which side to use (side with larger vertical span)
    bool useLeft;
    if (leftAvailable && rightAvailable) {
      final leftSpan = (leftAnkle.y - leftShoulder.y).abs();
      final rightSpan = (rightAnkle.y - rightShoulder.y).abs();
      useLeft = leftSpan >= rightSpan;
    } else if (leftAvailable) {
      useLeft = true;
    } else if (rightAvailable) {
      useLeft = false;
    } else {
      // Minimal fallback
      useLeft = (leftHip != null && leftKnee != null && leftAnkle != null);
    }

    final shoulder = useLeft ? leftShoulder : rightShoulder;
    final hip = useLeft ? leftHip : rightHip;
    final knee = useLeft ? leftKnee : rightKnee;
    final ankle = useLeft ? leftAnkle : rightAnkle;

    // Ensure chosen side joints exist
    if (hip == null || knee == null || ankle == null) {
      return SquatProcessResult(
        correctReps: _correctReps,
        incorrectReps: _incorrectReps,
        currentSet: _currentSet,
        feedback: 'No pose detected',
        isRepCounted: false,
      );
    }

    // Calculate angles: vertical angle from hip/knee point to ground
    final hipVertAngle = shoulder != null
        ? _findAngle(
            _Point(shoulder.x, shoulder.y),
            _Point(hip.x, 0), // vertical reference
            _Point(hip.x, hip.y),
          )
        : 0.0;

    final kneeVertAngle = _findAngle(
      _Point(hip.x, hip.y),
      _Point(knee.x, 0), // vertical reference
      _Point(knee.x, knee.y),
    );

    final ankleVertAngle = _findAngle(
      _Point(knee.x, knee.y),
      _Point(ankle.x, 0), // vertical reference
      _Point(ankle.x, ankle.y),
    );

    // Get current state based on knee angle
    final state = _getState(kneeVertAngle.toInt());
    _currentState = state;
    debugPrint(
        '[SquatProcessor] kneeAngle=${kneeVertAngle.toStringAsFixed(1)}°, state=$state, seq=$_stateSequence');
    _updateStateSequence(state);

    bool repCounted = false;

    // State machine logic: s1 -> s2 -> s3 -> s1 = 1 rep
    if (state == 's1') {
      debugPrint(
          '[SquatProcessor] In s1, checking seq=$_stateSequence, incorrectPosture=$_incorrectPosture');
      // Python logic: count CORRECT when both s2 and s3 occurred in sequence
      // before returning to s1, and posture is not incorrect.
      if (_stateSequence.contains('s2') &&
          _stateSequence.contains('s3') &&
          !_incorrectPosture) {
        _correctReps++;
        _totalCorrectReps++;
        repCounted = true;
        debugPrint(
            '[SquatProcessor] Correct rep #$_correctReps (total: $_totalCorrectReps)');
      } else if (_stateSequence.contains('s2') &&
          !_stateSequence.contains('s3')) {
        // Incomplete squat (reached TRANS only)
        _incorrectReps++;
        _totalIncorrectReps++;
        repCounted = true;
        debugPrint(
            '[SquatProcessor] Incorrect rep #$_incorrectReps (total: $_totalIncorrectReps) (incomplete)');
      } else if (_incorrectPosture) {
        // Squat with bad posture
        _incorrectReps++;
        _totalIncorrectReps++;
        repCounted = true;
        debugPrint(
            '[SquatProcessor] Incorrect rep #$_incorrectReps (total: $_totalIncorrectReps) (posture)');
      }

      // If no rep was counted, log why
      if (!repCounted && _stateSequence.isNotEmpty) {
        debugPrint(
            '[SquatProcessor] ⚠️ No rep counted - seq=$_stateSequence (need s2 AND s3)');
      }

      _stateSequence = [];
      _incorrectPosture = false;

      // Check if set is complete
      final totalReps = _correctReps + _incorrectReps;
      if (totalReps >= targetReps) {
        _currentSet++;
        debugPrint('[SquatProcessor] Set $_currentSet complete!');
        _correctReps = 0; // Reset per-set counters
        _incorrectReps = 0;
      }
    }

    // Feedback logic (posture validation)
    _displayText = {0: false, 1: false, 2: false, 3: false};

    if (hipVertAngle > thresholds.hipThreshMax) {
      _displayText[0] = true; // BEND FORWARD
    } else if (hipVertAngle < thresholds.hipThreshMin &&
        _stateSequence.where((s) => s == 's2').length == 1) {
      _displayText[1] = true; // BEND BACKWARDS
    }

    if (kneeVertAngle > thresholds.kneeThreshMin &&
        kneeVertAngle < thresholds.kneeThreshMid &&
        _stateSequence.where((s) => s == 's2').length == 1) {
      _lowerHips = true;
    } else if (kneeVertAngle > thresholds.kneeThreshMax) {
      _displayText[3] = true; // SQUAT TOO DEEP
      _incorrectPosture = true;
    } else {
      _lowerHips = false;
    }

    if (ankleVertAngle > thresholds.ankleThresh) {
      _displayText[2] = true; // KNEE FALLING OVER TOE
      _incorrectPosture = true;
    }

    if (_stateSequence.contains('s3')) {
      _lowerHips = false;
    }

    return SquatProcessResult(
      correctReps: _correctReps,
      incorrectReps: _incorrectReps,
      currentSet: _currentSet,
      feedback: _generateFeedback(),
      isRepCounted: repCounted,
      kneeAngle: kneeVertAngle,
      hipAngle: hipVertAngle,
      ankleAngle: ankleVertAngle,
      currentState: _currentState,
    );
  }

  /// Convert knee angle to state (s1=NORMAL, s2=TRANS, s3=PASS)
  /// Matches Python _get_state from process_frame_squat.py
  String? _getState(int kneeAngle) {
    final normal = thresholds.hipKneeVertNormal;
    final trans = thresholds.hipKneeVertTrans;
    final pass = thresholds.hipKneeVertPass;

    if (kneeAngle >= normal.$1 && kneeAngle <= normal.$2) {
      return 's1';
    } else if (kneeAngle >= trans.$1 && kneeAngle <= trans.$2) {
      return 's2';
    } else if (kneeAngle >= pass.$1 && kneeAngle <= pass.$2) {
      return 's3';
    }
    return null;
  }

  /// Update state sequence tracking
  /// Matches Python _update_state_sequence logic from process_frame_squat.py
  void _updateStateSequence(String? state) {
    if (state == null) return;

    if (state == 's2') {
      final s2Count = _stateSequence.where((s) => s == 's2').length;
      final hasS3 = _stateSequence.contains('s3');

      // Add s2 only once unless we've seen s3 (in which case add it again on second pass)
      if ((!hasS3 && s2Count == 0) || (hasS3 && s2Count == 1)) {
        _stateSequence.add(state);
      }
    } else if (state == 's3') {
      // Only add s3 if we've seen s2 first and don't already have s3
      if (!_stateSequence.contains(state) && _stateSequence.contains('s2')) {
        _stateSequence.add(state);
      }
    }
  }

  /// Calculate angle between two 2D points with reference point
  /// Converts Python: cos_theta = dot(p1_ref, p2_ref) / (norm(p1_ref) * norm(p2_ref))
  /// From utils.py find_angle function
  double _findAngle(_Point p1, _Point p2, _Point refPt) {
    final p1Ref = _Point(p1.x - refPt.x, p1.y - refPt.y);
    final p2Ref = _Point(p2.x - refPt.x, p2.y - refPt.y);

    // Calculate dot product
    final dotProduct = p1Ref.x * p2Ref.x + p1Ref.y * p2Ref.y;

    // Calculate norms (magnitudes)
    final norm1 = sqrt(p1Ref.x * p1Ref.x + p1Ref.y * p1Ref.y);
    final norm2 = sqrt(p2Ref.x * p2Ref.x + p2Ref.y * p2Ref.y);

    if (norm1 == 0 || norm2 == 0) return 0;

    // Calculate cosine of angle
    final cosTheta = dotProduct / (norm1 * norm2);
    final clipped = cosTheta.clamp(-1.0, 1.0);

    // Calculate angle in radians then convert to degrees
    final theta = acos(clipped);
    final degree = (180 / pi) * theta;

    return degree;
  }

  /// Generate feedback messages based on current state
  /// Maps to FEEDBACK_ID_MAP from process_frame_squat.py
  String _generateFeedback() {
    if (_displayText[0] == true) return 'BEND FORWARD';
    if (_displayText[1] == true) return 'BEND BACKWARDS';
    if (_displayText[2] == true) return 'KNEE FALLING OVER TOE';
    if (_displayText[3] == true) return 'SQUAT TOO DEEP';
    if (_lowerHips) return 'LOWER YOUR HIPS';
    return 'Good form';
  }
}

/// Result from processing a single frame
class SquatProcessResult {
  final int correctReps;
  final int incorrectReps;
  final int currentSet;
  final String feedback;
  final bool isRepCounted;
  final double kneeAngle;
  final double hipAngle;
  final double ankleAngle;
  final String? currentState;

  SquatProcessResult({
    required this.correctReps,
    required this.incorrectReps,
    required this.currentSet,
    required this.feedback,
    required this.isRepCounted,
    this.kneeAngle = 0,
    this.hipAngle = 0,
    this.ankleAngle = 0,
    this.currentState,
  });
}

/// 2D point helper class for angle calculations
class _Point {
  final double x;
  final double y;

  _Point(this.x, this.y);
}
