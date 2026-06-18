import 'package:flutter/material.dart';
import '../../utils/patient_manager.dart';
import '../../utils/theme_provider.dart';
import '../../widgets/custom_app_bar.dart';

class TreatmentPrescriptionFormScreen extends StatefulWidget {
  final PatientData patient;
  final TreatmentPrescription? initialPrescription;
  final Future<void> Function(TreatmentPrescription prescription) onSave;

  const TreatmentPrescriptionFormScreen({
    super.key,
    required this.patient,
    this.initialPrescription,
    required this.onSave,
  });

  @override
  State<TreatmentPrescriptionFormScreen> createState() =>
      _TreatmentPrescriptionFormScreenState();
}

class _TreatmentPrescriptionFormScreenState
    extends State<TreatmentPrescriptionFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _treatmentController;
  late final TextEditingController _notesController;
  final List<_MedicationCardControllers> _medicationCards = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPrescription ?? const TreatmentPrescription();
    _treatmentController = TextEditingController(text: initial.treatmentName);
    _notesController = TextEditingController(text: initial.notes);
    if (initial.items.isEmpty) {
      _medicationCards.add(_MedicationCardControllers());
    } else {
      for (final item in initial.items) {
        _medicationCards.add(_MedicationCardControllers.fromItem(item));
      }
    }
  }

  @override
  void dispose() {
    _treatmentController.dispose();
    _notesController.dispose();
    for (final card in _medicationCards) {
      card.dispose();
    }
    super.dispose();
  }

  void _addMedication() {
    setState(() {
      _medicationCards.add(_MedicationCardControllers());
    });
  }

  void _removeMedication(int index) {
    setState(() {
      _medicationCards[index].dispose();
      _medicationCards.removeAt(index);
    });
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
    });

    final items = _medicationCards
        .map((card) => PrescriptionMedicationItem(
              medication: card.medicationController.text.trim(),
              dosage: card.dosageController.text.trim(),
              duration: card.durationController.text.trim(),
            ))
        .where((item) => !item.isEmpty)
        .toList();

    final prescription = TreatmentPrescription(
      treatmentName: _treatmentController.text.trim(),
      items: items,
      notes: _notesController.text.trim(),
    );

    try {
      await widget.onSave(prescription);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('Prescription saved', 'تم حفظ الروشتة')),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('Unable to save prescription', 'تعذر حفظ الروشتة')),
          backgroundColor: Colors.redAccent,
        ),
      );
      debugPrint('[TreatmentPrescriptionForm] save error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppBar(
        title: t('Treatment Prescription', 'الروشتة العلاجية'),
        onBack: () => Navigator.pop(context),
      ),
      backgroundColor:
          isDark ? AppTheme.bg(isDark) : const Color(0xFFF5F9FC),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionCard(
              isDark: isDark,
              title: t('Patient', 'المريض'),
              child: Text(
                widget.patient.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF12344D),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              isDark: isDark,
              title: t('Prescription Details', 'تفاصيل الروشتة'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _treatmentController,
                    decoration: _decoration(
                      t('Treatment name', 'اسم العلاج'),
                      Icons.healing_outlined,
                      isDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          t('Medication Cards', 'بطاقات الأدوية'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: isDark ? Colors.white70 : const Color(0xFF12344D),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addMedication,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(t('Add', 'إضافة')),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF00BCD4),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...List.generate(_medicationCards.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.bg(isDark)
                              : const Color(0xFFF8FCFF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white12
                                : const Color(0xFFD2E2ED),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${t('Medication', 'دواء')} ${index + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF12344D),
                                    ),
                                  ),
                                ),
                                if (_medicationCards.length > 1)
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () => _removeMedication(index),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller:
                                  _medicationCards[index].medicationController,
                              decoration: _decoration(
                                t('Medication name', 'اسم الدواء'),
                                Icons.medication_outlined,
                                isDark,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller:
                                  _medicationCards[index].dosageController,
                              decoration: _decoration(
                                t('Dosage / frequency', 'الجرعة / التكرار'),
                                Icons.schedule,
                                isDark,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller:
                                  _medicationCards[index].durationController,
                              decoration: _decoration(
                                t('Duration', 'مدة العلاج'),
                                Icons.timelapse_outlined,
                                isDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 4,
                    decoration: _decoration(
                      t('Additional notes', 'ملاحظات إضافية'),
                      Icons.note_alt_outlined,
                      isDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_isSaving
                  ? t('Saving...', 'جاري الحفظ...')
                  : t('Save Prescription', 'حفظ الروشتة')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required bool isDark,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFDBEAF2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF12344D),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon, bool isDark) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF00BCD4)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white24 : const Color(0xFFD2E2ED),
        ),
      ),
      filled: true,
      fillColor: isDark ? AppTheme.bg(isDark) : const Color(0xFFF8FCFF),
    );
  }
}

class _MedicationCardControllers {
  final TextEditingController medicationController;
  final TextEditingController dosageController;
  final TextEditingController durationController;

  _MedicationCardControllers({
    String medication = '',
    String dosage = '',
    String duration = '',
  })  : medicationController = TextEditingController(text: medication),
        dosageController = TextEditingController(text: dosage),
        durationController = TextEditingController(text: duration);

  factory _MedicationCardControllers.fromItem(PrescriptionMedicationItem item) {
    return _MedicationCardControllers(
      medication: item.medication,
      dosage: item.dosage,
      duration: item.duration,
    );
  }

  void dispose() {
    medicationController.dispose();
    dosageController.dispose();
    durationController.dispose();
  }
}
