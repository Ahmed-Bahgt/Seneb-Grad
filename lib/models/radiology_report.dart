import 'package:cloud_firestore/cloud_firestore.dart';

class RadiologyReport {
  final String id;
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final String modality;
  final String bodyPart;
  final String prediction;
  final String confidence;
  final String finalReport;
  final List<String> ragGuidelines;
  final String? heatmapBase64;
  final bool specialistUsed;
  final DateTime createdAt;

  const RadiologyReport({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    required this.modality,
    required this.bodyPart,
    required this.prediction,
    required this.confidence,
    required this.finalReport,
    required this.ragGuidelines,
    this.heatmapBase64,
    required this.specialistUsed,
    required this.createdAt,
  });

  factory RadiologyReport.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RadiologyReport(
      id: doc.id,
      patientId: data['patientId'] as String? ?? '',
      patientName: data['patientName'] as String? ?? '',
      doctorId: data['doctorId'] as String? ?? '',
      doctorName: data['doctorName'] as String? ?? '',
      modality: data['modality'] as String? ?? '',
      bodyPart: data['bodyPart'] as String? ?? '',
      prediction: data['prediction'] as String? ?? '',
      confidence: data['confidence'] as String? ?? '',
      finalReport: data['finalReport'] as String? ?? '',
      ragGuidelines: (data['ragGuidelines'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      heatmapBase64: data['heatmapBase64'] as String?,
      specialistUsed: data['specialistUsed'] as bool? ?? false,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'patientId': patientId,
        'patientName': patientName,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'modality': modality,
        'bodyPart': bodyPart,
        'prediction': prediction,
        'confidence': confidence,
        'finalReport': finalReport,
        'ragGuidelines': ragGuidelines,
        'heatmapBase64': heatmapBase64,
        'specialistUsed': specialistUsed,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
