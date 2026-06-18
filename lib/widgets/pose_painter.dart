import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Custom painter to draw pose skeleton and reference lines/angles.
///
/// Two modes:
///  - Side view (Squat): draws one half of the body (left or right) selected
///    by [selectedSide]. Used together with [hipAngle] / [kneeAngle] /
///    [ankleAngle] for the squat angle labels.
///  - Front view (Abduction, Internal Rotation, Lateral Raise, custom
///    front-view): draws the full upper body (both arms + torso + hips)
///    bilaterally. [selectedSide] is ignored.
class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;
  final double? hipAngle;
  final double? kneeAngle;
  final double? ankleAngle;
  final bool drawReferences;
  final String? selectedSide; // 'left' or 'right' (side view only)
  final String view; // 'front' or 'side'

  PosePainter({
    required this.poses,
    required this.imageSize,
    this.hipAngle,
    this.kneeAngle,
    this.ankleAngle,
    this.drawReferences = false,
    this.selectedSide,
    this.view = 'side',
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (poses.isEmpty) return;

    final pose = poses.first;
    final landmarks = pose.landmarks;

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    final landmarkPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;

    final connectionPaint = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final refPaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    if (view == 'front') {
      _drawFrontConnections(canvas, landmarks, scaleX, scaleY, connectionPaint);
      _drawFrontLandmarks(canvas, landmarks, scaleX, scaleY, landmarkPaint);
    } else {
      _drawSideConnections(canvas, landmarks, scaleX, scaleY, connectionPaint);
      _drawSideLandmarks(canvas, landmarks, scaleX, scaleY, landmarkPaint);
      if (drawReferences) {
        _drawReferenceLinesAndAngles(canvas, size, landmarks, scaleX, scaleY, refPaint);
      }
    }
  }

  // ── Front view: bilateral upper body ────────────────────────────────────
  void _drawFrontConnections(
    Canvas canvas,
    Map<PoseLandmarkType, PoseLandmark> lm,
    double scaleX,
    double scaleY,
    Paint paint,
  ) {
    const connections = [
      // Shoulders + arms (both sides)
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
      // Torso
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    ];

    for (final c in connections) {
      final start = lm[c[0]];
      final end = lm[c[1]];
      if (start == null || end == null) continue;
      canvas.drawLine(
        Offset(start.x * scaleX, start.y * scaleY),
        Offset(end.x * scaleX, end.y * scaleY),
        paint,
      );
    }
  }

  void _drawFrontLandmarks(
    Canvas canvas,
    Map<PoseLandmarkType, PoseLandmark> lm,
    double scaleX,
    double scaleY,
    Paint paint,
  ) {
    const types = [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ];
    for (final type in types) {
      final p = lm[type];
      if (p == null) continue;
      canvas.drawCircle(Offset(p.x * scaleX, p.y * scaleY), 6, paint);
    }
  }

  // ── Side view: one half of body, used for squats ────────────────────────
  void _drawSideConnections(
    Canvas canvas,
    Map<PoseLandmarkType, PoseLandmark> landmarks,
    double scaleX,
    double scaleY,
    Paint paint,
  ) {
    if (selectedSide == null) return;

    final connections = selectedSide == 'left'
        ? const [
            [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
            [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
            [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
            [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
            [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
            [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex],
          ]
        : const [
            [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
            [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
            [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
            [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
            [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
            [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex],
          ];

    for (final connection in connections) {
      final start = landmarks[connection[0]];
      final end = landmarks[connection[1]];
      if (start != null && end != null) {
        canvas.drawLine(
          Offset(start.x * scaleX, start.y * scaleY),
          Offset(end.x * scaleX, end.y * scaleY),
          paint,
        );
      }
    }
  }

  void _drawSideLandmarks(
    Canvas canvas,
    Map<PoseLandmarkType, PoseLandmark> landmarks,
    double scaleX,
    double scaleY,
    Paint paint,
  ) {
    if (selectedSide == null) return;
    final side = selectedSide == 'left'
        ? const [
            PoseLandmarkType.leftShoulder,
            PoseLandmarkType.leftElbow,
            PoseLandmarkType.leftWrist,
            PoseLandmarkType.leftHip,
            PoseLandmarkType.leftKnee,
            PoseLandmarkType.leftAnkle,
            PoseLandmarkType.leftFootIndex,
          ]
        : const [
            PoseLandmarkType.rightShoulder,
            PoseLandmarkType.rightElbow,
            PoseLandmarkType.rightWrist,
            PoseLandmarkType.rightHip,
            PoseLandmarkType.rightKnee,
            PoseLandmarkType.rightAnkle,
            PoseLandmarkType.rightFootIndex,
          ];

    for (final type in side) {
      final landmark = landmarks[type];
      if (landmark == null) continue;
      canvas.drawCircle(
        Offset(landmark.x * scaleX, landmark.y * scaleY),
        6,
        paint,
      );
    }
  }

  void _drawReferenceLinesAndAngles(
    Canvas canvas,
    Size size,
    Map<PoseLandmarkType, PoseLandmark> lm,
    double scaleX,
    double scaleY,
    Paint refPaint,
  ) {
    final leftShoulder = lm[PoseLandmarkType.leftShoulder];
    final rightShoulder = lm[PoseLandmarkType.rightShoulder];
    final leftFoot = lm[PoseLandmarkType.leftFootIndex] ?? lm[PoseLandmarkType.leftHeel];
    final rightFoot = lm[PoseLandmarkType.rightFootIndex] ?? lm[PoseLandmarkType.rightHeel];

    if (leftShoulder == null || rightShoulder == null || leftFoot == null || rightFoot == null) return;

    final leftSpan = (leftFoot.y - leftShoulder.y).abs();
    final rightSpan = (rightFoot.y - rightShoulder.y).abs();
    final useLeft = leftSpan >= rightSpan;

    final hip = lm[useLeft ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip];
    final knee = lm[useLeft ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee];
    final ankle = lm[useLeft ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle];

    if (hip == null || knee == null || ankle == null) return;

    final hipX = hip.x * scaleX;
    final kneeX = knee.x * scaleX;
    final ankleX = ankle.x * scaleX;

    const textStyle = TextStyle(
      color: Colors.lightGreenAccent,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );

    void drawAngle(double? angle, double x, double y) {
      if (angle == null) return;
      final tp = TextPainter(
        text: TextSpan(text: angle.toInt().toString(), style: textStyle),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x + 8, y - 16));
    }

    drawAngle(hipAngle, hipX, hip.y * scaleY);
    drawAngle(kneeAngle, kneeX, knee.y * scaleY);
    drawAngle(ankleAngle, ankleX, ankle.y * scaleY);
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.poses != poses ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.hipAngle != hipAngle ||
        oldDelegate.kneeAngle != kneeAngle ||
        oldDelegate.ankleAngle != ankleAngle ||
        oldDelegate.drawReferences != drawReferences ||
        oldDelegate.selectedSide != selectedSide ||
        oldDelegate.view != view;
  }
}
