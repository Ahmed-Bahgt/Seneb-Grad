import 'package:flutter/material.dart';
import 'patient_manager.dart';
import 'patient_bookings_manager.dart';
import 'availability_manager.dart';
import 'patient_profile_manager.dart';
import 'theme_provider.dart';

/// Singleton that manages developer test mode.
/// When active, all managers use in-memory mock data so no Firebase login
/// or real Firestore connection is needed.
class DevModeService {
  static final DevModeService _instance = DevModeService._internal();
  factory DevModeService() => _instance;
  DevModeService._internal();

  bool isActive = false;
  String activeRole = '';

  static const String devDoctorId = 'DEV_DOCTOR_001';
  static const String devPatientId = 'DEV_PATIENT_001';

  void activate(String role) {
    isActive = true;
    activeRole = role;
    appDevMode = true; // prevents managers from overwriting mock data

    // Set display name and role on the global ThemeProvider
    if (role == 'doctor') {
      globalThemeProvider.setDisplayName('Dr. Khaled Mansour');
      globalThemeProvider.setUserRole('doctor');
    } else if (role == 'patient') {
      globalThemeProvider.setDisplayName('Sara Hassan');
      globalThemeProvider.setUserRole('patient');
    } else if (role == 'admin') {
      globalThemeProvider.setDisplayName('Admin');
      globalThemeProvider.setUserRole('admin');
    }

    // Seed managers with synthetic data
    if (role == 'doctor') {
      PatientManager().loadDevModeData(
        myPatients: _mockMyPatients(),
        allPatients: _mockUnassignedPatients(),
      );
      AvailabilityManager().loadDevModeData(
        slots: _mockSlots(),
        bookedAppointments: _mockBookedAppointments(),
        bookedCount: 1,
      );
    } else if (role == 'patient') {
      PatientProfileManager().setPatientName('Sara Hassan');
      PatientProfileManager().setExercisePlan(
        type: 'Squat',
        sets: 3,
        reps: 12,
      );
      PatientProfileManager().setExerciseMode('Normal');
      PatientBookingsManager().loadDevModeData(_mockPatientBookings());
    }
  }

  void deactivate() {
    isActive = false;
    activeRole = '';
  }

  /// Re-seed all manager data — call this in a post-frame callback after
  /// the dashboard mounts so that all ListenableBuilders receive the notification.
  void refreshDoctorData() {
    if (!isActive || activeRole != 'doctor') return;
    PatientManager().loadDevModeData(
      myPatients: _mockMyPatients(),
      allPatients: _mockUnassignedPatients(),
    );
    AvailabilityManager().loadDevModeData(
      slots: _mockSlots(),
      bookedAppointments: _mockBookedAppointments(),
      bookedCount: 1,
    );
  }

  // ─── Mock data factories ──────────────────────────────────────────────────

  List<PatientData> _mockMyPatients() {
    return [
      PatientData(
        id: devPatientId,
        name: 'Sara Hassan',
        diagnosis: 'Knee Rehabilitation',
        progress: 40.0,
        phone: '01001234567',
        email: 'sara.hassan@example.com',
        assignedPlan: 'Squat',
        assignedMode: 'Normal',
        notes: 'Patient recovering well. Keep monitoring knee alignment.',
        lastSession: '2026-05-07',
        nextAppointment: '2026-05-10',
        assignedDoctorId: devDoctorId,
        sessions: 12,
        completedSessions: 5,
        sets: 3,
        reps: 12,
        medicalHistory: const MedicalHistoryData(
          age: 29,
          heightCm: 162.0,
          weightKg: 58.0,
          walkingDuration: '30 minutes',
          mealsPerDay: '3',
          smokingStatus: 'Non-smoker',
          painLevel: '3',
          sleepQuality: 'Good',
          chronicConditions: 'None',
          medications: 'Ibuprofen (as needed)',
          allergies: 'None',
        ),
      ),
      PatientData(
        id: 'DEV_PATIENT_002',
        name: 'Omar Nasser',
        diagnosis: 'Shoulder Impingement',
        progress: 25.0,
        phone: '01009876543',
        email: 'omar.nasser@example.com',
        assignedPlan: 'Shoulder Abduction',
        assignedMode: 'Normal',
        notes: 'Avoid overhead movements during recovery phase.',
        lastSession: '2026-05-05',
        nextAppointment: '2026-05-11',
        assignedDoctorId: devDoctorId,
        sessions: 8,
        completedSessions: 2,
        sets: 3,
        reps: 10,
      ),
    ];
  }

  List<PatientData> _mockUnassignedPatients() {
    return [
      PatientData(
        id: 'DEV_PATIENT_003',
        name: 'Layla Ibrahim',
        diagnosis: 'Rotator Cuff Strain',
        progress: 0.0,
        phone: '01055566677',
        email: 'layla.ibrahim@example.com',
        assignedPlan: '',
        assignedMode: '',
        notes: '',
        lastSession: '',
        nextAppointment: '',
        assignedDoctorId: '',
        sessions: 10,
        completedSessions: 0,
        sets: 3,
        reps: 12,
      ),
    ];
  }

  List<AvailabilitySlot> _mockSlots() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final dayAfter = DateTime.now().add(const Duration(days: 2));
    return [
      AvailabilitySlot(
        date: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
        timeFrom: const TimeOfDay(hour: 10, minute: 0),
        timeTo: const TimeOfDay(hour: 11, minute: 0),
      ),
      AvailabilitySlot(
        date: DateTime(dayAfter.year, dayAfter.month, dayAfter.day),
        timeFrom: const TimeOfDay(hour: 14, minute: 0),
        timeTo: const TimeOfDay(hour: 15, minute: 0),
      ),
    ];
  }

  List<BookedAppointment> _mockBookedAppointments() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final apptDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10, 0);
    return [
      BookedAppointment(
        id: 'DEV_BOOKING_001',
        doctorId: devDoctorId,
        doctorName: 'Dr. Khaled Mansour',
        patientId: devPatientId,
        patientName: 'Sara Hassan',
        dateTime: apptDate,
        endTime: apptDate.add(const Duration(hours: 1)),
        status: 'upcoming',
      ),
    ];
  }

  List<PatientBooking> _mockPatientBookings() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final apptDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10, 0);
    return [
      PatientBooking(
        id: 'DEV_BOOKING_001',
        doctorId: devDoctorId,
        doctorName: 'Dr. Khaled Mansour',
        specialty: 'Physiotherapy',
        dateTime: apptDate,
        endTime: apptDate.add(const Duration(hours: 1)),
        doctorImage: '',
        status: 'upcoming',
      ),
    ];
  }
}
