// =============================================================================
// PATIENT MANAGEMENT SCREEN - PATIENT LIST & SEARCH
// =============================================================================
// Purpose: Manage doctor's patient list with two-tab interface
// Tab 1 - My Patients:
// - List of patients under doctor's care
// - View patient profiles (opens PatientProfileScreen)
// - Remove patients from care list
// - Progress tracking with visual progress bars
// Tab 2 - All Patients:
// - Search bar for finding patients by name/diagnosis
// - Add patients to doctor's care list
// - Browse all available patients in the system
// Data Source: PatientManager (shared with Home screen)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/custom_app_bar.dart';
import '../../utils/theme_provider.dart';
import '../../utils/patient_manager.dart';
import '../../services/doctor_patient_chat_service.dart';
import '../common/doctor_patient_chat_screen.dart';
import 'patient_profile_screen.dart';
import 'medical_history_form_screen.dart';
import 'treatment_prescription_form_screen.dart';

/// Patient Management Screen with tabs for My Patients and All Patients
class PatientManagementScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PatientManagementScreen({super.key, this.onBack});

  @override
  State<PatientManagementScreen> createState() =>
      _PatientManagementScreenState();
}

class _PatientManagementScreenState extends State<PatientManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _myPatientsSearchController = TextEditingController();
  final PatientManager _patientManager = PatientManager();
  String _searchQuery = '';
  String _myPatientsQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _patientManager.addListener(_onPatientsChanged);
  }

  void _onPatientsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _patientManager.removeListener(_onPatientsChanged);
    _tabController.dispose();
    _searchController.dispose();
    _myPatientsSearchController.dispose();
    super.dispose();
  }

  void _addPatientToMyCare(PatientData patient) async {
    await _patientManager.addToMyCare(patient);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(t('Patient added to your care', 'تمت إضافة المريض لرعايتك')),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _removePatientFromMyCare(PatientData patient) async {
    await _patientManager.removeFromMyCare(patient);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            t('Patient removed from your care', 'تم إزالة المريض من رعايتك')),
        backgroundColor: Colors.orange,
      ),
    );
  }


  List<PatientData> get _filteredAllPatients {
    if (_searchQuery.isEmpty) return _patientManager.allPatients;
    return _patientManager.allPatients
        .where((patient) =>
            patient.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            patient.diagnosis
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppBar(
        title: t('Patients', 'المرضى'),
        onBack: widget.onBack,
      ),
      backgroundColor: AppTheme.bg(isDark),
      body: Column(
        children: [
          // Tab Bar
          Container(
            color: AppTheme.card(isDark),
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              indicatorColor: const Color(0xFF00BCD4),
              labelColor: const Color(0xFF00BCD4),
              unselectedLabelColor: AppTheme.sub(isDark),
              tabs: [
                Tab(text: t('My Patients', 'مرضاي')),
                Tab(text: t('All Patients', 'جميع المرضى')),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: ListenableBuilder(
              listenable: _patientManager,
              builder: (context, _) {
                return TabBarView(
                  controller: _tabController,
                  children: [
                    // My Patients Tab
                    _buildMyPatientsTab(isDark),
                    // All Patients Tab
                    _buildAllPatientsTab(isDark),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<PatientData> get _filteredMyPatients {
    final all = _patientManager.myPatients;
    if (_myPatientsQuery.isEmpty) return all;
    final q = _myPatientsQuery.toLowerCase();
    return all
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.diagnosis.toLowerCase().contains(q))
        .toList();
  }

  Widget _buildMyPatientsTab(bool isDark) {
    if (_patientManager.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00BCD4)),
      );
    }

    if (_patientManager.myPatients.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline,
                size: 80, color: AppTheme.sub(isDark).withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              t('No patients under your care yet',
                  'لا يوجد مرضى تحت رعايتك بعد'),
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.sub(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t('Add patients from "All Patients" tab',
                  'أضف مرضى من تبويب "جميع المرضى"'),
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.sub(isDark).withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredMyPatients;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _myPatientsSearchController,
            onChanged: (v) => setState(() => _myPatientsQuery = v),
            decoration: InputDecoration(
              hintText: t('Search my patients...', 'ابحث في مرضاي...'),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF00BCD4)),
              suffixIcon: _myPatientsQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _myPatientsSearchController.clear();
                        setState(() => _myPatientsQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppTheme.border(isDark),
                ),
              ),
              filled: true,
              fillColor: AppTheme.card(isDark),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    t('No matching patients', 'لا يوجد مرضى مطابقون'),
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final patient = filtered[index];
                    return _PatientDetailTile(
                      patient: patient,
                      isDark: isDark,
                      onRemove: () => _removePatientFromMyCare(patient),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAllPatientsTab(bool isDark) {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: t('Search patients...', 'ابحث عن المرضى...'),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF00BCD4)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppTheme.border(isDark),
                ),
              ),
              filled: true,
              fillColor: AppTheme.card(isDark),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),

        // Patient List
        Expanded(
          child: _filteredAllPatients.isEmpty
              ? Center(
                  child: Text(
                    t('No patients found', 'لم يتم العثور على مرضى'),
                    style: TextStyle(
                      color: AppTheme.sub(isDark),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredAllPatients.length,
                  itemBuilder: (context, index) {
                    final patient = _filteredAllPatients[index];
                    return _PatientCard(
                      patient: patient,
                      isDark: isDark,
                      onAdd: () => _addPatientToMyCare(patient),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PatientCard extends StatelessWidget {
  final PatientData patient;
  final bool isDark;
  final VoidCallback? onAdd;

  const _PatientCard({
    required this.patient,
    required this.isDark,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.border(isDark),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF00BCD4).withValues(alpha: 0.2),
                child: Text(
                  patient.name.split(' ').map((e) => e[0]).take(2).join(),
                  style: const TextStyle(
                    color: Color(0xFF00BCD4),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.text(isDark),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      patient.diagnosis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.sub(isDark),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: Text(t('Add to My Care', 'إضافة لرعايتي')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BCD4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full detail patient tile matching the Home screen's My Patients section.
/// Shows ExpansionTile with progress, last session, notes, next appointment,
/// and action buttons for View Profile, Medical History, Treatment Rx, Chat.
class _PatientDetailTile extends StatelessWidget {
  final PatientData patient;
  final bool isDark;
  final VoidCallback? onRemove;

  const _PatientDetailTile({
    required this.patient,
    required this.isDark,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF00BCD4).withValues(alpha: 0.15),
            child: Text(
              patient.name.split(' ').map((e) => e[0]).take(2).join(),
              style: const TextStyle(
                  color: Color(0xFF00BCD4), fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(
            patient.name,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.text(isDark)),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (patient.diagnosis.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      patient.diagnosis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.sub(isDark),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: patient.progress,
                          minHeight: 8,
                          backgroundColor: AppTheme.border(isDark),
                          valueColor:
                              const AlwaysStoppedAnimation(AppTheme.cyan),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${(patient.progress * 100).round()}%',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.sub(isDark))),
                    // Remove icon
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                      tooltip: t('Remove Patient', 'حذف المريض'),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(t('Remove Patient', 'حذف المريض')),
                            content: Text(t(
                                'Are you sure you want to remove this patient from your care?',
                                'هل أنت متأكد أنك تريد إزالة هذا المريض من رعايتك؟')),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(t('Cancel', 'إلغاء')),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(t('Remove', 'حذف'),
                                    style: const TextStyle(
                                        color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          onRemove?.call();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          trailing:
              Icon(Icons.keyboard_arrow_down, color: AppTheme.sub(isDark)),
          children: [
            const SizedBox(height: 6),
            if (patient.lastSession.isNotEmpty)
              _detailRow(Icons.event_note, t('Last Session', 'آخر جلسة'),
                  patient.lastSession, isDark),
            if (patient.lastSession.isNotEmpty) const SizedBox(height: 8),
            if (patient.notes.isNotEmpty)
              _detailRow(Icons.sticky_note_2_outlined, t('Notes', 'ملاحظات'),
                  patient.notes, isDark),
            if (patient.notes.isNotEmpty) const SizedBox(height: 8),
            if (patient.nextAppointment.isNotEmpty)
              _detailRow(Icons.schedule, t('Next', 'التالي'),
                  patient.nextAppointment, isDark),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push<PatientData>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PatientProfileScreen(
                              patient: patient,
                              onUpdate: (updatedPatient) async {
                                await PatientManager()
                                    .updatePatient(updatedPatient);
                                Navigator.pop(context, updatedPatient);
                              },
                            ),
                          ),
                        );
                        if (result != null) {}
                      },
                      icon: const Icon(Icons.open_in_new,
                          color: Color(0xFF00BCD4)),
                      label: Text(
                        t('View Profile', 'عرض الملف'),
                        style: const TextStyle(color: Color(0xFF00BCD4)),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MedicalHistoryFormScreen(
                              patient: patient,
                              onSave: (history) async {
                                await PatientManager()
                                    .saveMedicalHistory(patient, history);
                              },
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.assignment_outlined,
                        color: Color(0xFF00BCD4),
                      ),
                      label: Text(
                        t('Medical History', 'التاريخ المرضي'),
                        style: const TextStyle(color: Color(0xFF00BCD4)),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final currentDoctorId =
                            FirebaseAuth.instance.currentUser?.uid ?? '';
                        TreatmentPrescription? currentPrescription;
                        if (currentDoctorId.isNotEmpty) {
                          for (final item in patient.prescriptions) {
                            if (item.doctorId == currentDoctorId) {
                              currentPrescription = item;
                              break;
                            }
                          }
                        }

                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                TreatmentPrescriptionFormScreen(
                              patient: patient,
                              initialPrescription: currentPrescription,
                              onSave: (prescription) async {
                                await PatientManager()
                                    .saveTreatmentPrescription(
                                  patient,
                                  prescription,
                                );
                              },
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.medication_outlined,
                        color: Color(0xFF00BCD4),
                      ),
                      label: Text(
                        t('Treatment Rx', 'الروشتة العلاجية'),
                        style: const TextStyle(color: Color(0xFF00BCD4)),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final currentDoctor =
                            FirebaseAuth.instance.currentUser;
                        if (currentDoctor == null) return;

                        final doctorName =
                            globalThemeProvider.displayName.trim().isNotEmpty
                                ? globalThemeProvider.displayName.trim()
                                : (currentDoctor.displayName ??
                                    currentDoctor.email?.split('@').first ??
                                    'Doctor');

                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DoctorPatientChatScreen(
                              chatContext: DoctorPatientChatContext(
                                doctorId: currentDoctor.uid,
                                doctorName: doctorName,
                                patientId: patient.id,
                                patientName: patient.name,
                              ),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.chat_bubble_outline,
                        color: Color(0xFF00BCD4),
                      ),
                      label: Text(
                        t('Chat', 'المحادثة'),
                        style: const TextStyle(color: Color(0xFF00BCD4)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.sub(isDark)),
        const SizedBox(width: 8),
        Text('$label: ',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.text(isDark))),
        Expanded(
          child: Text(value,
              style:
                  TextStyle(color: isDark ? Colors.white60 : Colors.black87)),
        ),
      ],
    );
  }
}
