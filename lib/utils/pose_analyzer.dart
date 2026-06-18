enum PoseLevel { beginner, pro }
enum SquatState { normal, trans, pass, none }

// Exact thresholds from thresholds.py
class PoseThresholdConfig {
  PoseThresholdConfig.beginner()
      : hipKneeVertNormal = (0, 30),
        hipKneeVertTrans = (35, 65),
        hipKneeVertPass = (70, 95),
        hipThresh = (10, 60),
        ankleThresh = 45,
        kneeThresh = (50, 70, 95),
        offsetThresh = 50.0,
        inactiveThresh = 15.0,
        cntFrameThresh = 50;

  PoseThresholdConfig.pro()
      : hipKneeVertNormal = (0, 30),
        hipKneeVertTrans = (35, 65),
        hipKneeVertPass = (80, 95),
        hipThresh = (15, 50),
        ankleThresh = 30,
        kneeThresh = (50, 80, 95),
        offsetThresh = 50.0,
        inactiveThresh = 15.0,
        cntFrameThresh = 50;

  final (int, int) hipKneeVertNormal;
  final (int, int) hipKneeVertTrans;
  final (int, int) hipKneeVertPass;
  final (int, int) hipThresh;
  final int ankleThresh;
  final (int, int, int) kneeThresh;
  final double offsetThresh;
  final double inactiveThresh;
  final int cntFrameThresh;

  // Getters for convenience
  int get hipThreshMin => hipThresh.$1;
  int get hipThreshMax => hipThresh.$2;
  int get kneeThreshMin => kneeThresh.$1;
  int get kneeThreshMid => kneeThresh.$2;
  int get kneeThreshMax => kneeThresh.$3;
}
