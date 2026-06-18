// =============================================================================
// DOCTOR AVAILABILITY SCREEN - TIME SLOT MANAGEMENT
// =============================================================================
// Purpose: Manage doctor's available time slots for appointments
// Features:
// - Add new availability slots (date + time range: from-to)
// - Edit existing slots (auto-fills form with slot data)
// - Remove slots with delete button
// - Time validation (ensures 'to' time is after 'from' time)
// - Sorted display by date and time
// - Day name display (e.g., Monday, Dec 16, 2025)
// Data Source: AvailabilityManager (shared with Home screen)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/custom_app_bar.dart';
import '../../utils/theme_provider.dart';
import '../../utils/availability_manager.dart';

/// Set Availability Screen
class SetAvailabilityScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const SetAvailabilityScreen({super.key, this.onBack});

  @override
  State<SetAvailabilityScreen> createState() => _SetAvailabilityScreenState();
}

class _SetAvailabilityScreenState extends State<SetAvailabilityScreen> {
  final AvailabilityManager _manager = AvailabilityManager();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTimeFrom;
  TimeOfDay? _selectedTimeTo;
  int? _editingIndex; // Track which slot is being edited

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onSlotsChanged);
    // Check if we should edit a slot from home screen
    if (_manager.editingIndex != null) {
      Future.microtask(() => _loadSlotForEditing(_manager.editingIndex!));
    }
  }

  @override
  void dispose() {
    _manager.removeListener(_onSlotsChanged);
    super.dispose();
  }

  void _onSlotsChanged() {
    setState(() {});
  }

  void _loadSlotForEditing(int index) {
    if (index >= 0 && index < _manager.slots.length) {
      final slot = _manager.slots[index];
      setState(() {
        _editingIndex = index;
        _selectedDate = slot.date;
        _selectedTimeFrom = slot.timeFrom;
        _selectedTimeTo = slot.timeTo;
      });
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTimeFrom(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTimeFrom ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _selectedTimeFrom = picked);
    }
  }

  Future<void> _pickTimeTo(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTimeTo ??
          (_selectedTimeFrom != null
              ? TimeOfDay(
                  hour: _selectedTimeFrom!.hour + 1,
                  minute: _selectedTimeFrom!.minute)
              : TimeOfDay.now()),
    );
    if (picked != null) {
      setState(() => _selectedTimeTo = picked);
    }
  }

  void _addSlot() {
    if (_selectedDate == null ||
        _selectedTimeFrom == null ||
        _selectedTimeTo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('Please select date, from time, and to time',
              'يرجى اختيار التاريخ والوقت من والى')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validate time range
    final fromMinutes =
        _selectedTimeFrom!.hour * 60 + _selectedTimeFrom!.minute;
    final toMinutes = _selectedTimeTo!.hour * 60 + _selectedTimeTo!.minute;
    if (fromMinutes >= toMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('"To" time must be after "From" time',
              'يجب أن يكون وقت "إلى" بعد وقت "من"')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final slot = AvailabilitySlot(
      date: _selectedDate!,
      timeFrom: _selectedTimeFrom!,
      timeTo: _selectedTimeTo!,
    );

    final wasEditing = _editingIndex != null;
    if (wasEditing) {
      _manager.updateSlot(_editingIndex!, slot);
    } else {
      _manager.addSlot(slot);
    }

    setState(() {
      _editingIndex = null;
      _selectedDate = null;
      _selectedTimeFrom = null;
      _selectedTimeTo = null;
    });
    _manager.clearEditingIndex();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasEditing
            ? t('Slot updated successfully', 'تم تحديث الموعد بنجاح')
            : t('Slot added successfully', 'تمت إضافة الموعد بنجاح')),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _editSlot(int index) {
    final slot = _manager.slots[index];
    setState(() {
      _editingIndex = index;
      _selectedDate = slot.date;
      _selectedTimeFrom = slot.timeFrom;
      _selectedTimeTo = slot.timeTo;
    });
    // Scroll to top to show the edit form
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _cancelEdit() {
    setState(() {
      _editingIndex = null;
      _selectedDate = null;
      _selectedTimeFrom = null;
      _selectedTimeTo = null;
    });
    _manager.clearEditingIndex();
  }

  void _removeSlot(int index) {
    _manager.removeSlot(index);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('Slot removed', 'تم حذف الموعد')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('EEEE, MMM d, yyyy').format(date);
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: CustomAppBar(
        title: t('Set Availability', 'تعيين التوفر'),
        onBack: widget.onBack,
      ),
      backgroundColor: AppTheme.bg(isDark),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _editingIndex != null
                      ? t('Edit Availability Slot', 'تعديل موعد متاح')
                      : t('Add Availability Slot', 'إضافة موعد متاح'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text(isDark),
                  ),
                ),
              ),
              if (_editingIndex != null)
                TextButton.icon(
                  onPressed: _cancelEdit,
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(t('Cancel', 'إلغاء')),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Date & Time Selectors
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card(isDark),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.border(isDark)),
            ),
            child: Column(
              children: [
                // Date Selector
                GestureDetector(
                  onTap: () => _pickDate(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color:
                          AppTheme.bg(isDark),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00BCD4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            color: Color(0xFF00BCD4), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selectedDate != null
                                ? _formatDate(_selectedDate!)
                                : t('Select Date', 'اختر التاريخ'),
                            style: TextStyle(
                              color: AppTheme.text(isDark),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Time From & To
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('From', 'من'),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.sub(isDark),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _pickTimeFrom(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppTheme.bg(isDark)
                                    : AppTheme.card(isDark),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0xFF00BCD4)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time,
                                      color: Color(0xFF00BCD4), size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedTimeFrom != null
                                          ? _formatTime(_selectedTimeFrom!)
                                          : t('Time', 'الوقت'),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('To', 'إلى'),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.sub(isDark),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _pickTimeTo(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppTheme.bg(isDark)
                                    : AppTheme.card(isDark),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: AppTheme.cyan),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time,
                                      color: Color(0xFF8BC34A), size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedTimeTo != null
                                          ? _formatTime(_selectedTimeTo!)
                                          : t('Time', 'الوقت'),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _addSlot,
                    icon: Icon(_editingIndex != null ? Icons.save : Icons.add),
                    label: Text(_editingIndex != null
                        ? t('Save Changes', 'حفظ التغييرات')
                        : t('Add Slot', 'إضافة موعد')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cyan,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Text(
            t('Your Availability Slots', 'مواعيدك المتاحة'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.text(isDark),
            ),
          ),
          const SizedBox(height: 12),

          // Slots List
          if (_manager.slots.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: AppTheme.card(isDark),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.event_busy,
                      size: 48,
                      color: isDark ? Colors.white24 : Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    t('No availability slots yet', 'لا توجد مواعيد متاحة بعد'),
                    style: TextStyle(
                        color: AppTheme.sub(isDark)),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_manager.slots.length, (index) {
              final slot = _manager.slots[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.card(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.border(isDark)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.event_available,
                          color: Color(0xFF00BCD4), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(slot.date),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppTheme.text(isDark),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.access_time,
                                  size: 14,
                                  color:
                                      AppTheme.sub(isDark)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${_formatTime(slot.timeFrom)} - ${_formatTime(slot.timeTo)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        AppTheme.sub(isDark),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _editSlot(index),
                      icon: const Icon(Icons.edit_outlined,
                          color: Color(0xFF00BCD4), size: 22),
                      tooltip: t('Edit', 'تعديل'),
                    ),
                    IconButton(
                      onPressed: () => _removeSlot(index),
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 24),
                      tooltip: t('Remove', 'حذف'),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
