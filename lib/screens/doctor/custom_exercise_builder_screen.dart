/// Doctor-facing 5-step wizard to build a custom exercise from scratch.
/// Mirrors the Python ⚙️_Exercise_Builder.py Streamlit wizard.
///
/// Step 0 — Exercise info + Gemini AI (or manual) primary measurement + form checks
/// Step 1 — Live camera calibration: capture rest (s1) and peak (s3) values
/// Step 2 — Fine-tune form check thresholds
/// Step 3 — Live test run with the assembled GenericExerciseProcessor
/// Step 4 — Set reps/sets/mode and add to program
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../models/custom_exercise_config.dart';
import '../../models/exercise_program.dart';
import '../../utils/api_config.dart';
import '../../utils/generic_exercise_processor.dart';
import '../../utils/theme_provider.dart';
import '../../utils/abduction_logic.dart';

// ── Colors used for form check badges (mirrors Python _COLORS) ────────────────
const _kCheckColors = [
  Color(0xFFFF5050),
  Color(0xFF00FFFF),
  Color(0xFF0099FF),
  Color(0xFFFFFF00),
  Color(0xFFFFA500),
];

const _kDisplayYs = [215, 170, 125, 80, 35];

class CustomExerciseBuilderScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final void Function(ProgramExercise exercise) onAddToProgram;

  const CustomExerciseBuilderScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.onAddToProgram,
  });

  @override
  State<CustomExerciseBuilderScreen> createState() =>
      _CustomExerciseBuilderScreenState();
}

class _CustomExerciseBuilderScreenState
    extends State<CustomExerciseBuilderScreen> {
  int _step = 0;
  static const _totalSteps = 5;

  // ── Step 0 state ───────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _view = 'front';
  String _exerciseMode = 'rep';
  double _holdDuration = 30.0;
  bool _isGenerating = false;
  String? _aiError;

  MeasurementConfig? _primaryMeasurement;
  List<int> _visibilityIndices = [0, 11, 12];
  List<_EditableCheck> _checks = [];

  // Manual primary measurement definition
  String _manualMeasType = 'bilateral_avg_angle';
  String _manualP1 = 'left_hip';
  String _manualVertex = 'left_shoulder';
  String _manualP3 = 'left_elbow';
  String _manualP2 = 'left_ankle';
  String _manualSide = 'bilateral_max';
  String _manualLeftP1 = 'left_hip';
  String _manualLeftVertex = 'left_shoulder';
  String _manualLeftP3 = 'left_elbow';
  String _manualRightP1 = 'right_hip';
  String _manualRightVertex = 'right_shoulder';
  String _manualRightP3 = 'right_elbow';

  // ── Step 1 state (calibration camera) ─────────────────────────────────────
  CameraController? _cameraCtrl;
  PoseDetector? _poseDetector;
  bool _cameraReady = false;
  bool _cameraError = false;
  bool _isProcessingFrame = false;
  double? _liveVal;
  double? _s1Val;
  double? _s3Val;

  // ── Step 3 state (test run camera) ────────────────────────────────────────
  GenericExerciseProcessor? _testProcessor;
  ExerciseResult? _testResult;

  // ── Step 4 state ───────────────────────────────────────────────────────────
  int _finalReps = 10;
  int _finalSets = 3;
  String _finalMode = 'Beginner';

  // ────────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _stopCamera();
    _poseDetector?.close();
    super.dispose();
  }

  // ── Camera lifecycle ───────────────────────────────────────────────────────

  Future<void> _startCamera() async {
    if (_cameraReady) return;
    final status = await Permission.camera.request();
    if (status.isDenied) {
      setState(() => _cameraError = true);
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = true);
        return;
      }
      // Prefer front camera for the doctor
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraCtrl = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cameraCtrl!.initialize();
      _poseDetector ??= PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream,
          model: PoseDetectionModel.base,
        ),
      );
      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _cameraError = false;
      });
      await _cameraCtrl!.startImageStream(_onCameraFrame);
    } catch (e) {
      if (mounted) setState(() => _cameraError = true);
    }
  }

  Future<void> _stopCamera() async {
    if (!_cameraReady) return;
    _cameraReady = false;
    try {
      await _cameraCtrl?.stopImageStream();
      await _cameraCtrl?.dispose();
    } catch (_) {}
    _cameraCtrl = null;
    if (mounted) setState(() {});
  }

  void _onCameraFrame(CameraImage img) async {
    if (_isProcessingFrame || !_cameraReady || _poseDetector == null) return;
    if (_primaryMeasurement == null) return;
    _isProcessingFrame = true;

    try {
      final inputImage = _buildInputImage(img);
      if (inputImage == null) {
        _isProcessingFrame = false;
        return;
      }
      final poses = await _poseDetector!.processImage(inputImage);
      if (poses.isEmpty) {
        if (mounted) setState(() => _liveVal = null);
        _isProcessingFrame = false;
        return;
      }

      final pose = poses.first;

      if (_step == 1) {
        // Calibration: just compute primary measurement
        final processor = GenericExerciseProcessor(
          config: _buildPreliminaryConfig(),
          targetSets: 1,
          repsPerSet: 1,
        );
        final val = processor.computePrimary(pose);
        if (mounted) setState(() => _liveVal = val);
      } else if (_step == 3) {
        // Test run: full processing
        final result = _testProcessor?.processFrame(pose);
        if (mounted) setState(() => _testResult = result);
      }
    } catch (_) {}

    _isProcessingFrame = false;
  }

  InputImage? _buildInputImage(CameraImage img) {
    try {
      final builder = BytesBuilder(copy: false);
      for (final p in img.planes) {
        builder.add(p.bytes);
      }
      final bytes = builder.toBytes();
      final sensor = _cameraCtrl?.description.sensorOrientation ?? 0;
      final rotation = switch (sensor) {
        90 => InputImageRotation.rotation90deg,
        180 => InputImageRotation.rotation180deg,
        270 => InputImageRotation.rotation270deg,
        _ => InputImageRotation.rotation0deg,
      };
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(
              img.width.toDouble(), img.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.yuv_420_888,
          bytesPerRow: img.planes.first.bytesPerRow,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Step navigation ────────────────────────────────────────────────────────

  void _goToStep(int next) async {
    // Stop camera when leaving calibration or test steps
    if (_step == 1 || _step == 3) await _stopCamera();

    setState(() {
      _step = next;
      _liveVal = null;
      _s1Val = _step == 1 ? null : _s1Val;
      _s3Val = _step == 1 ? null : _s3Val;
    });

    // Start camera when entering calibration or test steps
    if (next == 1) {
      await _startCamera();
    } else if (next == 3) {
      _testProcessor = GenericExerciseProcessor(
        config: _assembleConfig(),
        targetSets: 1,
        repsPerSet: 3,
      );
      await _startCamera();
    }
  }

  // ── Gemini AI call ─────────────────────────────────────────────────────────

  Future<void> _generateWithGemini() async {
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    if (name.isEmpty || desc.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _aiError = null;
    });

    try {
      final model = GenerativeModel(
        model: ApiConfig.geminiModel,
        apiKey: ApiConfig.geminiApiKey,
      );

      final bilateralHint = _view == 'front'
          ? 'Front view: prefer bilateral measurement types (bilateral_avg_angle etc.) '
              'or lateral_trunk_angle / knee_valgus_ratio for lower-body exercises.'
          : 'Side view: prefer vertical_angle, angle, torso_angle, or distance_ratio.';

      final holdHint = _exerciseMode == 'hold'
          ? '\nThis is a TIMED HOLD / isometric exercise. '
              's3 zone = the correct hold position. s1 = rest. '
              'Form checks should fire when the person deviates from the correct hold posture.'
          : '';

      final prompt = '''You are a physiotherapy exercise configuration expert.
Generate a JSON configuration for the exercise below.

Exercise: $name
Description: $desc
Camera view: $_view
Exercise mode: $_exerciseMode$holdHint
$bilateralHint

MEASUREMENT TYPES available:
- "angle": 3-point angle. Needs: p1, vertex, p3.
- "vertical_angle": angle from vertical. Needs: p1, vertex.
- "bilateral_avg_angle" / "bilateral_max_angle" / "bilateral_min_angle" / "bilateral_diff_angle":
  bilateral arm/leg measurements. Needs: left{p1,vertex,p3}, right{p1,vertex,p3}.
- "torso_angle": forward trunk lean (SIDE VIEW). No extra fields.
- "lateral_trunk_angle": sideways trunk lean (FRONT VIEW). No extra fields.
- "distance_ratio": distance between two landmarks / shoulder_width. Needs: p1, p2.
- "knee_valgus_ratio": knee collapse. Needs: side ("left"/"right"/"bilateral_max").
- "rotation_ratio": forearm rotation ratio (use arm_lock=true). No extra fields.
- "wrist_y_diff": vertical wrist-elbow offset (use arm_lock=true). No extra fields.
- "elbow_flare_ratio": elbow flare (use arm_lock=true). No extra fields.

LANDMARKS: nose, left_shoulder, right_shoulder, left_elbow, right_elbow,
left_wrist, right_wrist, left_hip, right_hip, left_knee, right_knee,
left_ankle, right_ankle, left_foot, right_foot

MEDIAPIPE INDICES: nose=0, left_shoulder=11, right_shoulder=12, left_elbow=13,
right_elbow=14, left_wrist=15, right_wrist=16, left_hip=23, right_hip=24,
left_knee=25, right_knee=26, left_ankle=27, right_ankle=28

Return ONLY valid JSON (no markdown fences):
{
  "primary_measurement": {...},
  "visibility_check": {"indices": [...], "error_msg": "short description"},
  "form_checks": [
    {
      "id": "UPPER_SNAKE_ID",
      "label_en": "IMPERATIVE CAPS",
      "label_ar": "Arabic translation",
      "condition_op": ">" or "<",
      "threshold": <float>,
      "measurement": {...},
      "affects_rep": false,
      "skip_in_states": [],
      "require_s2_seen": false
    }
  ]
}
Generate 3-5 clinically relevant form checks. Keep thresholds realistic.''';

      final response =
          await model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';

      // Strip markdown fences if present
      String jsonStr = text.trim();
      if (jsonStr.contains('```')) {
        final parts = jsonStr.split('```');
        for (final p in parts) {
          final clean = p.trim().replaceFirst(RegExp(r'^json'), '').trim();
          try {
            jsonDecode(clean);
            jsonStr = clean;
            break;
          } catch (_) {}
        }
      }

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      _applyAiResult(data);
    } catch (e) {
      if (mounted) setState(() => _aiError = 'Gemini error: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _applyAiResult(Map<String, dynamic> data) {
    final pm = data['primary_measurement'];
    final vis = data['visibility_check'];
    final checks = data['form_checks'] as List<dynamic>? ?? [];

    setState(() {
      if (pm != null) {
        _primaryMeasurement = MeasurementConfig.fromMap(
            Map<String, dynamic>.from(pm as Map));
      }
      if (vis != null) {
        _visibilityIndices =
            ((vis as Map)['indices'] as List<dynamic>?)?.cast<int>() ??
                [0, 11, 12];
      }
      _checks = checks.asMap().entries.map((e) {
        final i = e.key;
        final c = Map<String, dynamic>.from(e.value as Map);
        final op = c['condition_op'] as String? ?? '>';
        final thr = (c['threshold'] as num?)?.toDouble() ?? 20.0;
        final measRaw = c['measurement'];
        final meas = measRaw != null
            ? MeasurementConfig.fromMap(Map<String, dynamic>.from(measRaw as Map))
            : MeasurementConfig(type: 'angle');
        return _EditableCheck(
          id: c['id'] as String? ?? 'CHECK_$i',
          labelEn: c['label_en'] as String? ?? '',
          labelAr: c['label_ar'] as String? ?? '',
          conditionOp: op,
          threshold: thr,
          measurement: meas,
          affectsRep: c['affects_rep'] as bool? ?? false,
          skipInStates:
              (c['skip_in_states'] as List<dynamic>?)?.cast<String>() ?? [],
          requireS2Seen: c['require_s2_seen'] as bool? ?? false,
        );
      }).toList();
      _aiError = null;
    });
  }

  // ── Manual primary measurement builder ────────────────────────────────────

  MeasurementConfig _buildManualPrimary() {
    if (kBilateralTypes.contains(_manualMeasType)) {
      return MeasurementConfig(
        type: _manualMeasType,
        left: MeasurementConfig(
            type: 'angle',
            p1: _manualLeftP1,
            vertex: _manualLeftVertex,
            p3: _manualLeftP3),
        right: MeasurementConfig(
            type: 'angle',
            p1: _manualRightP1,
            vertex: _manualRightVertex,
            p3: _manualRightP3),
      );
    }
    if (_manualMeasType == 'knee_valgus_ratio') {
      return MeasurementConfig(type: _manualMeasType, side: _manualSide);
    }
    if (_manualMeasType == 'distance_ratio') {
      return MeasurementConfig(
          type: _manualMeasType, p1: _manualP1, p2: _manualP2);
    }
    if (_manualMeasType == 'angle') {
      return MeasurementConfig(
          type: _manualMeasType,
          p1: _manualP1,
          vertex: _manualVertex,
          p3: _manualP3);
    }
    if (_manualMeasType == 'vertical_angle') {
      return MeasurementConfig(
          type: _manualMeasType, p1: _manualP1, vertex: _manualVertex);
    }
    return MeasurementConfig(type: _manualMeasType);
  }

  // ── Config assembly ────────────────────────────────────────────────────────

  CustomExerciseConfig _buildPreliminaryConfig() {
    final primary = _primaryMeasurement ?? _buildManualPrimary();
    return CustomExerciseConfig(
      name: _nameCtrl.text.trim().isEmpty ? 'Custom Exercise' : _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      view: _view,
      mode: _exerciseMode,
      holdDuration: _exerciseMode == 'hold' ? _holdDuration : null,
      visibilityIndices: _visibilityIndices,
      states: {'s1': [0, 30], 's2': [30, 60], 's3': [60, 90]}, // placeholder
      primaryMeasurement: primary,
      formChecks: [],
    );
  }

  CustomExerciseConfig _assembleConfig() {
    final primary = _primaryMeasurement ?? _buildManualPrimary();

    // Compute state ranges from captured s1/s3 values
    final lo = min(_s1Val ?? 0.0, _s3Val ?? 90.0);
    final hi = max(_s1Val ?? 0.0, _s3Val ?? 90.0);
    final buf = max(5.0, (hi - lo) * 0.12);
    final states = {
      's1': [lo - buf, lo + buf],
      's2': [lo + buf, hi - buf],
      's3': [hi - buf, hi + buf],
    };

    final formChecks = _checks.asMap().entries.map((e) {
      final i = e.key;
      final c = e.value;
      return FormCheckConfig(
        id: c.id,
        labelEn: c.labelEn,
        labelAr: c.labelAr,
        color: _colorToList(_kCheckColors[i % _kCheckColors.length]),
        displayY: _kDisplayYs[i % _kDisplayYs.length],
        measurement: c.measurement,
        condition: 'value ${c.conditionOp} ${c.threshold}',
        affectsRep: c.affectsRep,
        skipInStates: c.skipInStates,
        requireS2Seen: c.requireS2Seen,
      );
    }).toList();

    return CustomExerciseConfig(
      name: _nameCtrl.text.trim().isEmpty ? 'Custom Exercise' : _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      view: _view,
      mode: _exerciseMode,
      holdDuration: _exerciseMode == 'hold' ? _holdDuration : null,
      visibilityIndices: _visibilityIndices,
      states: states,
      primaryMeasurement: primary,
      formChecks: formChecks,
    );
  }

  List<int> _colorToList(Color c) => [
        (c.r * 255.0).round().clamp(0, 255),
        (c.g * 255.0).round().clamp(0, 255),
        (c.b * 255.0).round().clamp(0, 255),
      ];

  double get _min => _s1Val != null && _s3Val != null
      ? min(_s1Val!, _s3Val!)
      : 0;
  double get _max => _s1Val != null && _s3Val != null
      ? max(_s1Val!, _s3Val!)
      : 90;

  // ── Validation ─────────────────────────────────────────────────────────────

  bool get _step0Valid =>
      _nameCtrl.text.trim().isNotEmpty &&
      _descCtrl.text.trim().isNotEmpty &&
      (_primaryMeasurement != null);

  bool get _step1Valid =>
      _s1Val != null &&
      _s3Val != null &&
      (_max - _min) > 5;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(t('Build Custom Exercise', 'بناء تمرين مخصص')),
        backgroundColor: const Color(0xFF00BCD4),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildStepIndicator(isDark),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: SingleChildScrollView(
                key: ValueKey(_step),
                padding: const EdgeInsets.all(16),
                child: _buildStepContent(isDark),
              ),
            ),
          ),
          _buildNavRow(isDark),
        ],
      ),
    );
  }

  // ── Step indicator ─────────────────────────────────────────────────────────

  Widget _buildStepIndicator(bool isDark) {
    const labels = ['Info', 'Calibrate', 'Checks', 'Test', 'Save'];
    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: List.generate(_totalSteps, (i) {
          final done = i < _step;
          final active = i == _step;
          return Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: done
                      ? Colors.green
                      : active
                          ? const Color(0xFF00BCD4)
                          : (isDark ? Colors.grey[700] : Colors.grey[300]),
                  child: done
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 12,
                              color: active || done
                                  ? Colors.white
                                  : Colors.grey[600])),
                ),
                const SizedBox(height: 2),
                Text(labels[i],
                    style: TextStyle(
                        fontSize: 10,
                        color: active
                            ? const Color(0xFF00BCD4)
                            : (AppTheme.sub(isDark)),
                        fontWeight:
                            active ? FontWeight.bold : FontWeight.normal)),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Step content router ────────────────────────────────────────────────────

  Widget _buildStepContent(bool isDark) {
    return switch (_step) {
      0 => _buildInfoStep(isDark),
      1 => _buildCalibStep(isDark),
      2 => _buildChecksStep(isDark),
      3 => _buildTestStep(isDark),
      4 => _buildSaveStep(isDark),
      _ => const SizedBox(),
    };
  }

  // ── Step 0: Info + AI ──────────────────────────────────────────────────────

  Widget _buildInfoStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Basic info card
        _card(isDark, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Exercise Details', 'تفاصيل التمرين', isDark),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              decoration: _inputDec('Exercise Name', 'اسم التمرين', isDark),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: _inputDec(
                  'Describe the movement (e.g. Stand facing camera, raise arms to shoulder level)',
                  'صف الحركة',
                  isDark),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Text(t('Camera View: ', 'زاوية الكاميرا: '),
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Front'),
                selected: _view == 'front',
                onSelected: (_) => setState(() => _view = 'front'),
                selectedColor: const Color(0xFF00BCD4),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Side'),
                selected: _view == 'side',
                onSelected: (_) => setState(() => _view = 'side'),
                selectedColor: const Color(0xFF00BCD4),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Text(t('Mode: ', 'النوع: '),
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Reps'),
                selected: _exerciseMode == 'rep',
                onSelected: (_) => setState(() => _exerciseMode = 'rep'),
                selectedColor: const Color(0xFF00BCD4),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Timed Hold'),
                selected: _exerciseMode == 'hold',
                onSelected: (_) => setState(() => _exerciseMode = 'hold'),
                selectedColor: const Color(0xFF00BCD4),
              ),
            ]),
            if (_exerciseMode == 'hold') ...[
              const SizedBox(height: 8),
              Text(
                  t('Hold duration: ${_holdDuration.toInt()}s',
                      'مدة الثبات: ${_holdDuration.toInt()}ث'),
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87)),
              Slider(
                value: _holdDuration,
                min: 5,
                max: 120,
                divisions: 23,
                activeColor: const Color(0xFF00BCD4),
                onChanged: (v) => setState(() => _holdDuration = v),
              ),
            ],
          ],
        )),

        const SizedBox(height: 12),

        // AI generation card
        _card(isDark, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Generate with Gemini AI', 'توليد باستخدام Gemini', isDark),
            const SizedBox(height: 6),
            Text(
              t('AI will suggest primary measurement + form checks based on exercise description.',
                  'سيقترح الذكاء الاصطناعي القياس الأساسي والفحوصات بناءً على الوصف.'),
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.sub(isDark)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_nameCtrl.text.isEmpty || _descCtrl.text.isEmpty || _isGenerating)
                    ? null
                    : _generateWithGemini,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome),
                label: Text(_isGenerating
                    ? t('Generating...', 'جارٍ التوليد...')
                    : t('Generate with Gemini', 'توليد بـ Gemini')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6750A4),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            if (_aiError != null) ...[
              const SizedBox(height: 8),
              Text(_aiError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        )),

        // Manual primary measurement card
        const SizedBox(height: 12),
        _card(isDark, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
                _primaryMeasurement != null
                    ? 'Primary Measurement ✓'
                    : 'Primary Measurement (define manually)',
                'القياس الأساسي',
                isDark),
            const SizedBox(height: 6),
            if (_primaryMeasurement != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _primaryMeasurement!.summary,
                        style: const TextStyle(
                            color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _primaryMeasurement = null),
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              _buildManualPrimaryForm(isDark),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => setState(
                      () => _primaryMeasurement = _buildManualPrimary()),
                  child: Text(t('Use This Measurement', 'استخدام هذا القياس')),
                ),
              ),
            ],
          ],
        )),

        // Form checks card
        if (_checks.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(isDark, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Form Checks (${_checks.length})', 'فحوصات الشكل', isDark),
              const SizedBox(height: 4),
              Text(
                t('Edit labels and thresholds. "Fails rep" = counted as incorrect.',
                    'عدّل التسميات والعتبات. "يفشل التكرار" = يُحسب خاطئاً.'),
                style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.sub(isDark)),
              ),
              ..._checks.asMap().entries.map((e) {
                final i = e.key;
                final chk = e.value;
                return _buildCheckCard(i, chk, isDark);
              }),
            ],
          )),
        ],
      ],
    );
  }

  Widget _buildManualPrimaryForm(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('Measurement type:', 'نوع القياس:'),
            style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _manualMeasType,
          items: kMeasurementTypes
              .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12))))
              .toList(),
          onChanged: (v) => setState(() => _manualMeasType = v!),
          decoration: _inputDec('', '', isDark),
          dropdownColor: isDark ? const Color(0xFF2A2A2A) : null,
          style: TextStyle(
              color: AppTheme.text(isDark), fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (_manualMeasType == 'angle') ...[
          _landmarkRow(isDark, 'p1', _manualP1, (v) => setState(() => _manualP1 = v!)),
          _landmarkRow(isDark, 'vertex', _manualVertex, (v) => setState(() => _manualVertex = v!)),
          _landmarkRow(isDark, 'p3', _manualP3, (v) => setState(() => _manualP3 = v!)),
        ],
        if (_manualMeasType == 'vertical_angle') ...[
          _landmarkRow(isDark, 'p1', _manualP1, (v) => setState(() => _manualP1 = v!)),
          _landmarkRow(isDark, 'vertex', _manualVertex, (v) => setState(() => _manualVertex = v!)),
        ],
        if (_manualMeasType == 'distance_ratio') ...[
          _landmarkRow(isDark, 'landmark 1', _manualP1, (v) => setState(() => _manualP1 = v!)),
          _landmarkRow(isDark, 'landmark 2', _manualP2, (v) => setState(() => _manualP2 = v!)),
        ],
        if (_manualMeasType == 'knee_valgus_ratio')
          DropdownButtonFormField<String>(
            initialValue: _manualSide,
            items: ['bilateral_max', 'left', 'right']
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _manualSide = v!),
            decoration: _inputDec('Side', 'الجانب', isDark),
            dropdownColor: isDark ? const Color(0xFF2A2A2A) : null,
            style: TextStyle(color: AppTheme.text(isDark)),
          ),
        if (kBilateralTypes.contains(_manualMeasType)) ...[
          Text(t('Left side:', 'الجانب الأيسر:'),
              style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.sub(isDark))),
          _landmarkRow(isDark, 'left p1', _manualLeftP1, (v) => setState(() => _manualLeftP1 = v!)),
          _landmarkRow(isDark, 'left vertex', _manualLeftVertex, (v) => setState(() => _manualLeftVertex = v!)),
          _landmarkRow(isDark, 'left p3', _manualLeftP3, (v) => setState(() => _manualLeftP3 = v!)),
          Text(t('Right side:', 'الجانب الأيمن:'),
              style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.sub(isDark))),
          _landmarkRow(isDark, 'right p1', _manualRightP1, (v) => setState(() => _manualRightP1 = v!)),
          _landmarkRow(isDark, 'right vertex', _manualRightVertex, (v) => setState(() => _manualRightVertex = v!)),
          _landmarkRow(isDark, 'right p3', _manualRightP3, (v) => setState(() => _manualRightP3 = v!)),
        ],
      ],
    );
  }

  Widget _landmarkRow(bool isDark, String label, String value,
      void Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.sub(isDark))),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              items: kLandmarkNames
                  .map((n) =>
                      DropdownMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 11))))
                  .toList(),
              onChanged: onChanged,
              decoration: _inputDec('', '', isDark),
              dropdownColor: isDark ? const Color(0xFF2A2A2A) : null,
              style: TextStyle(
                  color: AppTheme.text(isDark), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckCard(int i, _EditableCheck chk, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: _kCheckColors[i % _kCheckColors.length].withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                    color: _kCheckColors[i % _kCheckColors.length],
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('Check ${i + 1}: ${chk.measurement.summary}',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.sub(isDark))),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red,
                onPressed: () => setState(() => _checks.removeAt(i)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // EN / AR labels
          Row(children: [
            Expanded(
              child: TextField(
                controller: TextEditingController(text: chk.labelEn)
                  ..selection = TextSelection.collapsed(offset: chk.labelEn.length),
                decoration: _inputDec('English label', 'التسمية بالإنجليزية', isDark),
                style: const TextStyle(fontSize: 12),
                onChanged: (v) => _checks[i] = chk.copyWith(labelEn: v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: TextEditingController(text: chk.labelAr)
                  ..selection = TextSelection.collapsed(offset: chk.labelAr.length),
                decoration: _inputDec('Arabic label', 'التسمية بالعربية', isDark),
                style: const TextStyle(fontSize: 12),
                onChanged: (v) => _checks[i] = chk.copyWith(labelAr: v),
                textDirection: TextDirection.rtl,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text(t('Fires when value ', 'يُطلق عندما '),
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87)),
            ChoiceChip(
              label: const Text('>'),
              selected: chk.conditionOp == '>',
              visualDensity: VisualDensity.compact,
              onSelected: (_) =>
                  setState(() => _checks[i] = chk.copyWith(conditionOp: '>')),
            ),
            const SizedBox(width: 4),
            ChoiceChip(
              label: const Text('<'),
              selected: chk.conditionOp == '<',
              visualDensity: VisualDensity.compact,
              onSelected: (_) =>
                  setState(() => _checks[i] = chk.copyWith(conditionOp: '<')),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextField(
                controller: TextEditingController(
                    text: chk.threshold.toStringAsFixed(1))
                  ..selection = const TextSelection.collapsed(offset: 0),
                keyboardType: TextInputType.number,
                decoration: _inputDec('Threshold', 'العتبة', isDark),
                style: const TextStyle(fontSize: 12),
                onChanged: (v) {
                  final d = double.tryParse(v);
                  if (d != null) {
                    setState(() => _checks[i] = chk.copyWith(threshold: d));
                  }
                },
              ),
            ),
          ]),
          const SizedBox(height: 4),
          CheckboxListTile(
            title: Text(t('Fails rep?', 'يُفشل التكرار؟'),
                style: const TextStyle(fontSize: 12)),
            value: chk.affectsRep,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) =>
                setState(() => _checks[i] = chk.copyWith(affectsRep: v ?? false)),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Calibration ────────────────────────────────────────────────────

  Widget _buildCalibStep(bool isDark) {
    final rangeOk = _step1Valid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(isDark, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Calibrate Zones', 'معايرة المناطق', isDark),
            Text(
              t('Stand in REST position → tap Capture Rest.\nMove to PEAK position → tap Capture Peak.',
                  'قف في وضع الراحة ← اضغط التقاط الراحة.\nانتقل إلى وضع الذروة ← اضغط التقاط الذروة.'),
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.sub(isDark)),
            ),
            const SizedBox(height: 12),
            // Live measurement value
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BCD4).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00BCD4)),
                ),
                child: Text(
                  _liveVal != null
                      ? _liveVal!.toStringAsFixed(1)
                      : (_cameraReady ? 'Detecting...' : 'Starting camera...'),
                  style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text(isDark)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _liveVal != null
                      ? () => setState(() => _s1Val = _liveVal)
                      : null,
                  icon: const Icon(Icons.looks_one_outlined),
                  label: Text(t('Capture Rest', 'التقاط الراحة')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _liveVal != null
                      ? () => setState(() => _s3Val = _liveVal)
                      : null,
                  icon: const Icon(Icons.looks_3_outlined),
                  label: Text(t('Capture Peak', 'التقاط الذروة')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _valBadge('Rest (s1)', _s1Val, Colors.green, isDark),
              const SizedBox(width: 8),
              _valBadge('Peak (s3)', _s3Val, Colors.orange, isDark),
            ]),
            if (rangeOk) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  t('✓ Rest ≈ ${_min.toStringAsFixed(1)}  |  Peak ≈ ${_max.toStringAsFixed(1)}  |  Range: ${(_max - _min).toStringAsFixed(1)}',
                      '✓ راحة ≈ ${_min.toStringAsFixed(1)}  |  ذروة ≈ ${_max.toStringAsFixed(1)}  |  المدى: ${(_max - _min).toStringAsFixed(1)}'),
                  style: const TextStyle(color: Colors.green, fontSize: 12),
                ),
              ),
            ] else if (_s1Val != null && _s3Val != null) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠ Range too small (< 5). Move further to reach peak position.',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ],
          ],
        )),
        const SizedBox(height: 12),
        // Camera preview
        if (_cameraReady && _cameraCtrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: _cameraCtrl!.value.aspectRatio,
              child: CameraPreview(_cameraCtrl!),
            ),
          )
        else if (_cameraError)
          Center(
            child: Text(t('Camera not available', 'الكاميرا غير متاحة'),
                style: const TextStyle(color: Colors.red)),
          )
        else
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _valBadge(String label, double? val, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: val != null
              ? color.withValues(alpha: 0.15)
              : (isDark ? Colors.grey[800] : AppTheme.card(isDark)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: val != null ? color.withValues(alpha: 0.5) : Colors.grey),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.sub(isDark))),
            Text(
              val != null ? val.toStringAsFixed(1) : '—',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: val != null ? color : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 2: Form check thresholds ─────────────────────────────────────────

  Widget _buildChecksStep(bool isDark) {
    if (_checks.isEmpty) {
      return _card(isDark,
          child: Center(
            child: Text(
              t('No form checks defined. Go back to Step 1 and use Gemini AI or add them manually.',
                  'لا توجد فحوصات. ارجع للخطوة الأولى.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black45),
            ),
          ));
    }

    return Column(
      children: _checks.asMap().entries.map((e) {
        final i = e.key;
        final chk = e.value;
        return _card(isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chk.labelEn,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _kCheckColors[i % _kCheckColors.length])),
                const SizedBox(height: 4),
                Text(
                  t('Fires when value ${chk.conditionOp} threshold',
                      'يُطلق عندما ${chk.conditionOp} العتبة'),
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.sub(isDark)),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Text(t('Threshold: ', 'العتبة: '),
                      style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87)),
                  Text(
                    chk.threshold.toStringAsFixed(1),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _kCheckColors[i % _kCheckColors.length]),
                  ),
                ]),
                Slider(
                  value: chk.threshold.clamp(0.0, 180.0),
                  min: 0,
                  max: 180,
                  divisions: 360,
                  activeColor: _kCheckColors[i % _kCheckColors.length],
                  onChanged: (v) =>
                      setState(() => _checks[i] = chk.copyWith(threshold: v)),
                ),
                Row(children: [
                  Text(t('Measurement: ', 'القياس: '),
                      style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.sub(isDark))),
                  Expanded(
                    child: Text(
                      chk.measurement.summary,
                      style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.sub(isDark)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ],
            ));
      }).toList(),
    );
  }

  // ── Step 3: Test run ───────────────────────────────────────────────────────

  Widget _buildTestStep(bool isDark) {
    final result = _testResult;

    return Column(
      children: [
        _card(isDark, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Live Test', 'اختبار مباشر', isDark),
            Text(
              t('Perform 3 reps to verify counting and feedback work correctly.',
                  'قم بـ 3 تكرارات للتحقق من صحة العد والتغذية الراجعة.'),
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.sub(isDark)),
            ),
            const SizedBox(height: 12),
            if (result != null) ...[
              // State badge
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _stateColor(result),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'State: ${_stateLabel(result)}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '✓ ${result.correctReps}  ✗ ${result.incorrectReps}',
                  style: const TextStyle(fontSize: 14),
                ),
              ]),
              const SizedBox(height: 8),
              if (result.feedback.isNotEmpty &&
                  result.feedback != 'Good form') ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(result.feedback,
                      style: const TextStyle(color: Colors.orange)),
                ),
              ],
              if (result.sessionComplete) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    t('✓ Test complete! Rep counting works correctly.',
                        '✓ اكتمل الاختبار! العد يعمل بشكل صحيح.'),
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
              ],
            ] else
              Text(
                _cameraReady
                    ? t('Move in front of camera...', 'تحرك أمام الكاميرا...')
                    : t('Starting camera...', 'جارٍ تشغيل الكاميرا...'),
                style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45),
              ),
          ],
        )),
        const SizedBox(height: 12),
        if (_cameraReady && _cameraCtrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: _cameraCtrl!.value.aspectRatio,
              child: CameraPreview(_cameraCtrl!),
            ),
          )
        else
          const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _testResult = null;
              _testProcessor?.reset();
            });
          },
          icon: const Icon(Icons.refresh),
          label: Text(t('Retry test', 'إعادة الاختبار')),
        ),
      ],
    );
  }

  Color _stateColor(ExerciseResult r) {
    if (r.waitingForReset) return Colors.purple;
    if (!r.jointsDetected) return Colors.grey;
    if (r.primaryAngle == 0) return Colors.grey;
    return const Color(0xFF00BCD4);
  }

  String _stateLabel(ExerciseResult r) {
    if (!r.jointsDetected) return 'Not detected';
    if (r.waitingForReset) return 'Rest';
    return r.currentSet < 1 ? 'Initializing' : 'Active';
  }

  // ── Step 4: Save / add to program ─────────────────────────────────────────

  Widget _buildSaveStep(bool isDark) {
    final config = _assembleConfig();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(isDark, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Exercise Summary', 'ملخص التمرين', isDark),
            const SizedBox(height: 8),
            _summaryRow(isDark, 'Name', config.name),
            _summaryRow(isDark, 'View', config.view),
            _summaryRow(isDark, 'Mode', config.mode),
            _summaryRow(isDark, 'Primary', config.primaryMeasurement.summary),
            _summaryRow(isDark, 'Form checks', '${config.formChecks.length}'),
            _summaryRow(isDark, 'State range',
                '${_min.toStringAsFixed(1)} → ${_max.toStringAsFixed(1)}'),
          ],
        )),

        const SizedBox(height: 12),

        _card(isDark, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Session Parameters', 'معاملات الجلسة', isDark),
            const SizedBox(height: 8),
            Text(
              t('Reps per set: $_finalReps', 'تكرارات لكل مجموعة: $_finalReps'),
              style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87),
            ),
            Slider(
              value: _finalReps.toDouble(),
              min: 3, max: 20, divisions: 17,
              activeColor: const Color(0xFF00BCD4),
              onChanged: (v) => setState(() => _finalReps = v.toInt()),
            ),
            Text(
              t('Sets: $_finalSets', 'مجموعات: $_finalSets'),
              style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87),
            ),
            Slider(
              value: _finalSets.toDouble(),
              min: 1, max: 6, divisions: 5,
              activeColor: const Color(0xFF00BCD4),
              onChanged: (v) => setState(() => _finalSets = v.toInt()),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text(t('Difficulty: ', 'الصعوبة: '),
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Beginner'),
                selected: _finalMode == 'Beginner',
                onSelected: (_) => setState(() => _finalMode = 'Beginner'),
                selectedColor: const Color(0xFF00BCD4),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Pro'),
                selected: _finalMode == 'Pro',
                onSelected: (_) => setState(() => _finalMode = 'Pro'),
                selectedColor: Colors.orange,
              ),
            ]),
          ],
        )),

        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              final exercise = ProgramExercise(
                type: 'custom',
                targetReps: _finalReps,
                targetSets: _finalSets,
                mode: _finalMode,
                customConfig: _assembleConfig(),
              );
              widget.onAddToProgram(exercise);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.add_circle_outline),
            label: Text(t(
                'Add to Program for ${widget.patientName}',
                'إضافة للبرنامج')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(bool isDark, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.sub(isDark))),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text(isDark))),
        ),
      ]),
    );
  }

  // ── Navigation row ─────────────────────────────────────────────────────────

  Widget _buildNavRow(bool isDark) {
    final canNext = switch (_step) {
      0 => _step0Valid,
      1 => _step1Valid,
      2 => true,
      3 => true,
      _ => false,
    };

    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (_step > 0)
            OutlinedButton(
              onPressed: () => _goToStep(_step - 1),
              child: Text(t('← Back', '← رجوع')),
            ),
          const Spacer(),
          if (_step < _totalSteps - 1)
            ElevatedButton(
              onPressed: canNext ? () => _goToStep(_step + 1) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                foregroundColor: Colors.white,
              ),
              child: Text(t('Next →', 'التالي →')),
            ),
        ],
      ),
    );
  }

  // ── Shared widget helpers ──────────────────────────────────────────────────

  Widget _card(bool isDark, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String en, String ar, bool isDark) {
    return Text(
      t(en, ar),
      style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: AppTheme.text(isDark)),
    );
  }

  InputDecoration _inputDec(String hint, String hintAr, bool isDark) {
    return InputDecoration(
      hintText: t(hint, hintAr),
      hintStyle: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38, fontSize: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
    );
  }
}

// ── Editable form check (mutable in wizard state) ──────────────────────────

class _EditableCheck {
  final String id;
  String labelEn;
  String labelAr;
  String conditionOp;
  double threshold;
  final MeasurementConfig measurement;
  bool affectsRep;
  final List<String> skipInStates;
  final bool requireS2Seen;

  _EditableCheck({
    required this.id,
    required this.labelEn,
    required this.labelAr,
    required this.conditionOp,
    required this.threshold,
    required this.measurement,
    this.affectsRep = false,
    this.skipInStates = const [],
    this.requireS2Seen = false,
  });

  _EditableCheck copyWith({
    String? labelEn,
    String? labelAr,
    String? conditionOp,
    double? threshold,
    bool? affectsRep,
  }) =>
      _EditableCheck(
        id: id,
        labelEn: labelEn ?? this.labelEn,
        labelAr: labelAr ?? this.labelAr,
        conditionOp: conditionOp ?? this.conditionOp,
        threshold: threshold ?? this.threshold,
        measurement: measurement,
        affectsRep: affectsRep ?? this.affectsRep,
        skipInStates: skipInStates,
        requireS2Seen: requireS2Seen,
      );
}
