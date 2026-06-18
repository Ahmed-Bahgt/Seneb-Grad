import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/exercise_program.dart';
import '../../utils/theme_provider.dart';
import 'custom_exercise_builder_screen.dart';

const _kPrimary = Color(0xFF00BCD4);

/// Default threshold values per exercise type (used as slider defaults).
const _defaults = {
  'Squat': {
    'hipAngleMin': 10.0, 'hipAngleMax': 60.0,
    'ankleAngle': 45.0, 'squatDepthMin': 70.0,
  },
  'Shoulder Abduction': {
    'armsTooHigh': 125.0, 'elbowBentMin': 140.0,
    'asymmetryMax': 20.0, 'backSwayMax': 10.0,
  },
  'Internal Rotation': {
    'elbowFlareMax': 0.4, 'wristAlignMax': 0.22, 'torsoTwistMin': 0.85,
  },
  'Lateral Raise': {
    'lateralArmsTooHigh': 105.0, 'elbowBentMin': 140.0,
    'lateralAsymmetryMax': 20.0,
  },
};

/// Doctor screen: build a multi-exercise program and assign it to a patient.
class ExerciseBuilderScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final ExerciseProgram? existingProgram;
  final Future<void> Function(ExerciseProgram) onSave;

  const ExerciseBuilderScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.onSave,
    this.existingProgram,
  });

  @override
  State<ExerciseBuilderScreen> createState() => _ExerciseBuilderScreenState();
}

class _ExerciseBuilderScreenState extends State<ExerciseBuilderScreen> {
  final _nameCtrl = TextEditingController();
  List<ProgramExercise> _exercises = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingProgram != null) {
      _nameCtrl.text = widget.existingProgram!.name;
      _exercises = List.from(widget.existingProgram!.exercises);
    } else {
      _nameCtrl.text = 'Rehab Program';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise first.')),
      );
      return;
    }
    setState(() => _saving = true);
    final program = ExerciseProgram(
      name: _nameCtrl.text.trim().isEmpty ? 'Rehab Program' : _nameCtrl.text.trim(),
      exercises: _exercises,
      assignedBy: FirebaseAuth.instance.currentUser?.uid ?? '',
      assignedAt: DateTime.now(),
    );
    await widget.onSave(program);
    if (mounted) Navigator.pop(context);
  }

  void _addExercise() => _openExerciseEditor(null, null);

  void _editExercise(int index) => _openExerciseEditor(index, _exercises[index]);

  void _openCustomBuilder() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomExerciseBuilderScreen(
          patientId: widget.patientId,
          patientName: widget.patientName,
          onAddToProgram: (ex) {
            setState(() => _exercises.add(ex));
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _removeExercise(int index) {
    setState(() => _exercises.removeAt(index));
  }

  void _moveUp(int index) {
    if (index == 0) return;
    setState(() {
      final e = _exercises.removeAt(index);
      _exercises.insert(index - 1, e);
    });
  }

  void _moveDown(int index) {
    if (index == _exercises.length - 1) return;
    setState(() {
      final e = _exercises.removeAt(index);
      _exercises.insert(index + 1, e);
    });
  }

  void _openExerciseEditor(int? editIndex, ProgramExercise? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExerciseEditorSheet(
        initial: existing,
        onDone: (ex) {
          setState(() {
            if (editIndex != null) {
              _exercises[editIndex] = ex;
            } else {
              _exercises.add(ex);
            }
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.bg(isDark) : const Color(0xFFF5F7FA);
    final card = AppTheme.card(isDark);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: AppTheme.card(isDark),
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: AppTheme.text(isDark)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          t('Exercise Builder', 'منشئ التمارين'),
          style: TextStyle(
              color: AppTheme.text(isDark),
              fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, color: _kPrimary),
              label: Text(t('Save', 'حفظ'),
                  style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Program name
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _nameCtrl,
              style: TextStyle(color: AppTheme.text(isDark)),
              decoration: InputDecoration(
                labelText: t('Program Name', 'اسم البرنامج'),
                prefixIcon: const Icon(Icons.fitness_center, color: _kPrimary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: card,
              ),
            ),
          ),

          // Patient chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              const Icon(Icons.person_outline, color: _kPrimary, size: 18),
              const SizedBox(width: 6),
              Text(
                t('For: ', 'للمريض: ') + widget.patientName,
                style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.sub(isDark)),
              ),
            ]),
          ),

          const Divider(height: 16),

          // Exercise list header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    t('Exercises (${_exercises.length})', 'التمارين (${_exercises.length})'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppTheme.text(isDark)),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(t('Add', 'إضافة')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _openCustomBuilder,
                      icon: const Icon(Icons.build, size: 18),
                      label: Text(t('Build Custom', 'بناء مخصص')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C4DFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Exercise cards
          Expanded(
            child: _exercises.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sports_gymnastics,
                            size: 64,
                            color: isDark ? Colors.white24 : Colors.black26),
                        const SizedBox(height: 12),
                        Text(
                          t('No exercises yet.\nTap "Add" to build the program.',
                              'لا توجد تمارين بعد.\nاضغط "إضافة" لبناء البرنامج.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: isDark ? Colors.white38 : Colors.black38),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: _exercises.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final ex = _exercises[i];
                      return _ExerciseCard(
                        index: i,
                        total: _exercises.length,
                        exercise: ex,
                        isDark: isDark,
                        onEdit: () => _editExercise(i),
                        onDelete: () => _removeExercise(i),
                        onMoveUp: i > 0 ? () => _moveUp(i) : null,
                        onMoveDown:
                            i < _exercises.length - 1 ? () => _moveDown(i) : null,
                      );
                    },
                  ),
          ),
        ],
      ),

      // Save FAB
      floatingActionButton: _exercises.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              backgroundColor: _kPrimary,
              icon: const Icon(Icons.check, color: Colors.white),
              label: Text(
                t('Assign to ${widget.patientName}',
                    'تعيين لـ${widget.patientName}'),
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ExerciseCard extends StatelessWidget {
  final int index;
  final int total;
  final ProgramExercise exercise;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _ExerciseCard({
    required this.index,
    required this.total,
    required this.exercise,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  IconData _iconFor(String type) {
    switch (type) {
      case 'Squat': return Icons.accessibility_new;
      case 'Shoulder Abduction': return Icons.airline_seat_flat_angled;
      case 'Internal Rotation': return Icons.rotate_right;
      case 'Lateral Raise': return Icons.expand;
      default: return Icons.fitness_center;
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = AppTheme.card(isDark);
    final textColor = AppTheme.text(isDark);
    final subColor = AppTheme.sub(isDark);
    final hasOverrides = !exercise.thresholds.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Step number
          Container(
            width: 44,
            height: 72,
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_iconFor(exercise.type), color: _kPrimary, size: 22),
              const SizedBox(height: 2),
              Text('${index + 1}',
                  style: const TextStyle(
                      color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
            ]),
          ),

          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exercise.type,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: textColor)),
                  const SizedBox(height: 4),
                  Text(
                    '${exercise.targetSets} sets × ${exercise.targetReps} reps  •  ${exercise.mode}',
                    style: TextStyle(fontSize: 12, color: subColor),
                  ),
                  if (hasOverrides)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Custom thresholds',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Actions
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onMoveUp != null)
                _iconBtn(Icons.keyboard_arrow_up, onMoveUp!, subColor),
              if (onMoveDown != null)
                _iconBtn(Icons.keyboard_arrow_down, onMoveDown!, subColor),
            ],
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _iconBtn(Icons.edit_outlined, onEdit, _kPrimary),
              _iconBtn(Icons.delete_outline, onDelete, Colors.red),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ExerciseEditorSheet extends StatefulWidget {
  final ProgramExercise? initial;
  final void Function(ProgramExercise) onDone;

  const _ExerciseEditorSheet({required this.onDone, this.initial});

  @override
  State<_ExerciseEditorSheet> createState() => _ExerciseEditorSheetState();
}

class _ExerciseEditorSheetState extends State<_ExerciseEditorSheet> {
  static const _types = [
    'Squat', 'Shoulder Abduction', 'Internal Rotation', 'Lateral Raise'
  ];

  late String _type;
  late double _reps;
  late double _sets;
  late String _mode;
  bool _showThresholds = false;

  // Threshold sliders — keyed by field name, value is current
  late Map<String, double> _thresh;

  @override
  void initState() {
    super.initState();
    final ex = widget.initial;
    _type = ex?.type ?? 'Squat';
    _reps = (ex?.targetReps ?? 10).toDouble();
    _sets = (ex?.targetSets ?? 3).toDouble();
    _mode = ex?.mode ?? 'Beginner';
    _thresh = _buildThreshMap(ex);
  }

  Map<String, double> _buildThreshMap(ProgramExercise? ex) {
    final defaults = Map<String, double>.from(
        (_defaults[_type] ?? {}).map((k, v) => MapEntry(k, v)));
    if (ex != null) {
      final t = ex.thresholds;
      if (t.hipAngleMin != null) defaults['hipAngleMin'] = t.hipAngleMin!;
      if (t.hipAngleMax != null) defaults['hipAngleMax'] = t.hipAngleMax!;
      if (t.ankleAngle != null) defaults['ankleAngle'] = t.ankleAngle!;
      if (t.squatDepthMin != null) defaults['squatDepthMin'] = t.squatDepthMin!;
      if (t.armsTooHigh != null) defaults['armsTooHigh'] = t.armsTooHigh!;
      if (t.elbowBentMin != null) defaults['elbowBentMin'] = t.elbowBentMin!;
      if (t.asymmetryMax != null) defaults['asymmetryMax'] = t.asymmetryMax!;
      if (t.backSwayMax != null) defaults['backSwayMax'] = t.backSwayMax!;
      if (t.elbowFlareMax != null) defaults['elbowFlareMax'] = t.elbowFlareMax!;
      if (t.wristAlignMax != null) defaults['wristAlignMax'] = t.wristAlignMax!;
      if (t.torsoTwistMin != null) defaults['torsoTwistMin'] = t.torsoTwistMin!;
      if (t.lateralArmsTooHigh != null) defaults['lateralArmsTooHigh'] = t.lateralArmsTooHigh!;
      if (t.lateralAsymmetryMax != null) defaults['lateralAsymmetryMax'] = t.lateralAsymmetryMax!;
    }
    return defaults;
  }

  ExerciseThresholdOverrides _buildOverrides() {
    final d = _defaults[_type] ?? {};
    bool changed = false;
    for (final k in _thresh.keys) {
      if (d[k] != _thresh[k]) { changed = true; break; }
    }
    if (!changed) return const ExerciseThresholdOverrides();

    return ExerciseThresholdOverrides(
      hipAngleMin: _thresh['hipAngleMin'],
      hipAngleMax: _thresh['hipAngleMax'],
      ankleAngle: _thresh['ankleAngle'],
      squatDepthMin: _thresh['squatDepthMin'],
      armsTooHigh: _thresh['armsTooHigh'],
      elbowBentMin: _thresh['elbowBentMin'],
      asymmetryMax: _thresh['asymmetryMax'],
      backSwayMax: _thresh['backSwayMax'],
      elbowFlareMax: _thresh['elbowFlareMax'],
      wristAlignMax: _thresh['wristAlignMax'],
      torsoTwistMin: _thresh['torsoTwistMin'],
      lateralArmsTooHigh: _thresh['lateralArmsTooHigh'],
      lateralAsymmetryMax: _thresh['lateralAsymmetryMax'],
    );
  }

  void _confirm() {
    widget.onDone(ProgramExercise(
      type: _type,
      targetReps: _reps.round(),
      targetSets: _sets.round(),
      mode: _mode,
      thresholds: _buildOverrides(),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = AppTheme.card(isDark);
    final textColor = AppTheme.text(isDark);
    final subColor = AppTheme.sub(isDark);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    widget.initial == null
                        ? t('Add Exercise', 'إضافة تمرين')
                        : t('Edit Exercise', 'تعديل التمرين'),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: textColor),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(t('Done', 'تأكيد')),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  // Exercise type
                  Text(t('Exercise Type', 'نوع التمرين'),
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: textColor)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _types.map((type) {
                      final selected = _type == type;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _type = type;
                          _thresh = _buildThreshMap(null);
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? _kPrimary
                                : (isDark
                                    ? AppTheme.bg(isDark)
                                    : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? _kPrimary
                                  : (isDark
                                      ? Colors.white24
                                      : Colors.grey.shade300),
                            ),
                          ),
                          child: Text(
                            type,
                            style: TextStyle(
                              color: selected ? Colors.white : textColor,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),

                  // Reps slider
                  _sliderRow(
                    label: t('Reps per set: ${_reps.round()}',
                        'تكرارات لكل مجموعة: ${_reps.round()}'),
                    value: _reps, min: 3, max: 20, divisions: 17,
                    textColor: textColor,
                    onChanged: (v) => setState(() => _reps = v),
                  ),

                  // Sets slider
                  _sliderRow(
                    label: t('Sets: ${_sets.round()}',
                        'المجموعات: ${_sets.round()}'),
                    value: _sets, min: 1, max: 6, divisions: 5,
                    textColor: textColor,
                    onChanged: (v) => setState(() => _sets = v),
                  ),

                  const SizedBox(height: 12),

                  // Mode toggle
                  Text(t('Difficulty Mode', 'مستوى الصعوبة'),
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: textColor)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _modeChip('Beginner', isDark, textColor),
                    const SizedBox(width: 10),
                    _modeChip('Pro', isDark, textColor),
                  ]),

                  const SizedBox(height: 20),
                  const Divider(),

                  // Threshold section toggle
                  InkWell(
                    onTap: () => setState(() => _showThresholds = !_showThresholds),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Icon(Icons.tune, color: _kPrimary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          t('Advanced: Form Check Thresholds',
                              'متقدم: حدود فحص الأداء'),
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _kPrimary, fontSize: 13),
                        ),
                        const Spacer(),
                        Icon(
                          _showThresholds
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: subColor,
                        ),
                      ]),
                    ),
                  ),

                  if (_showThresholds) ..._buildThresholdSliders(textColor, subColor, isDark),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(String mode, bool isDark, Color textColor) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _kPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? _kPrimary : (isDark ? Colors.white24 : Colors.grey.shade300)),
        ),
        child: Text(mode,
            style: TextStyle(
              color: selected ? Colors.white : textColor,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            )),
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Color textColor,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
        Slider(
          value: value, min: min, max: max, divisions: divisions,
          activeColor: _kPrimary,
          label: value.round().toString(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  List<Widget> _buildThresholdSliders(
      Color textColor, Color subColor, bool isDark) {
    switch (_type) {
      case 'Squat':
        return [
          _threshNote(
              'Lower hip min → easier form check. Higher ankle → stricter knee tracking.',
              subColor),
          _threshSlider('hipAngleMin', 'Hip angle min (bend forward limit)°',
              5, 30, textColor),
          _threshSlider('hipAngleMax', 'Hip angle max (lean back limit)°',
              40, 80, textColor),
          _threshSlider('ankleAngle', 'Ankle angle (knee-over-toe limit)°',
              20, 60, textColor),
          _threshSlider('squatDepthMin', 'Min squat depth°', 50, 90, textColor),
        ];
      case 'Shoulder Abduction':
        return [
          _threshNote(
              'Raise "arms too high" to allow a wider ROM. Lower asymmetry to catch uneven raises.',
              subColor),
          _threshSlider('armsTooHigh', 'Arms too high limit°', 100, 150, textColor),
          _threshSlider('elbowBentMin', 'Elbow straight min°', 110, 170, textColor),
          _threshSlider('asymmetryMax', 'Max arm asymmetry°', 5, 35, textColor),
          _threshSlider('backSwayMax', 'Max back sway°', 5, 20, textColor),
        ];
      case 'Internal Rotation':
        return [
          _threshNote(
              'These are ratios (0.0–1.0), not angles. Raise elbow flare max to be more lenient.',
              subColor),
          _threshSliderDecimal('elbowFlareMax', 'Elbow flare max ratio',
              0.1, 0.8, textColor),
          _threshSliderDecimal('wristAlignMax', 'Wrist alignment max ratio',
              0.05, 0.4, textColor),
          _threshSliderDecimal('torsoTwistMin', 'Torso twist min ratio',
              0.6, 1.0, textColor),
        ];
      case 'Lateral Raise':
        return [
          _threshNote(
              'Raise the "arms too high" limit to allow full shoulder-level raises.',
              subColor),
          _threshSlider('lateralArmsTooHigh', 'Arms too high limit°',
              85, 130, textColor),
          _threshSlider('elbowBentMin', 'Elbow straight min°', 110, 170, textColor),
          _threshSlider('lateralAsymmetryMax', 'Max arm asymmetry°',
              5, 35, textColor),
        ];
      default:
        return [];
    }
  }

  Widget _threshNote(String text, Color subColor) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text,
            style: TextStyle(fontSize: 11, color: subColor, fontStyle: FontStyle.italic)),
      );

  Widget _threshSlider(String key, String label, double min, double max,
      Color textColor) {
    final val = (_thresh[key] ?? min).clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${val.round()}°',
            style: TextStyle(fontSize: 12, color: textColor)),
        Slider(
          value: val, min: min, max: max,
          divisions: (max - min).round(),
          activeColor: _kPrimary,
          label: '${val.round()}°',
          onChanged: (v) => setState(() => _thresh[key] = v),
        ),
      ],
    );
  }

  Widget _threshSliderDecimal(String key, String label, double min, double max,
      Color textColor) {
    final val = (_thresh[key] ?? min).clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${val.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 12, color: textColor)),
        Slider(
          value: val, min: min, max: max, divisions: 30,
          activeColor: _kPrimary,
          label: val.toStringAsFixed(2),
          onChanged: (v) => setState(() => _thresh[key] = v),
        ),
      ],
    );
  }
}
