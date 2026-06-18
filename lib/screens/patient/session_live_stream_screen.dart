import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../services/sql_service.dart';
import '../../utils/theme_provider.dart';
import '../../utils/squat_logic.dart';
import '../../utils/squat_processor.dart';
import '../../utils/pose_analyzer.dart';
import '../../utils/abduction_logic.dart';
import '../../utils/internal_rotation_logic.dart';
import '../../utils/lateral_raise_logic.dart';
import '../../widgets/pose_painter.dart';
import '../../utils/patient_profile_manager.dart';
import '../../utils/generic_exercise_processor.dart';
import '../../models/exercise_program.dart';

/// Live Stream Screen matching Live_Stream.py logic
class SessionLiveStreamScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const SessionLiveStreamScreen({super.key, this.onBack});

  @override
  State<SessionLiveStreamScreen> createState() =>
      _SessionLiveStreamScreenState();
}

class _SessionLiveStreamScreenState extends State<SessionLiveStreamScreen> {
  String _selectedMode = 'Beginner';
  int _targetReps = 10;
  int _targetSets = 3;
  String _assignedExercise = '';
  ExerciseProgram? _program;
  int _currentExerciseIndex = 0;
  bool _isStreamActive = false;
  bool _recordingConsent = true; // Patient consent to record session video
  bool _isProcessing = false;
  bool _calibrating = false;
  int _calibrationCounter = 0;
  List<Pose> _poses = [];
  bool _isSessionEnding = false;
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  String? _cameraError;
  PoseDetector? _poseDetector;
  late SquatProcessor _squatProcessor;
  AbductionLogic? _abductionLogic;
  InternalRotationLogic? _internalRotationLogic;
  LateralRaiseLogic? _lateralRaiseLogic;
  GenericExerciseProcessor? _genericProcessor;
  SquatResult? _lastResult;
  String? _selectedSide; // 'left' or 'right' based on shoulder-to-foot span
  List<CameraDescription> _availableCameras = [];
  int _currentCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadAssignedPlan();
    _initializeProcessor();
    _initializeCamera();
    _initializePoseDetectorAsync();
    // Refresh profile from Firestore in case doctor changed exercise assignment
    // while the patient was already logged in.
    if (!appDevMode) {
      PatientProfileManager().loadPatientProfile().then((_) {
        if (mounted && !_isStreamActive) {
          _loadAssignedPlan();
          // Re-initialize processors with the freshly loaded targets/mode.
          // _loadAssignedPlan only updates state vars; without this the
          // processors keep their initial defaults (10 reps × 3 sets, Beginner).
          _initializeProcessor();
        }
      });
    }
  }

  /// Returns 'front' or 'side' based on the current exercise.
  /// Squat is the only side-view exercise; everything else (Abduction, Internal
  /// Rotation, Lateral Raise) is front-view. Custom exercises read the view
  /// directly from the doctor's config.
  String _exerciseView() {
    if (_assignedExercise == 'Squat') return 'side';
    if (_assignedExercise == 'custom' &&
        _program != null &&
        _currentExerciseIndex < _program!.exercises.length) {
      final cfg = _program!.exercises[_currentExerciseIndex].customConfig;
      if (cfg != null) return cfg.view;
    }
    return 'front';
  }

  bool get _isFrontView => _exerciseView() == 'front';

  bool get _isUsingFrontCamera =>
      _availableCameras.isNotEmpty &&
      _availableCameras[_currentCameraIndex].lensDirection ==
          CameraLensDirection.front;

  void _loadAssignedPlan() {
    final profile = PatientProfileManager();
    final program = profile.exerciseProgram;

    if (program != null && program.exercises.isNotEmpty) {
      // Multi-exercise program assigned by doctor
      final first = program.exercises.first;
      setState(() {
        _program = program;
        _currentExerciseIndex = 0;
        _assignedExercise = first.type;
        _targetReps = first.targetReps;
        _targetSets = first.targetSets;
        _selectedMode = first.mode;
      });
    } else {
      // Legacy single-exercise fallback
      final type = profile.exerciseType;
      final sets = profile.exerciseSets;
      final reps = profile.exerciseReps;
      final mode = profile.exerciseMode;
      setState(() {
        _program = null;
        _assignedExercise = type;
        if (reps > 0) _targetReps = reps;
        if (sets > 0) _targetSets = sets;
        if (mode.isNotEmpty) _selectedMode = mode;
      });
    }
  }

  /// Switch to the next exercise in the program, re-initialise processors.
  void _advanceToNextExercise() {
    if (_program == null) return;
    final next = _currentExerciseIndex + 1;
    if (next >= _program!.exercises.length) return;
    final ex = _program!.exercises[next];
    setState(() {
      _currentExerciseIndex = next;
      _assignedExercise = ex.type;
      _targetReps = ex.targetReps;
      _targetSets = ex.targetSets;
      _selectedMode = ex.mode;
      _calibrating = false;
      _calibrationCounter = 0;
      _lastResult = null;
      _poses = [];
    });
    _initializeProcessor();
  }

  @override
  void dispose() {
    // Set flags to prevent further processing
    _isProcessing = true;
    _isStreamActive = false;

    // Clean up resources synchronously
    // Note: stopImageStream is async but we can't await in dispose
    // The _isStreamActive flag will prevent new frames from being processed
    _cameraController?.dispose();
    _poseDetector?.close();
    super.dispose();
  }

  Future<void> _initializePoseDetectorAsync() async {
    try {
      final options = PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      );
      _poseDetector = PoseDetector(options: options);
      if (mounted) {
        setState(() {}); // Notify that pose detector is ready
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Pose detector error: $e');
      }
    }
  }

  void _initializeProcessor() {
    final thresholds = _selectedMode == 'Beginner'
        ? PoseThresholdConfig.beginner()
        : PoseThresholdConfig.pro();
    final exMode = _selectedMode == 'Pro' ? ExerciseMode.pro : ExerciseMode.beginner;

    // Pull custom threshold overrides from the current program exercise (if any)
    ExerciseThresholdOverrides? overrides;
    if (_program != null && _currentExerciseIndex < _program!.exercises.length) {
      final t = _program!.exercises[_currentExerciseIndex].thresholds;
      if (!t.isEmpty) overrides = t;
    }

    _squatProcessor = SquatProcessor(
      thresholds: thresholds,
      targetReps: _targetReps,
      targetSets: _targetSets,
    );
    _abductionLogic = AbductionLogic(
        mode: exMode, targetReps: _targetReps, targetSets: _targetSets,
        thresholds: overrides);
    _internalRotationLogic = InternalRotationLogic(
        mode: exMode, targetReps: _targetReps, targetSets: _targetSets,
        thresholds: overrides);
    _lateralRaiseLogic = LateralRaiseLogic(
        mode: exMode, targetReps: _targetReps, targetSets: _targetSets,
        thresholds: overrides);

    // Custom exercise via GenericExerciseProcessor
    if (_assignedExercise == 'custom' && _program != null &&
        _currentExerciseIndex < _program!.exercises.length) {
      final cfg = _program!.exercises[_currentExerciseIndex].customConfig;
      if (cfg != null) {
        _genericProcessor = GenericExerciseProcessor(
            config: cfg, targetSets: _targetSets, repsPerSet: _targetReps);
      }
    } else {
      _genericProcessor = null;
    }
  }

  Future<void> _initializeCamera() async {
    if (mounted) setState(() => _cameraError = null);
    try {
      final status = await Permission.camera.request();
      if (status.isDenied) {
        if (mounted) {
          setState(() => _cameraError = 'Camera permission denied.\nTap "Settings" to enable it.');
          _showPermissionDeniedDialog();
        }
        return;
      }

      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No cameras found on this device.');
        return;
      }

      _cameraController = CameraController(
        _availableCameras[_currentCameraIndex],
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _isCameraInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  Future<void> _startSession() async {
    if (!_isCameraInitialized) return;

    _initializeProcessor();
    _squatProcessor.reset();
    _abductionLogic?.reset();
    _internalRotationLogic?.reset();
    _lateralRaiseLogic?.reset();
    _genericProcessor?.reset();

    setState(() {
      _isStreamActive = true;
      _calibrating = true;
      _calibrationCounter = 0;
      _lastResult = null;
      _poses = [];
    });

    // Re-enabling dual stream with lower resolution
    _isSessionEnding = false;
    if (_recordingConsent) {
      try {
        await _cameraController!.startVideoRecording(onAvailable: _processImage);
        debugPrint('[SessionLiveStream] Dual-stream started (Video + AI)');
      } catch (e) {
        debugPrint('[SessionLiveStream] Dual-stream failed, falling back to AI only: $e');
        await _cameraController!.startImageStream(_processImage);
      }
    } else {
      await _cameraController!.startImageStream(_processImage);
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing || _poseDetector == null || !_isStreamActive) return;
    _isProcessing = true;

    try {
      final inputImage = _convertToInputImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final poses = await _poseDetector!.processImage(inputImage);
      if (poses.isEmpty) {
        if (mounted) {
          setState(() {
            _poses = [];
            _lastResult = SquatResult(
              correctReps: _lastResult?.correctReps ?? 0,
              incorrectReps: _lastResult?.incorrectReps ?? 0,
              currentSet: _lastResult?.currentSet ?? 0,
              effectiveSetCount: _lastResult?.effectiveSetCount ?? 0,
              feedback: 'No person detected',
              isRepCounted: false,
              kneeAngle: 0,
              hipAngle: 0,
              ankleAngle: 0,
              currentState: null,
              sessionComplete: false,
              jointsDetected: false,
              displayMessage: 'No person detected',
              waitingForReset: false,
              messageTimer: 0,
            );
          });
        }
        _isProcessing = false;
        return;
      }

      // Calibration/visibility gating - exercise-aware (front vs side view)
      if (_calibrating) {
        final pose = poses.first;
        final nose = pose.landmarks[PoseLandmarkType.nose];
        final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
        final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
        final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
        final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
        final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
        final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
        final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
        final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
        final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
        final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

        String calibMessage;
        bool calibOk;

        if (_isFrontView) {
          // Front-view exercises (Abduction, Internal Rotation, Lateral Raise,
          // custom front-view): user faces the camera; ankles aren't required.
          // Skip the offset-angle check (no sideways stance) and verify the
          // upper body landmarks needed by these processors.
          _selectedSide = null; // Front view uses bilateral skeleton instead
          final bool shouldersOk = (leftShoulder?.likelihood ?? 0) > 0.5 &&
              (rightShoulder?.likelihood ?? 0) > 0.5;
          final bool elbowsOk = (leftElbow?.likelihood ?? 0) > 0.5 &&
              (rightElbow?.likelihood ?? 0) > 0.5;
          final bool wristsOk = (leftWrist?.likelihood ?? 0) > 0.5 &&
              (rightWrist?.likelihood ?? 0) > 0.5;
          final bool hipsOk = (leftHip?.likelihood ?? 0) > 0.5 &&
              (rightHip?.likelihood ?? 0) > 0.5;

          calibOk = shouldersOk && elbowsOk && wristsOk && hipsOk;
          if (!shouldersOk) {
            calibMessage = 'MOVE BACK SO BOTH SHOULDERS ARE VISIBLE';
          } else if (!elbowsOk || !wristsOk) {
            calibMessage = 'KEEP BOTH ARMS IN FRAME';
          } else if (!hipsOk) {
            calibMessage = 'MOVE BACK SO YOUR HIPS ARE VISIBLE';
          } else {
            calibMessage = 'PERFECT! HOLD POSITION...';
          }
        } else {
          // Side-view exercises (Squat). Original logic: offset angle < 50
          // (sideways stance) AND nose + at least one ankle visible.
          if (nose != null && leftShoulder != null && rightShoulder != null) {
            final offsetAngle = _calculateOffsetAngle(
              leftShoulder.x, leftShoulder.y,
              rightShoulder.x, rightShoulder.y,
              nose.x, nose.y,
            );
            if (offsetAngle > 50) {
              _calibrationCounter = 0;
              _selectedSide = null;
              if (mounted) {
                setState(() {
                  _poses = poses;
                  _lastResult = SquatResult(
                    correctReps: 0, incorrectReps: 0, currentSet: 0,
                    effectiveSetCount: 0, feedback: '', isRepCounted: false,
                    kneeAngle: 0, hipAngle: 0, ankleAngle: 0,
                    currentState: null, sessionComplete: false,
                    jointsDetected: false,
                    displayMessage: 'POSTURE NOT ALIGNED!!! (TURN LEFT or RIGHT)',
                    waitingForReset: false, messageTimer: 0,
                  );
                });
              }
              _isProcessing = false;
              return;
            } else {
              _determineSelectedSide(poses.first);
            }
          }

          final bool noseVisible = nose != null && nose.likelihood > 0.5;
          final bool lVisible = leftAnkle != null && leftAnkle.likelihood > 0.5;
          final bool rVisible = rightAnkle != null && rightAnkle.likelihood > 0.5;
          calibOk = noseVisible && (lVisible || rVisible);
          if (!noseVisible) {
            calibMessage = 'MOVE YOUR HEAD INTO FRAME';
          } else if (!lVisible && !rVisible) {
            calibMessage = 'MOVE AT LEAST ONE FOOT INTO FRAME';
          } else {
            calibMessage = 'PERFECT! HOLD POSITION...';
          }
        }

        if (calibOk) {
          _calibrationCounter = (_calibrationCounter + 1).clamp(0, 30);
          if (_calibrationCounter >= 30) {
            _calibrating = false;
            // Don't return here - continue to process the frame
          }
        } else {
          _calibrationCounter = 0;
        }

        // If still calibrating, show calibration message and progress bar
        if (_calibrating) {
          if (mounted) {
            setState(() {
              _poses = poses;
              _lastResult = SquatResult(
                correctReps: _lastResult?.correctReps ?? 0,
                incorrectReps: _lastResult?.incorrectReps ?? 0,
                currentSet: _lastResult?.currentSet ?? 0,
                effectiveSetCount: _lastResult?.effectiveSetCount ?? 0,
                feedback: '',
                isRepCounted: false,
                kneeAngle: _lastResult?.kneeAngle ?? 0,
                hipAngle: _lastResult?.hipAngle ?? 0,
                ankleAngle: _lastResult?.ankleAngle ?? 0,
                currentState: _lastResult?.currentState,
                sessionComplete: false,
                jointsDetected: true,
                displayMessage: calibMessage,
                waitingForReset: _lastResult?.waitingForReset ?? false,
                messageTimer: _lastResult?.messageTimer ?? 0,
              );
            });
          }
          _isProcessing = false;
          return;
        }
      }

      // Route to the correct exercise processor
      final SquatResult result;
      if (_assignedExercise == 'Shoulder Abduction') {
        final r = _abductionLogic!.processFrame(poses.first);
        result = _exerciseResultToSquatResult(r);
      } else if (_assignedExercise == 'Internal Rotation') {
        final r = _internalRotationLogic!.processFrame(poses.first);
        result = _exerciseResultToSquatResult(r);
      } else if (_assignedExercise == 'Lateral Raise') {
        final r = _lateralRaiseLogic!.processFrame(poses.first);
        result = _exerciseResultToSquatResult(r);
      } else if (_assignedExercise == 'custom' && _genericProcessor != null) {
        final r = _genericProcessor!.processFrame(poses.first);
        result = _exerciseResultToSquatResult(r);
      } else {
        // Default: Squat
        final pResult = _squatProcessor.processFrame(poses.first);
        result = _mapProcessorResult(pResult);
      }
      debugPrint(
          '[SquatProcessor] correct=${result.correctReps}, incorrect=${result.incorrectReps}, feedback=${result.feedback}, kneeAngle=${result.kneeAngle.toStringAsFixed(1)}');

      if (mounted) {
        setState(() {
          _poses = poses;
          _lastResult = result;
        });
      }

      if (result.sessionComplete) {
        await _stopSession();
      }
    } catch (e) {
      debugPrint('[SessionLiveStream] Error: $e');
    }

    _isProcessing = false;
  }

   Future<void> _stopSession() async {
    if (_isSessionEnding) return;
    _isSessionEnding = true;
    try {
      // 1. Stop image stream if it was started as fallback
      try {
        await _cameraController?.stopImageStream();
      } catch (_) {} 

      // 2. Stop video recording if it was active and get file
      XFile? videoFile;
      if (_cameraController?.value.isRecordingVideo ?? false) {
        try {
          videoFile = await _cameraController?.stopVideoRecording();
          debugPrint('[SessionLiveStream] Video recording stopped: ${videoFile?.path}');
        } catch (e) {
          debugPrint('[SessionLiveStream] Error stopping video recording: $e');
        }
      }

      // Small delay to ensure the last frame processing completes
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (mounted) {
        setState(() {
          _isStreamActive = false;
        });
        final hasMoreExercises = _program != null &&
            _currentExerciseIndex < _program!.exercises.length - 1;
        if (hasMoreExercises) {
          _showExerciseCompleteDialog(videoFile: videoFile);
        } else {
          _showSummaryDialog(videoFile: videoFile);
        }
      }
    } catch (e) {
      debugPrint('[SessionLiveStream] Error stopping camera: $e');
    }
  }

  InputImage? _convertToInputImage(CameraImage image) {
    try {
      // ML Kit on Android only accepts single-plane formats (nv21). The camera
      // is configured with ImageFormatGroup.nv21 so each frame already has
      // exactly one plane — no concatenation needed.
      if (image.planes.isEmpty) return null;
      final plane = image.planes.first;

      final sensor = _cameraController?.description.sensorOrientation;
      final rotation = InputImageRotationValue.fromRawValue(sensor ?? 0);
      if (rotation == null) return null;

      // Resolve the format from the camera's raw format code, falling back to
      // nv21 on Android / bgra8888 on iOS if the lookup fails.
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      );

      return InputImage.fromBytes(bytes: plane.bytes, metadata: metadata);
    } catch (e) {
      debugPrint('[SessionLiveStream] _convertToInputImage error: $e');
      return null;
    }
  }

  SquatResult _mapProcessorResult(SquatProcessResult r) {
    return SquatResult(
      correctReps: r.correctReps,
      incorrectReps: r.incorrectReps,
      currentSet: r.currentSet,
      effectiveSetCount: 0,
      feedback: r.feedback,
      isRepCounted: r.isRepCounted,
      hipAngle: r.hipAngle,
      kneeAngle: r.kneeAngle,
      ankleAngle: r.ankleAngle,
      currentState: r.currentState,
      sessionComplete: _squatProcessor.sessionComplete,
      jointsDetected: true,
      displayMessage: '',
      waitingForReset: false,
      messageTimer: 0,
    );
  }

  SquatResult _exerciseResultToSquatResult(ExerciseResult r) {
    return SquatResult(
      correctReps: r.correctReps,
      incorrectReps: r.incorrectReps,
      currentSet: r.currentSet,
      effectiveSetCount: r.effectiveSetCount,
      feedback: r.feedback,
      isRepCounted: r.isRepCounted,
      hipAngle: r.primaryAngle,
      kneeAngle: r.primaryAngle,
      ankleAngle: 0,
      currentState: null,
      sessionComplete: r.sessionComplete,
      jointsDetected: r.jointsDetected,
      displayMessage: r.displayMessage ?? '',
      waitingForReset: r.waitingForReset,
      messageTimer: r.messageTimer,
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text('Enable camera access in settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Settings'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      ),
    );
  }

  double _calculateOffsetAngle(double lShoulderX, double lShoulderY,
      double rShoulderX, double rShoulderY, double noseX, double noseY) {
    final p1X = lShoulderX - noseX;
    final p1Y = lShoulderY - noseY;
    final p2X = rShoulderX - noseX;
    final p2Y = rShoulderY - noseY;

    final dot = p1X * p2X + p1Y * p2Y;
    final norm1 = sqrt(p1X * p1X + p1Y * p1Y);
    final norm2 = sqrt(p2X * p2X + p2Y * p2Y);
    if (norm1 == 0 || norm2 == 0) return 0;

    final cosTheta = (dot / (norm1 * norm2)).clamp(-1.0, 1.0);
    return (180 / pi) * acos(cosTheta);
  }

  void _determineSelectedSide(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftFoot = pose.landmarks[PoseLandmarkType.leftFootIndex];
    final rightFoot = pose.landmarks[PoseLandmarkType.rightFootIndex];

    if (leftShoulder != null &&
        rightShoulder != null &&
        leftFoot != null &&
        rightFoot != null) {
      final leftSpan = (leftFoot.y - leftShoulder.y).abs();
      final rightSpan = (rightFoot.y - rightShoulder.y).abs();
      _selectedSide = leftSpan >= rightSpan ? 'left' : 'right';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isStreamActive) {
      return _buildStreamingView(isDark);
    }

    return _buildSetupView(isDark);
  }

  Widget _buildStreamingView(bool isDark) {
    final result = _lastResult;
    final isWaiting = result?.waitingForReset ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        if (_isCameraInitialized && _cameraController != null)
          CameraPreview(_cameraController!)
        else
          Container(color: Colors.black),

        // Skeleton overlay — render whenever we have a pose. For side-view
        // (squat) we wait until selectedSide is set; for front-view exercises
        // selectedSide is intentionally null and the painter draws bilaterally.
        if (_poses.isNotEmpty &&
            (result?.jointsDetected ?? false) &&
            (_isFrontView || _selectedSide != null))
          Positioned.fill(
            child: Transform(
              alignment: Alignment.center,
              // Mirror the skeleton overlay horizontally when using the front
              // camera so joints align with the already-mirrored camera preview.
              transform: _isUsingFrontCamera
                  ? Matrix4.diagonal3Values(-1.0, 1.0, 1.0)
                  : Matrix4.identity(),
              child: CustomPaint(
                painter: PosePainter(
                  poses: _poses,
                  imageSize: Size(
                    _cameraController!.value.previewSize!.height,
                    _cameraController!.value.previewSize!.width,
                  ),
                  hipAngle: result?.hipAngle,
                  kneeAngle: result?.kneeAngle,
                  ankleAngle: result?.ankleAngle,
                  drawReferences: !_isFrontView,
                  selectedSide: _selectedSide,
                  view: _isFrontView ? 'front' : 'side',
                ),
              ),
            ),
          ),

        // Program progress banner (top-left, only when program has >1 exercise)
        if (_program != null && _program!.exercises.length > 1)
          Positioned(
            top: 20,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_assignedExercise.isEmpty ? "(no plan)" : _assignedExercise}'
                '\n${_currentExerciseIndex + 1} / ${_program!.exercises.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),

        // Top-right counters (CORRECT/INCORRECT/SET)
        Positioned(
          top: 20,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBadge('CORRECT: ${result?.correctReps ?? 0}', Colors.green),
              const SizedBox(height: 8),
              _buildBadge(
                  'INCORRECT: ${result?.incorrectReps ?? 0}', Colors.red),
              const SizedBox(height: 8),
              _buildBadge('SET: ${result?.currentSet ?? 0} / $_targetSets',
                  Colors.blue),
            ],
          ),
        ),

        // Posture alignment warning (if angle too high)
        if ((result?.displayMessage ?? '').contains('POSTURE NOT ALIGNED'))
          Positioned(
            bottom: 200,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  result!.displayMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

        // Calibration progress bar (during calibration phase)
        if (_calibrating)
          Positioned(
            bottom: 80,
            left: 40,
            right: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 200,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white54, width: 1),
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor:
                              (_calibrationCounter / 30).clamp(0.0, 1.0),
                          child: Container(
                            color: _calibrationCounter >= 30
                                ? Colors.green
                                : Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_calibrationCounter / 30 * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

        // Feedback messages at BOTTOM (LOWER YOUR HIPS, BEND FORWARD, etc.)
        if (!_calibrating &&
            result != null &&
            result.feedback.isNotEmpty &&
            !result.feedback.contains('Good form') &&
            !isWaiting)
          Positioned(
            left: 0,
            right: 0,
            bottom: 100,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: _getFeedbackColor(result.feedback),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  result.feedback,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

        // Angle labels (displayed on skeleton)
        if ((result?.jointsDetected ?? false) && !isWaiting && !_calibrating)
          Positioned(
            right: 20,
            bottom: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Current State Indicator
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStateColor(result?.currentState),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'State: ${result?.currentState ?? "?"}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hip: ${result!.hipAngle.toStringAsFixed(0)}°',
                  style: const TextStyle(
                    color: Colors.lightGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Knee: ${result.kneeAngle.toStringAsFixed(0)}°',
                  style: const TextStyle(
                    color: Colors.lightGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Ankle: ${result.ankleAngle.toStringAsFixed(0)}°',
                  style: const TextStyle(
                    color: Colors.lightGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

        // Freeze message (central, during reset phase)
        if (isWaiting && (result?.displayMessage ?? '').isNotEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.orange[800],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                result!.displayMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

        // Camera toggle button (top right)
        if (_availableCameras.length > 1)
          Positioned(
            top: 20,
            right: 20,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: _toggleCamera,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.flip_camera_android,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),

        // Start/Stop button
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: Center(
            child: ElevatedButton(
              onPressed: _stopSession,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'End Session',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCameraErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_rounded,
                size: 48, color: Colors.red[400]),
            const SizedBox(height: 12),
            Text(
              _cameraError!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.sub(isDark),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(t('Retry', 'إعادة المحاولة')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF64B5F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getFeedbackColor(String feedback) {
    if (feedback.contains('BEND')) return const Color(0xFF0099FF);
    if (feedback.contains('LOWER')) return Colors.yellow;
    if (feedback.contains('KNEE FALLING') || feedback.contains('DEEP')) {
      return Colors.red;
    }
    return Colors.orange;
  }

  Color _getStateColor(String? state) {
    switch (state) {
      case 's1':
        return Colors.green;
      case 's2':
        return Colors.orange;
      case 's3':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  /// Shows between exercises in a multi-exercise program.
  void _showExerciseCompleteDialog({XFile? videoFile}) {
    if (!mounted || _program == null) return;

    final isSquat = _assignedExercise.isEmpty || _assignedExercise == 'Squat';
    final correctReps = isSquat
        ? _squatProcessor.totalCorrectReps
        : (_lastResult?.correctReps ?? 0);
    final incorrectReps = isSquat
        ? _squatProcessor.totalIncorrectReps
        : (_lastResult?.incorrectReps ?? 0);
    final totalReps = correctReps + incorrectReps;
    final accuracy = totalReps > 0
        ? (correctReps / totalReps * 100).toStringAsFixed(1)
        : '0.0';

    final nextIndex = _currentExerciseIndex + 1;
    final nextEx = _program!.exercises[nextIndex];
    final currentName = _assignedExercise.isEmpty ? 'Squat' : _assignedExercise;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          Text('$currentName Done!',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accuracy: $accuracy%  •  Correct: $correctReps'),
            const Divider(height: 20),
            Row(children: [
              const Icon(Icons.arrow_forward, color: Color(0xFF00BCD4), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Next: ${nextEx.type}\n'
                  '${nextEx.targetSets} sets × ${nextEx.targetReps} reps  •  ${nextEx.mode}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              'Exercise ${nextIndex + 1} of ${_program!.exercises.length}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _saveSessionToFirestore(
                correctReps: correctReps,
                incorrectReps: incorrectReps,
                accuracyPercentage: double.parse(accuracy),
                videoFile: videoFile,
              );
              if (mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Skip Program', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BCD4),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Next Exercise'),
            onPressed: () async {
              await _saveSessionToFirestore(
                correctReps: correctReps,
                incorrectReps: incorrectReps,
                accuracyPercentage: double.parse(accuracy),
                videoFile: videoFile,
              );
              if (mounted) {
                Navigator.of(ctx).pop();
                _advanceToNextExercise();
                await _startSession();
              }
            },
          ),
        ],
      ),
    );
  }

  void _showSummaryDialog({XFile? videoFile}) {
    if (!mounted) return;

    final bool isSquat =
        _assignedExercise.isEmpty || _assignedExercise == 'Squat';
    int correctReps = 0;
    int incorrectReps = 0;

    if (isSquat) {
      correctReps = _squatProcessor.totalCorrectReps;
      incorrectReps = _squatProcessor.totalIncorrectReps;
    } else if (_assignedExercise == 'Shoulder Abduction') {
      correctReps = _abductionLogic?.totalCorrectReps ?? 0;
      incorrectReps = _abductionLogic?.totalIncorrectReps ?? 0;
    } else if (_assignedExercise == 'Internal Rotation') {
      correctReps = _internalRotationLogic?.totalCorrectReps ?? 0;
      incorrectReps = _internalRotationLogic?.totalIncorrectReps ?? 0;
    } else if (_assignedExercise == 'Lateral Raise') {
      correctReps = _lateralRaiseLogic?.totalCorrectReps ?? 0;
      incorrectReps = _lateralRaiseLogic?.totalIncorrectReps ?? 0;
    } else if (_genericProcessor != null) {
      correctReps = _genericProcessor!.totalCorrectReps;
      incorrectReps = _genericProcessor!.totalIncorrectReps;
    } else {
      correctReps = _lastResult?.correctReps ?? 0;
      incorrectReps = _lastResult?.incorrectReps ?? 0;
    }

    final totalReps = correctReps + incorrectReps;
    final accuracy = totalReps > 0
        ? (correctReps / totalReps * 100).toStringAsFixed(1)
        : '0.0';
    final sessionCompleted = isSquat
        ? _squatProcessor.sessionComplete
        : (_lastResult?.sessionComplete ?? false);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Session Summary'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Correct: $correctReps'),
              Text('Incorrect: $incorrectReps'),
              Text('Total: $totalReps'),
              Text('Accuracy: $accuracy%'),
              Text(
                  'Sets: ${isSquat ? (_squatProcessor.currentSet - 1).clamp(1, _targetSets) : (_lastResult?.currentSet ?? 0)}/$_targetSets'),
              if (sessionCompleted)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    '✅ Session Completed!',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                // 1. Close the dialog immediately
                Navigator.of(context).pop();
                
                // 2. Trigger saving in the background (don't await to keep UI responsive)
                _saveSessionToFirestore(
                  correctReps: correctReps,
                  incorrectReps: incorrectReps,
                  accuracyPercentage: double.parse(accuracy),
                  sessionCompleted: sessionCompleted,
                  videoFile: videoFile,
                ).then((_) {
                  if (sessionCompleted) {
                    _incrementCompletedSessions();
                  }
                });

                // 3. Exit the session screen back to dashboard
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Save completed session data to Firestore
  /// Stores: correctReps, wrongReps, accuracyPercentage, timestamp
  /// Location: /Patients/{patientId}/Sessions/{sessionId}
  Future<void> _saveSessionToFirestore({
    required int correctReps,
    required int incorrectReps,
    required double accuracyPercentage,
    bool sessionCompleted = false,
    XFile? videoFile,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final patientId = user.uid;
      final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      String? videoUrl;

      // --- UPLOAD VIDEO TO FIREBASE STORAGE ---
      if (videoFile != null) {
        try {
          debugPrint('[SessionLiveStream] Uploading video to Storage...');
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('workout_videos')
              .child(patientId)
              .child('$sessionId.mp4');
          
          final uploadTask = await storageRef.putFile(File(videoFile.path));
          videoUrl = await uploadTask.ref.getDownloadURL();
          debugPrint('[SessionLiveStream] Video uploaded: $videoUrl');
        } catch (e) {
          debugPrint('[SessionLiveStream] Video upload failed: $e');
        }
      }

      // Save session data to /Patients/{patientId}/Sessions/{sessionId}
      debugPrint(
          '[SessionLiveStream] Saving session for patientId: $patientId');
      debugPrint(
          '[SessionLiveStream] Session Data: correct=$correctReps, wrong=$incorrectReps, accuracy=$accuracyPercentage%');

      final totalReps = correctReps + incorrectReps;
      final isSquat =
          _assignedExercise.isEmpty || _assignedExercise == 'Squat';
      final currentSet = isSquat
          ? (_squatProcessor.currentSet - 1).clamp(1, _targetSets)
          : (_lastResult?.currentSet ?? 0);

      await FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .collection('Sessions')
          .add({
        'patientId': patientId,
        'correctReps': correctReps,
        'incorrectReps': incorrectReps,
        'totalReps': totalReps,
        'accuracy': accuracyPercentage,
        'currentSet': currentSet,
        'effectiveSets': _lastResult?.effectiveSetCount ?? 0,
        'targetSets': _targetSets,
        'exerciseType':
            _assignedExercise.isEmpty ? 'Squat' : _assignedExercise,
        'mode': _selectedMode,
        'sessionComplete': sessionCompleted,
        'videoUrl': videoUrl,
        'recordingConsent': _recordingConsent,
        'timestamp': FieldValue.serverTimestamp(),
      });

      debugPrint('[SessionLiveStream] Session saved successfully: $sessionId');

      // --- SYNC TO SQL BACKEND ---
      try {
        final sqlService = SqlService();
        await sqlService.logSession(
          patientId: patientId,
          correct: correctReps,
          incorrect: incorrectReps,
          totalSets: currentSet,
          exerciseType: _assignedExercise.isEmpty ? 'Squat' : _assignedExercise,
          mode: _selectedMode,
          accuracy: accuracyPercentage.toStringAsFixed(1),
          sessionComplete: sessionCompleted,
        );
        debugPrint('✅ SQL: Session synced to PostgreSQL');
      } catch (sqlError) {
        debugPrint('⚠️ SQL: Session sync failed - $sqlError');
      }

      // Show success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Session saved successfully'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[SessionLiveStream] Error saving session to Firestore: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save session'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Increment the completedSessions counter atomically
  Future<void> _incrementCompletedSessions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('patients')
          .doc(user.uid)
          .update({
        'completedSessions': FieldValue.increment(1),
        'lastSession': FieldValue.serverTimestamp(),
      });

      debugPrint('[SessionLiveStream] Incremented completedSessions');
    } catch (e) {
      debugPrint('[SessionLiveStream] Error incrementing completedSessions: $e');
    }
  }

  /// Toggle between front and back cameras
  Future<void> _toggleCamera() async {
    if (_availableCameras.length < 2) {
      _showErrorDialog('Only one camera available');
      return;
    }

    try {
      // Stop image stream if active
      final wasStreamActive = _isStreamActive;
      if (wasStreamActive) {
        await _cameraController?.stopImageStream();
      }

      // Dispose current controller
      await _cameraController?.dispose();

      // Switch to next camera
      _currentCameraIndex =
          (_currentCameraIndex + 1) % _availableCameras.length;

      // Initialize new camera
      _cameraController = CameraController(
        _availableCameras[_currentCameraIndex],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });

      // Restart image stream if it was active
      if (wasStreamActive) {
        await _cameraController!.startImageStream(_processImage);
      }

      debugPrint(
          '[SessionLiveStream] Switched to camera: ${_availableCameras[_currentCameraIndex].name}');
    } catch (e) {
      debugPrint('[SessionLiveStream] Error switching camera: $e');
      _showErrorDialog('Failed to switch camera: $e');
    }
  }

  Widget _buildSetupView(bool isDark) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Program overview card (when multi-exercise program assigned)
          if (_program != null && _program!.exercises.length > 1)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.card(isDark),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00BCD4).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.list_alt, color: Color(0xFF00BCD4), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      _program!.name,
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14,
                          color: AppTheme.text(isDark)),
                    ),
                    const Spacer(),
                    Text('${_program!.exercises.length} exercises',
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black45)),
                  ]),
                  const SizedBox(height: 10),
                  ...List.generate(_program!.exercises.length, (i) {
                    final ex = _program!.exercises[i];
                    final isCurrent = i == _currentExerciseIndex;
                    final isDone = i < _currentExerciseIndex;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: isDone
                                ? Colors.green.withValues(alpha: 0.2)
                                : isCurrent
                                    ? const Color(0xFF00BCD4).withValues(alpha: 0.2)
                                    : Colors.grey.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: isDone
                                ? const Icon(Icons.check, size: 13, color: Colors.green)
                                : Text('${i + 1}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isCurrent
                                            ? const Color(0xFF00BCD4)
                                            : Colors.grey)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(ex.type,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isDone
                                      ? Colors.grey
                                      : (AppTheme.text(isDark)))),
                        ),
                        Text('${ex.targetSets}×${ex.targetReps}',
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38)),
                      ]),
                    );
                  }),
                ],
              ),
            ),

          // Show message if no plan assigned
          if (_assignedExercise.isEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.bg(isDark) : Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: Colors.orange, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t('Doctor didn\'t set a rehabilitation plan yet',
                          'لم يحدد الطبيب خطة إعادة تأهيل بعد'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.orange[300] : Colors.orange[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.card(isDark) : Colors.grey[50],
              border: Border(
                  bottom: BorderSide(
                      color: isDark ? Colors.white12 : Colors.grey[300]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('Workout Settings', 'إعدادات التمرين'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.text(isDark))),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: _modeButton(
                            'Beginner',
                            _selectedMode == 'Beginner',
                            null)), // Always locked for patients
                    const SizedBox(width: 12),
                    Expanded(
                        child: _modeButton('Pro', _selectedMode == 'Pro',
                            null)), // Always locked for patients
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: _buildDropdown(
                            t('Reps per Set', 'التكرارات'),
                            _targetReps,
                            20,
                            null)), // Always locked for patients
                    const SizedBox(width: 12),
                    Expanded(
                        child: _buildDropdown(
                            t('Total Sets', 'المجموعات'),
                            _targetSets,
                            10,
                            null)), // Always locked for patients
                  ],
                ),
              ],
            ),
          ),

          // Camera preview
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        height: 400,
                        color: Colors.black12,
                        child: _isCameraInitialized && _cameraController != null
                            ? CameraPreview(_cameraController!)
                            : _cameraError != null
                                ? _buildCameraErrorState(isDark)
                                : Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: isDark ? Colors.white38 : Colors.grey[400],
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                            t('Initializing camera...',
                                                'جاري تهيئة الكاميرا...'),
                                            style: TextStyle(color: Colors.grey[600])),
                                      ],
                                    ),
                                  ),
                      ),
                    ),
                    // Camera toggle button
                    if (_isCameraInitialized && _availableCameras.length > 1)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: _toggleCamera,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                Icons.flip_camera_android,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),


                // --- Recording Consent Toggle ---
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _recordingConsent
                        ? const Color(0xFF64B5F6).withValues(alpha: 0.08)
                        : Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _recordingConsent
                          ? const Color(0xFF64B5F6).withValues(alpha: 0.3)
                          : Colors.grey.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _recordingConsent ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                        color: _recordingConsent ? const Color(0xFF64B5F6) : Colors.grey,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('Record Session Video', 'تسجيل فيديو الجلسة'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              t('Share with your doctor for review', 'مشاركة مع طبيبك للمراجعة'),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _recordingConsent,
                        onChanged: (val) => setState(() => _recordingConsent = val),
                        activeThumbColor: const Color(0xFF64B5F6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF64B5F6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isCameraInitialized ? _startSession : null,
                    child: Text(t('Start Session', 'بدء الجلسة'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),

          // Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF64B5F6).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFF64B5F6).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('📷 Camera Requirements', '📷 متطلبات الكاميرا'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64B5F6))),
                  const SizedBox(height: 8),
                  Text(
                    t('• Good lighting\n• Full body visible (head to feet)\n• 2-3 meters from camera\n• Stable position',
                        '• إضاءة جيدة\n• الجسم مرئي بالكامل (من الرأس إلى القدمين)\n• 2-3 أمتار من الكاميرا\n• موضع ثابت'),
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(String label, bool isSelected, VoidCallback? onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDisabled = onTap == null;
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF64B5F6)
              : (isDark ? AppTheme.bg(isDark) : AppTheme.card(isDark)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isSelected
                  ? const Color(0xFF64B5F6)
                  : (isDark ? Colors.white12 : Colors.grey[300]!)),
        ),
        child: Center(
            child: Text(label,
                style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (AppTheme.sub(isDark)),
                    fontWeight: FontWeight.w600))),
      ),
    );
  }

  Widget _buildDropdown(
      String label, int value, int max, Function(int)? onChanged) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDisabled = onChanged == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.sub(isDark))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.bg(isDark) : AppTheme.card(isDark),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
          ),
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: AppTheme.card(isDark),
            style: TextStyle(
                color: AppTheme.text(isDark), fontSize: 14),
            onChanged:
                isDisabled ? null : (v) => v != null ? onChanged(v) : null,
            items: List.generate(max, (i) => i + 1)
                .map((n) =>
                    DropdownMenuItem(value: n, child: Text(n.toString())))
                .toList(),
          ),
        ),
      ],
    );
  }
}
