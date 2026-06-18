import 'package:flutter/material.dart';
import '../../widgets/custom_app_bar.dart';
import '../../utils/theme_provider.dart';
import '../../utils/patient_manager.dart';

class MedicalHistoryFormScreen extends StatefulWidget {
  final PatientData patient;
  final Future<void> Function(MedicalHistoryData history) onSave;

  const MedicalHistoryFormScreen({
    super.key,
    required this.patient,
    required this.onSave,
  });

  @override
  State<MedicalHistoryFormScreen> createState() =>
      _MedicalHistoryFormScreenState();
}

class _MedicalHistoryFormScreenState extends State<MedicalHistoryFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _ageController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _chronicController;
  late final TextEditingController _medicationsController;
  late final TextEditingController _allergiesController;

  String? _walkingDuration;
  String? _mealsPerDay;
  String? _smokingStatus;
  String? _painLevel;
  String? _sleepQuality;

  bool _isSaving = false;

  final List<String> _walkingOptions = const [
    'Less than 30 minutes',
    '30 to 60 minutes',
    '1 to 2 hours',
    'More than 2 hours',
  ];

  final List<String> _mealsOptions = const [
    '1 meal',
    '2 meals',
    '3 meals',
    'More than 3 meals',
  ];

  final List<String> _smokingOptions = const [
    'No',
    'Occasionally',
    'Yes',
  ];

  final List<String> _painOptions = const [
    'No pain',
    'Mild',
    'Moderate',
    'Severe',
  ];

  final List<String> _sleepOptions = const [
    'Less than 5 hours',
    '5 to 7 hours',
    '7 to 9 hours',
    'More than 9 hours',
  ];

  @override
  void initState() {
    super.initState();
    final history = widget.patient.medicalHistory;

    _ageController = TextEditingController(
      text: history.age?.toString() ?? '',
    );
    _heightController = TextEditingController(
      text: history.heightCm?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: history.weightKg?.toString() ?? '',
    );
    _chronicController = TextEditingController(text: history.chronicConditions);
    _medicationsController = TextEditingController(text: history.medications);
    _allergiesController = TextEditingController(text: history.allergies);

    _walkingDuration =
        history.walkingDuration.isEmpty ? null : history.walkingDuration;
    _mealsPerDay = history.mealsPerDay.isEmpty ? null : history.mealsPerDay;
    _smokingStatus =
        history.smokingStatus.isEmpty ? null : history.smokingStatus;
    _painLevel = history.painLevel.isEmpty ? null : history.painLevel;
    _sleepQuality = history.sleepQuality.isEmpty ? null : history.sleepQuality;
  }

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _chronicController.dispose();
    _medicationsController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    final history = MedicalHistoryData(
      age: _parseInt(_ageController.text),
      heightCm: _parseDouble(_heightController.text),
      weightKg: _parseDouble(_weightController.text),
      walkingDuration: _walkingDuration ?? '',
      mealsPerDay: _mealsPerDay ?? '',
      smokingStatus: _smokingStatus ?? '',
      painLevel: _painLevel ?? '',
      sleepQuality: _sleepQuality ?? '',
      chronicConditions: _chronicController.text.trim(),
      medications: _medicationsController.text.trim(),
      allergies: _allergiesController.text.trim(),
    );

    try {
      await widget.onSave(history);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('Medical history saved successfully',
              'تم حفظ التاريخ المرضي بنجاح')),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              t('Failed to save medical history', 'فشل حفظ التاريخ المرضي')),
          backgroundColor: Colors.redAccent,
        ),
      );
      debugPrint('[MedicalHistoryFormScreen] Save error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  int? _parseInt(String input) {
    if (input.trim().isEmpty) return null;
    return int.tryParse(input.trim());
  }

  double? _parseDouble(String input) {
    if (input.trim().isEmpty) return null;
    return double.tryParse(input.trim());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.bg(isDark) : const Color(0xFFF5F9FC);

    return Scaffold(
      appBar: CustomAppBar(
        title: t('Medical History', 'التاريخ المرضي'),
        onBack: () => Navigator.pop(context),
      ),
      backgroundColor: bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [AppTheme.dBg, AppTheme.dCard]
                : [AppTheme.lBg, const Color(0xFFEDF6FB)],
          ),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionCard(
                isDark: isDark,
                title: t('Patient Information', 'بيانات المريض'),
                children: [
                  _readOnlyField(
                    label: t('Patient Name', 'اسم المريض'),
                    value: widget.patient.name,
                    icon: Icons.person_outline,
                    isDark: isDark,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _sectionCard(
                isDark: isDark,
                title: t('Body Measurements', 'القياسات الجسمانية'),
                children: [
                  TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(
                      t('Age', 'العمر'),
                      Icons.cake_outlined,
                      isDark,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final age = int.tryParse(value.trim());
                      if (age == null || age <= 0 || age > 120) {
                        return t('Enter a valid age', 'ادخل عمر صحيح');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _heightController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDecoration(
                      t('Height (cm)', 'الطول (سم)'),
                      Icons.height,
                      isDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _weightController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDecoration(
                      t('Weight (kg)', 'الوزن (كجم)'),
                      Icons.monitor_weight_outlined,
                      isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _sectionCard(
                isDark: isDark,
                title: t('Lifestyle', 'نمط الحياة'),
                children: [
                  _dropdownField(
                    isDark: isDark,
                    label: t('Walking per day', 'المشي يوميا'),
                    icon: Icons.directions_walk,
                    value: _walkingDuration,
                    items: _walkingOptions,
                    onChanged: (value) =>
                        setState(() => _walkingDuration = value),
                    trLabel: 'وقت المشي يوميا',
                  ),
                  const SizedBox(height: 12),
                  _dropdownField(
                    isDark: isDark,
                    label: t('Meals per day', 'عدد الوجبات يوميا'),
                    icon: Icons.restaurant_menu,
                    value: _mealsPerDay,
                    items: _mealsOptions,
                    onChanged: (value) => setState(() => _mealsPerDay = value),
                    trLabel: 'عدد الوجبات في اليوم',
                  ),
                  const SizedBox(height: 12),
                  _dropdownField(
                    isDark: isDark,
                    label: t('Smoking', 'التدخين'),
                    icon: Icons.smoking_rooms_outlined,
                    value: _smokingStatus,
                    items: _smokingOptions,
                    onChanged: (value) =>
                        setState(() => _smokingStatus = value),
                    trLabel: 'التدخين',
                  ),
                  const SizedBox(height: 12),
                  _dropdownField(
                    isDark: isDark,
                    label: t('Pain level', 'مستوى الألم'),
                    icon: Icons.healing_outlined,
                    value: _painLevel,
                    items: _painOptions,
                    onChanged: (value) => setState(() => _painLevel = value),
                    trLabel: 'مستوى الألم',
                  ),
                  const SizedBox(height: 12),
                  _dropdownField(
                    isDark: isDark,
                    label: t('Sleep quality', 'جودة النوم'),
                    icon: Icons.nightlight_outlined,
                    value: _sleepQuality,
                    items: _sleepOptions,
                    onChanged: (value) => setState(() => _sleepQuality = value),
                    trLabel: 'جودة النوم',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _sectionCard(
                isDark: isDark,
                title: t('Medical Notes', 'ملاحظات طبية'),
                children: [
                  TextFormField(
                    controller: _chronicController,
                    maxLines: 2,
                    decoration: _inputDecoration(
                      t('Chronic conditions', 'الأمراض المزمنة'),
                      Icons.health_and_safety_outlined,
                      isDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _medicationsController,
                    maxLines: 2,
                    decoration: _inputDecoration(
                      t('Current medications', 'الأدوية الحالية'),
                      Icons.medication_outlined,
                      isDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _allergiesController,
                    maxLines: 2,
                    decoration: _inputDecoration(
                      t('Allergies', 'الحساسية'),
                      Icons.warning_amber_outlined,
                      isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
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
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving
                    ? t('Saving...', 'جاري الحفظ...')
                    : t('Save', 'حفظ')),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required bool isDark,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFDBEAF2),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.18)
                : const Color(0xFF7AA7C7).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
          ...children,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, bool isDark) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF00BCD4)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white24 : const Color(0xFFD2E2ED),
        ),
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

  Widget _readOnlyField({
    required String label,
    required String value,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white24 : const Color(0xFFD2E2ED),
        ),
        color: isDark ? AppTheme.bg(isDark) : const Color(0xFFF8FCFF),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF00BCD4)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : const Color(0xFF5C7285),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF12344D),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownField({
    required bool isDark,
    required String label,
    required String trLabel,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    // Prevent Red Screen Crash if the stored value doesn't match the current options
    final safeValue = (value != null && items.contains(value)) ? value : null;

    return DropdownButtonFormField<String>(
      initialValue: safeValue,
      decoration: _inputDecoration(label, icon, isDark),
      dropdownColor: AppTheme.card(isDark),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                t(item, _translateOption(trLabel, item)),
                style: TextStyle(
                  color: AppTheme.text(isDark),
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      hint: Text(t('Select', 'اختر')),
    );
  }

  String _translateOption(String group, String english) {
    switch (group) {
      case 'وقت المشي يوميا':
        switch (english) {
          case 'Less than 30 minutes':
            return 'اقل من 30 دقيقة';
          case '30 to 60 minutes':
            return 'من 30 الى 60 دقيقة';
          case '1 to 2 hours':
            return 'من ساعة الى ساعتين';
          case 'More than 2 hours':
            return 'اكثر من ساعتين';
        }
      case 'عدد الوجبات في اليوم':
        switch (english) {
          case '1 meal':
            return 'وجبة واحدة';
          case '2 meals':
            return 'وجبتان';
          case '3 meals':
            return '3 وجبات';
          case 'More than 3 meals':
            return 'اكثر من 3 وجبات';
        }
      case 'التدخين':
        switch (english) {
          case 'No':
            return 'لا';
          case 'Occasionally':
            return 'احيانا';
          case 'Yes':
            return 'نعم';
        }
      case 'مستوى الألم':
        switch (english) {
          case 'No pain':
            return 'بدون الم';
          case 'Mild':
            return 'خفيف';
          case 'Moderate':
            return 'متوسط';
          case 'Severe':
            return 'شديد';
        }
      case 'جودة النوم':
        switch (english) {
          case 'Less than 5 hours':
            return 'اقل من 5 ساعات';
          case '5 to 7 hours':
            return 'من 5 الى 7 ساعات';
          case '7 to 9 hours':
            return 'من 7 الى 9 ساعات';
          case 'More than 9 hours':
            return 'اكثر من 9 ساعات';
        }
    }

    return english;
  }
}
