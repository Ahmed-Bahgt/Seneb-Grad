// =============================================================================
// PATIENT PROFILE SCREEN - DETAILED PATIENT VIEW & EDITING
// =============================================================================
// Purpose: View and edit comprehensive patient information
// Displays:
// - Patient basic info: Name, diagnosis, phone, email
// - Progress overview with visual progress bar
// - Last session, next appointment, doctor's notes
// Editable Fields:
// - Assigned Treatment Plan (dropdown with options: None, Squat, More coming soon...)
// - Doctor's Notes (multi-line text area)
// Actions:
// - Submit button to save all changes
// - Changes sync back to PatientManager (updates everywhere)
// =============================================================================

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../models/radiology_report.dart';
import '../../models/exercise_program.dart';
import '../../widgets/custom_app_bar.dart';
import '../../utils/theme_provider.dart';
import '../../utils/patient_manager.dart';
import '../../services/database_service.dart';
import 'exercise_builder_screen.dart';
import 'medical_history_form_screen.dart';
import 'patient_reports_screen.dart';
import 'treatment_prescription_form_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Patient Profile Screen - View and edit patient details
class PatientProfileScreen extends StatefulWidget {
  final PatientData patient;
  final Function(PatientData) onUpdate;

  const PatientProfileScreen({
    super.key,
    required this.patient,
    required this.onUpdate,
  });

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  late TextEditingController _notesController;
  late TextEditingController _sessionsController;
  late TextEditingController _setsController;
  late TextEditingController _repsController;
  late String _selectedMode;
  late String _selectedPlan;
  late MedicalHistoryData _currentMedicalHistory;
  late List<TreatmentPrescription> _currentPrescriptions;
  ExerciseProgram? _currentProgram;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.patient.notes);
    _sessionsController =
        TextEditingController(text: widget.patient.sessions.toString());
    _setsController =
        TextEditingController(text: widget.patient.sets.toString());
    _repsController =
        TextEditingController(text: widget.patient.reps.toString());
    _selectedMode = widget.patient.assignedMode.isNotEmpty
        ? widget.patient.assignedMode
        : 'Beginner';
    _selectedPlan = widget.patient.assignedPlan;
    _currentMedicalHistory = widget.patient.medicalHistory;
    _currentPrescriptions = List<TreatmentPrescription>.from(
      widget.patient.prescriptions,
    );
    _loadCurrentProgram();
  }

  Future<void> _loadCurrentProgram() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patient.id)
          .get();
      final data = doc.data();
      if (data != null && data['assignedProgram'] is Map) {
        final program = ExerciseProgram.fromFirestore(
          Map<String, dynamic>.from(data['assignedProgram'] as Map),
        );
        if (mounted) setState(() => _currentProgram = program);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _notesController.dispose();
    _sessionsController.dispose();
    _setsController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  void _submitChanges() async {
    final updatedPatient = _buildPatientFromCurrentForm();

    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(t('Saving changes...', 'جاري حفظ التغييرات...')),
            ],
          ),
        ),
      );
    }

    try {
      final result = widget.onUpdate(updatedPatient);
      if (result is Future) {
        await result;
      }

      if (!mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('Patient details updated', 'تم تحديث بيانات المريض')),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Wait for snackbar to display then navigate back
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('Error saving patient: ', 'خطأ في حفظ المريض: ') +
              e.toString()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      debugPrint('Error in _submitChanges: $e');
    }
  }

  PatientData _buildPatientFromCurrentForm(
      {MedicalHistoryData? historyOverride}) {
    return widget.patient.copyWith(
      assignedPlan: _selectedPlan,
      assignedMode: _selectedMode,
      notes: _notesController.text,
      sessions:
          int.tryParse(_sessionsController.text) ?? widget.patient.sessions,
      sets: int.tryParse(_setsController.text) ?? widget.patient.sets,
      reps: int.tryParse(_repsController.text) ?? widget.patient.reps,
      medicalHistory: historyOverride ?? _currentMedicalHistory,
      prescriptions: _currentPrescriptions,
    );
  }

  Future<void> _openMedicalHistoryForm() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => MedicalHistoryFormScreen(
          patient: _buildPatientFromCurrentForm(),
          onSave: (history) async {
            await PatientManager().saveMedicalHistory(
              _buildPatientFromCurrentForm(),
              history,
            );
            if (mounted) {
              setState(() {
                _currentMedicalHistory = history;
              });
            }
          },
        ),
      ),
    );
  }

  Future<void> _openPrescriptionForm() async {
    final currentDoctorId = FirebaseAuth.instance.currentUser?.uid ?? '';
    TreatmentPrescription? initial;
    if (currentDoctorId.isNotEmpty) {
      for (final item in _currentPrescriptions) {
        if (item.doctorId == currentDoctorId) {
          initial = item;
          break;
        }
      }
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => TreatmentPrescriptionFormScreen(
          patient: _buildPatientFromCurrentForm(),
          initialPrescription: initial,
          onSave: (prescription) async {
            await PatientManager().saveTreatmentPrescription(
              _buildPatientFromCurrentForm(),
              prescription,
            );

            final refreshed = List<TreatmentPrescription>.from(
              _currentPrescriptions,
            );
            final idx = refreshed.indexWhere(
              (item) => item.doctorId == currentDoctorId,
            );
            final now = DateTime.now();
            if (idx >= 0) {
              final old = refreshed[idx];
              refreshed[idx] = prescription.copyWith(
                id: old.id,
                doctorId: currentDoctorId,
                doctorName: old.doctorName,
                createdAt: old.createdAt,
                updatedAt: now,
              );
            } else {
              refreshed.add(
                prescription.copyWith(
                  doctorId: currentDoctorId,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
            }

            if (mounted) {
              setState(() {
                _currentPrescriptions = refreshed;
              });
            }
          },
        ),
      ),
    );
  }

  void _showXrayReports(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.text(isDark);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                const Icon(Icons.image_search, color: Color(0xFF00BCD4)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'X-Ray Reports — ${widget.patient.name}',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close,
                      color: AppTheme.sub(isDark)),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('patients')
                    .doc(widget.patient.id)
                    .collection('radiology_reports')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text('No radiology reports yet',
                          style: TextStyle(
                              color: isDark
                                  ? Colors.white54
                                  : Colors.black45)),
                    );
                  }
                  return ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.all(12),
                    itemCount: snapshot.data!.docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final report = RadiologyReport.fromFirestore(
                          snapshot.data!.docs[i]);
                      final isAbnormal =
                          report.prediction.toLowerCase().contains('abnormal') ||
                          report.prediction.toLowerCase().contains('fracture');
                      final badgeColor =
                          isAbnormal ? Colors.red : Colors.green;
                      final dt = report.createdAt;
                      final dateStr =
                          '${dt.day.toString().padLeft(2, '0')}/'
                          '${dt.month.toString().padLeft(2, '0')}/'
                          '${dt.year}';
                      return GestureDetector(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: isDark
                                ? AppTheme.card(isDark)
                                : Colors.white,
                            insetPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 24),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${report.bodyPart} — ${report.modality}',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: textColor),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(dateStr,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.black45)),
                                  const Divider(height: 20),
                                  Flexible(
                                    child: SingleChildScrollView(
                                      child: MarkdownBody(
                                        data: report.finalReport.isNotEmpty
                                            ? report.finalReport
                                            : '_No report text_',
                                        styleSheet: MarkdownStyleSheet(
                                          p: TextStyle(
                                              fontSize: 13,
                                              height: 1.6,
                                              color: textColor),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (report.heatmapBase64 != null) ...[
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.image),
                                      label:
                                          const Text('View Grad-CAM Heatmap'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF00BCD4),
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        showDialog(
                                          context: context,
                                          builder: (_) => Dialog(
                                            child: Image.memory(
                                              base64Decode(
                                                  report.heatmapBase64!),
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF00BCD4)),
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close',
                                        style:
                                            TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppTheme.bg(isDark)
                                : Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: isDark
                                    ? Colors.white12
                                    : Colors.grey.shade200),
                          ),
                          child: Row(children: [
                            const Icon(Icons.image_search,
                                color: Color(0xFF00BCD4), size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${report.bodyPart} — ${report.modality}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: textColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(dateStr,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.black45)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color:
                                        badgeColor.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                report.prediction,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: badgeColor),
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppBar(
        title: widget.patient.name,
        onBack: () => Navigator.pop(context),
      ),
      backgroundColor: AppTheme.bg(isDark),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Patient Avatar and Basic Info
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor:
                      const Color(0xFF00BCD4).withValues(alpha: 0.2),
                  child: Text(
                    widget.patient.name
                        .split(' ')
                        .map((e) => e[0])
                        .take(2)
                        .join(),
                    style: const TextStyle(
                      color: Color(0xFF00BCD4),
                      fontWeight: FontWeight.bold,
                      fontSize: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.patient.name,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text(isDark),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Progress Section
          _buildSectionCard(
            isDark: isDark,
            title: t('Progress Overview', 'نظرة عامة على التقدم'),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        t('Overall Progress', 'التقدم الإجمالي'),
                        style: TextStyle(fontSize: 14, color: AppTheme.sub(isDark)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(widget.patient.progress * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8BC34A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: widget.patient.progress,
                    minHeight: 12,
                    backgroundColor: isDark ? Colors.white12 : Colors.grey[300],
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF8BC34A)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Patient Details Section
          _buildSectionCard(
            isDark: isDark,
            title: t('Patient Details', 'تفاصيل المريض'),
            child: Column(
              children: [
                _buildDetailRow(
                  icon: Icons.medical_services,
                  label: t('Diagnosis', 'التشخيص'),
                  value: widget.patient.diagnosis,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildDetailRow(
                  icon: Icons.phone,
                  label: t('Phone', 'الهاتف'),
                  value: widget.patient.phone,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildDetailRow(
                  icon: Icons.email,
                  label: t('Email', 'البريد الإلكتروني'),
                  value: widget.patient.email,
                  isDark: isDark,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Exercise Program Section
          _buildSectionCard(
            isDark: isDark,
            title: t('Exercise Program', 'برنامج التمارين'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_currentProgram != null && _currentProgram!.exercises.isNotEmpty) ...[
                  // Program summary
                  Row(children: [
                    const Icon(Icons.check_circle, color: Color(0xFF00BCD4), size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _currentProgram!.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14,
                          color: AppTheme.text(isDark),
                        ),
                      ),
                    ),
                    Text(
                      '${_currentProgram!.exercises.length} ${t("exercises", "تمارين")}',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  ...List.generate(_currentProgram!.exercises.length, (i) {
                    final ex = _currentProgram!.exercises[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00BCD4).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF00BCD4),
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(ex.type,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.text(isDark))),
                        ),
                        Text(
                          '${ex.targetSets}×${ex.targetReps}  ${ex.mode}',
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.black45),
                        ),
                      ]),
                    );
                  }),
                  const SizedBox(height: 12),
                ] else ...[
                  Text(
                    t('No program assigned yet. Use the builder to create one.',
                        'لم يتم تعيين برنامج بعد. استخدم المنشئ لإنشاء برنامج.'),
                    style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black45),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExerciseBuilderScreen(
                          patientId: widget.patient.id,
                          patientName: widget.patient.name,
                          existingProgram: _currentProgram,
                          onSave: (program) async {
                            await DatabaseService().saveExerciseProgram(
                              patientId: widget.patient.id,
                              program: program,
                            );
                            await PatientManager().refreshPatients();
                            if (mounted) {
                              setState(() => _currentProgram = program);
                            }
                          },
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.build_outlined, size: 18),
                    label: Text(
                      _currentProgram != null
                          ? t('Edit Exercise Program', 'تعديل برنامج التمارين')
                          : t('Build Exercise Program', 'بناء برنامج التمارين'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BCD4),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Notes Section
          _buildSectionCard(
            isDark: isDark,
            title: t('Doctor\'s Notes', 'ملاحظات الطبيب'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Add notes about this patient',
                      'أضف ملاحظات حول هذا المريض'),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.sub(isDark),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText:
                        t('Enter your notes here...', 'أدخل ملاحظاتك هنا...'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor:
                        isDark ? AppTheme.bg(isDark) : AppTheme.card(isDark),
                  ),
                  style: TextStyle(
                    color: AppTheme.text(isDark),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // View Medical History Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _openMedicalHistoryForm,
              icon: const Icon(Icons.assignment_outlined),
              label: Text(
                t('View Medical History', 'عرض التاريخ المرضي'),
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4DB6AC),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _openPrescriptionForm,
              icon: const Icon(Icons.medication_outlined),
              label: Text(
                t('View Treatment Prescription', 'عرض الروشتة العلاجية'),
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF26A69A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // View Reports Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PatientReportsScreen(
                      patientId: widget.patient.id,
                      patientName: widget.patient.name,
                      onBack: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.assessment),
              label: Text(
                t('View Session Reports', 'عرض تقارير الجلسات'),
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF64B5F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // X-Ray Reports Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => _showXrayReports(context),
              icon: const Icon(Icons.image_search),
              label: Text(
                t('View X-Ray Reports', 'عرض تقارير الأشعة'),
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7E57C2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _submitChanges,
              icon: const Icon(Icons.save),
              label: Text(
                t('Submit Changes', 'حفظ التغييرات'),
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.text(isDark),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF00BCD4).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF00BCD4), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.sub(isDark),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.text(isDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
