import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../../models/radiology_report.dart';
import '../../utils/patient_manager.dart';
import '../../utils/theme_provider.dart';
import '../../widgets/custom_app_bar.dart';

class MedicalHubScreen extends StatelessWidget {
  final VoidCallback? onBack;

  const MedicalHubScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) {
      return Scaffold(
        appBar: CustomAppBar(
            title: t('Medical Hub', 'المركز الطبي'), onBack: onBack),
        body: Center(
          child: Text(t('Please login first', 'يرجى تسجيل الدخول أولا')),
        ),
      );
    }

    return Scaffold(
      appBar:
          CustomAppBar(title: t('Medical Hub', 'المركز الطبي'), onBack: onBack),
      backgroundColor: AppTheme.bg(isDark),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('patients')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Text(
                t('No medical data available', 'لا توجد بيانات طبية متاحة'),
                style: TextStyle(
                  color: AppTheme.sub(isDark),
                ),
              ),
            );
          }

          final data = snapshot.data!.data() ?? {};
          final history = MedicalHistoryData.fromMap(
            data['medicalHistory'] is Map
                ? Map<String, dynamic>.from(data['medicalHistory'] as Map)
                : null,
          );

          final prescriptions = (data['prescriptions'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((item) => TreatmentPrescription.fromMap(
                  Map<String, dynamic>.from(item)))
              .toList()
            ..sort((a, b) {
              final aDate = a.updatedAt ?? a.createdAt ?? DateTime(1970);
              final bDate = b.updatedAt ?? b.createdAt ?? DateTime(1970);
              return bDate.compareTo(aDate);
            });

          return RefreshIndicator(
            onRefresh: () => Future.delayed(const Duration(milliseconds: 600)),
            color: const Color(0xFF00BCD4),
            child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                decoration: _cardDecoration(isDark),
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    leading: const Icon(Icons.assignment_outlined,
                        color: Color(0xFF00BCD4), size: 20),
                    title: Text(
                      t('Medical History', 'التاريخ المرضي'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.text(isDark),
                      ),
                    ),
                    iconColor: AppTheme.sub(isDark),
                    collapsedIconColor: AppTheme.sub(isDark),
                    initiallyExpanded: false,
                    children: [_historyContent(context, history, isDark)],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle(
                context,
                t('Treatment Prescriptions', 'الروشتات العلاجية'),
                Icons.medication_outlined,
              ),
              const SizedBox(height: 10),
              if (prescriptions.isEmpty)
                _emptyCard(
                  context,
                  t('No treatment prescriptions yet',
                      'لا توجد روشتات علاجية حتى الآن'),
                )
              else
                ...prescriptions.asMap().entries.map(
                      (entry) => _prescriptionCard(
                          context, entry.value, entry.key == 0),
                    ),

              // ── Radiology Reports ─────────────────────────
              const SizedBox(height: 20),
              _sectionTitle(
                context,
                t('Radiology Reports', 'تقارير الأشعة'),
                Icons.image_search,
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('patients')
                    .doc(user.uid)
                    .collection('radiology_reports')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (ctx, rSnap) {
                  if (rSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!rSnap.hasData || rSnap.data!.docs.isEmpty) {
                    return _emptyCard(
                      ctx,
                      t('No radiology reports yet',
                          'لا توجد تقارير أشعة حتى الآن'),
                    );
                  }
                  return Column(
                    children: rSnap.data!.docs.map((doc) {
                      final report = RadiologyReport.fromFirestore(doc);
                      final isAbnormal =
                          report.prediction.toLowerCase().contains('abnormal') ||
                          report.prediction.toLowerCase().contains('fracture');
                      final badgeColor =
                          isAbnormal ? Colors.red : Colors.green;
                      final dt = report.createdAt;
                      final dateStr =
                          '${dt.day.toString().padLeft(2, '0')}/'
                          '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: _cardDecoration(isDark),
                        child: Theme(
                          data: Theme.of(context)
                              .copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            leading: const Icon(Icons.image_search,
                                color: Color(0xFF00BCD4), size: 20),
                            title: Text(
                              '${report.bodyPart} — ${report.modality}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.text(isDark),
                              ),
                            ),
                            subtitle: Row(children: [
                              Flexible(
                                child: Text(dateStr,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.sub(isDark).withValues(alpha: 0.8))),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color:
                                          badgeColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(report.prediction,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: badgeColor)),
                              ),
                            ]),
                            iconColor: AppTheme.sub(isDark),
                            collapsedIconColor: AppTheme.sub(isDark),
                            children: [
                              MarkdownBody(
                                data: report.finalReport.isNotEmpty
                                    ? report.finalReport
                                    : '_No report text_',
                                styleSheet: MarkdownStyleSheet(
                                  p: TextStyle(
                                      fontSize: 13,
                                      height: 1.6,
                                      color: AppTheme.text(isDark)),
                                ),
                              ),
                              if (report.heatmapBase64 != null) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.image),
                                    label: Text(t('View Heatmap',
                                        'عرض الخريطة الحرارية')),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF00BCD4),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => showDialog(
                                      context: context,
                                      builder: (_) => Dialog(
                                        child: Image.memory(
                                          base64Decode(
                                              report.heatmapBase64!),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              // ── Workout History ───────────────────────────
              const SizedBox(height: 20),
              _sectionTitle(
                context,
                t('Workout History', 'سجل التمارين'),
                Icons.fitness_center,
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('patients')
                    .doc(user.uid)
                    .collection('Sessions')
                    .orderBy('timestamp', descending: true)
                    .limit(10)
                    .snapshots(),
                builder: (ctx, wSnap) {
                  if (wSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!wSnap.hasData || wSnap.data!.docs.isEmpty) {
                    return _emptyCard(
                      ctx,
                      t('No workout sessions yet',
                          'لا توجد جلسات تمرين حتى الآن'),
                    );
                  }
                  return Column(
                    children: wSnap.data!.docs.map((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      final ts = d['timestamp'];
                      final date = ts is Timestamp
                          ? ts.toDate()
                          : DateTime.now();
                      final dateStr =
                          '${date.day.toString().padLeft(2, '0')}/'
                          '${date.month.toString().padLeft(2, '0')}/'
                          '${date.year}';
                      final accuracy =
                          (d['accuracy'] as num?)?.toDouble() ?? 0.0;
                      final correctReps =
                          (d['correctReps'] as num?)?.toInt() ?? 0;
                      final incorrectReps =
                          (d['incorrectReps'] as num?)?.toInt() ?? 0;
                      final currentSet =
                          (d['currentSet'] as num?)?.toInt() ?? 0;
                      final effectiveSets =
                          (d['effectiveSets'] as num?)?.toInt() ?? 0;
                      final accColor = accuracy >= 70
                          ? Colors.green
                          : accuracy >= 40
                              ? Colors.orange
                              : Colors.red;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: _cardDecoration(isDark),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: accColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${accuracy.toStringAsFixed(0)}%',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: accColor,
                                  fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dateStr,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: AppTheme.text(isDark))),
                                const SizedBox(height: 4),
                                Text(
                                  '${t('Correct', 'صحيح')}: $correctReps  '
                                  '${t('Wrong', 'خاطئ')}: $incorrectReps  '
                                  '${t('Sets', 'مجموعات')}: $currentSet  '
                                  '${t('Eff', 'فعّالة')}: $effectiveSets',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.sub(isDark)),
                                ),
                              ],
                            ),
                          ),
                        ]),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),   // ListView
          );   // RefreshIndicator
        },
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00BCD4), size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppTheme.text(isDark),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _historyContent(
      BuildContext context, MedicalHistoryData history, bool isDark) {
    final items = <String, String>{
      t('Age', 'العمر'): history.age?.toString() ?? '-',
      t('Height', 'الطول'):
          history.heightCm == null ? '-' : '${history.heightCm} cm',
      t('Weight', 'الوزن'):
          history.weightKg == null ? '-' : '${history.weightKg} kg',
      t('Walking', 'المشي'):
          history.walkingDuration.isEmpty ? '-' : history.walkingDuration,
      t('Meals/day', 'الوجبات/اليوم'):
          history.mealsPerDay.isEmpty ? '-' : history.mealsPerDay,
      t('Smoking', 'التدخين'):
          history.smokingStatus.isEmpty ? '-' : history.smokingStatus,
      t('Pain level', 'مستوى الألم'):
          history.painLevel.isEmpty ? '-' : history.painLevel,
      t('Sleep quality', 'جودة النوم'):
          history.sleepQuality.isEmpty ? '-' : history.sleepQuality,
      t('Chronic conditions', 'الأمراض المزمنة'):
          history.chronicConditions.isEmpty ? '-' : history.chronicConditions,
      t('Medications', 'الأدوية'):
          history.medications.isEmpty ? '-' : history.medications,
      t('Allergies', 'الحساسية'):
          history.allergies.isEmpty ? '-' : history.allergies,
      t('Updated by doctor', 'آخر تحديث بواسطة الطبيب'):
          history.updatedByDoctorName.isEmpty
              ? '-'
              : history.updatedByDoctorName,
      t('Updated at', 'تاريخ التحديث'): _formatDate(history.updatedAt),
    };

    return Column(
      children: items.entries
          .map((entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          color: AppTheme.sub(isDark),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: AppTheme.text(isDark),
                        ),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _prescriptionCard(
      BuildContext context, TreatmentPrescription item, bool isActive) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.treatmentName.isEmpty
                      ? t('Untitled treatment', 'علاج بدون عنوان')
                      : item.treatmentName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text(isDark),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF00BCD4).withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive ? const Color(0xFF00BCD4) : Colors.orange,
                    width: 1,
                  ),
                ),
                child: Text(
                  isActive ? t('Active', 'حالية') : t('Old', 'قديمة'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive ? const Color(0xFF00BCD4) : Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDate(item.updatedAt ?? item.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.sub(isDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _infoLine(context, t('Doctor', 'الطبيب'),
              item.doctorName.isEmpty ? '-' : item.doctorName),
          if (item.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t('Medications', 'الأدوية')}:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text(isDark),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...item.items.asMap().entries.map(
                        (entry) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: AppTheme.cardDeco(isDark, radius: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${t('Medication', 'دواء')} ${entry.key + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.text(isDark),
                                ),
                              ),
                              const SizedBox(height: 6),
                              _infoLine(
                                context,
                                t('Name', 'الاسم'),
                                entry.value.medication.isEmpty
                                    ? '-'
                                    : entry.value.medication,
                              ),
                              _infoLine(
                                context,
                                t('Dosage', 'الجرعة'),
                                entry.value.dosage.isEmpty
                                    ? '-'
                                    : entry.value.dosage,
                              ),
                              _infoLine(
                                context,
                                t('Duration', 'المدة'),
                                entry.value.duration.isEmpty
                                    ? '-'
                                    : entry.value.duration,
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            )
          else
            _infoLine(context, t('Medications', 'الأدوية'), '-'),
          _infoLine(context, t('Notes', 'ملاحظات'),
              item.notes.isEmpty ? '-' : item.notes),
        ],
      ),
    );
  }

  Widget _infoLine(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.text(isDark),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppTheme.text(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(BuildContext context, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(isDark),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.sub(isDark),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration(bool isDark) => AppTheme.cardDeco(isDark, radius: 12);

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('dd MMM yyyy, h:mm a').format(date);
  }
}
