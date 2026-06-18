"""
Full Firebase → PostgreSQL Migration Script
============================================
Pulls ALL data from Firestore and inserts into the correct SQL tables:
  1. users           (from 'doctors' + 'patients' collections)
  2. doctors         (from 'doctors' collection)
  3. patients        (from 'patients' collection)
  4. available_slots (from 'doctors/{id}/availability_slots' subcollection)
  5. bookings        (from 'doctors/{id}/bookings' subcollection)
  6. workout_sessions(from 'patients/{id}/Sessions' subcollection)
  7. radiology_reports(from 'patients/{id}/radiology_reports' subcollection)
  8. admins          (kept as-is, created by backend on startup)
"""

import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime
import models
from database import SessionLocal, engine

# --- 1. INITIALIZE FIREBASE ---
SERVICE_ACCOUNT_PATH = "../tamrentech-firebase-adminsdk-fbsvc-af3878f30b.json"
cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
firebase_admin.initialize_app(cred)
db_firestore = firestore.client()

# --- 2. INITIALIZE SQL ---
models.Base.metadata.create_all(bind=engine)
db_sql = SessionLocal()

# --- HELPERS ---
def ts_to_dt(ts):
    """Convert Firestore Timestamp to Python datetime."""
    if ts is None:
        return None
    if isinstance(ts, datetime):
        return ts
    try:
        return ts.replace(tzinfo=None) if hasattr(ts, 'replace') else ts
    except:
        return None

def safe_str(val, default=''):
    if val is None:
        return default
    return str(val)

def sanitize_for_json(obj):
    """Recursively convert Firestore Timestamps/DatetimeWithNanoseconds to ISO strings."""
    if obj is None:
        return None
    if isinstance(obj, datetime):
        return obj.isoformat()
    if hasattr(obj, 'isoformat'):
        return obj.isoformat()
    if isinstance(obj, dict):
        return {k: sanitize_for_json(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [sanitize_for_json(item) for item in obj]
    return obj

# --- COUNTERS ---
counts = {
    'users': 0,
    'doctors': 0,
    'patients': 0,
    'available_slots': 0,
    'bookings': 0,
    'workout_sessions': 0,
    'radiology_reports': 0,
    'admins': 0,
}

try:
    # ===================================================================
    # STEP 1: Migrate Doctors → users + doctors tables
    # ===================================================================
    print("\n[1/6] Migrating DOCTORS...")
    docs = db_firestore.collection('doctors').stream()
    for doc in docs:
        data = doc.to_dict()
        doc_id = doc.id

        # --- users table ---
        if not db_sql.query(models.User).filter(models.User.id == doc_id).first():
            first = data.get('firstName', '')
            last = data.get('lastName', '')
            full_name = data.get('fullName', '')
            if not full_name and (first or last):
                full_name = f"{first} {last}".strip()
            
            new_user = models.User(
                id=doc_id,
                email=data.get('email', ''),
                full_name=full_name,
                phone=data.get('phone', ''),
                role='doctor'
            )
            db_sql.add(new_user)
            counts['users'] += 1

        # --- doctors table ---
        if not db_sql.query(models.Doctor).filter(models.Doctor.id == doc_id).first():
            first = data.get('firstName', '')
            last = data.get('lastName', '')
            full_name = data.get('fullName', '')
            if not full_name and (first or last):
                full_name = f"{first} {last}".strip()

            new_doctor = models.Doctor(
                id=doc_id,
                full_name=full_name,
                degree=data.get('degree'),
                graduation_date=data.get('graduationDate'),
                certificate_url=data.get('certificateUrl'),
                is_verified=data.get('isVerified', False),
                approval_status=data.get('approvalStatus', 'pending'),
                qualifications=data.get('qualifications')
            )
            db_sql.add(new_doctor)
            counts['doctors'] += 1

    db_sql.commit()
    print(f"  ✅ Users (doctors): {counts['users']}, Doctors: {counts['doctors']}")

    # ===================================================================
    # STEP 2: Migrate Patients → users + patients tables
    # ===================================================================
    print("\n[2/6] Migrating PATIENTS...")
    docs = db_firestore.collection('patients').stream()
    for doc in docs:
        data = doc.to_dict()
        doc_id = doc.id

        # --- users table ---
        if not db_sql.query(models.User).filter(models.User.id == doc_id).first():
            full_name = data.get('fullName', data.get('name', ''))
            new_user = models.User(
                id=doc_id,
                email=data.get('email', ''),
                full_name=full_name,
                phone=data.get('phone', ''),
                role='patient'
            )
            db_sql.add(new_user)
            counts['users'] += 1

        # --- patients table ---
        if not db_sql.query(models.Patient).filter(models.Patient.id == doc_id).first():
            doc_doctor_id = data.get('assignedDoctorId')
            if not doc_doctor_id:
                doc_doctor_id = None
            else:
                # Verify FK exists
                exists = db_sql.query(models.User).filter(models.User.id == doc_doctor_id).first()
                if not exists:
                    doc_doctor_id = None

            full_name = data.get('fullName', data.get('name', ''))
            new_patient = models.Patient(
                id=doc_id,
                full_name=full_name,
                assigned_doctor_id=doc_doctor_id,
                assigned_program=sanitize_for_json(data.get('assignedProgram'))
            )
            db_sql.add(new_patient)
            counts['patients'] += 1

    db_sql.commit()
    print(f"  ✅ Users (patients): {counts['users']}, Patients: {counts['patients']}")

    # ===================================================================
    # STEP 3: Migrate Available Slots (from doctors/{id}/availability_slots)
    # ===================================================================
    print("\n[3/6] Migrating AVAILABLE SLOTS...")
    doctor_docs = db_firestore.collection('doctors').stream()
    for doctor_doc in doctor_docs:
        doctor_id = doctor_doc.id
        # Check doctor exists in users
        if not db_sql.query(models.User).filter(models.User.id == doctor_id).first():
            continue

        slots = db_firestore.collection('doctors').document(doctor_id)\
            .collection('availability_slots').stream()
        
        for slot_doc in slots:
            slot_data = slot_doc.to_dict()
            
            date_ts = slot_data.get('date')
            if date_ts is None:
                continue
            date = ts_to_dt(date_ts)
            if date is None:
                continue

            tfh = slot_data.get('timeFromHour', 0)
            tfm = slot_data.get('timeFromMinute', 0)
            tth = slot_data.get('timeToHour', 0)
            ttm = slot_data.get('timeToMinute', 0)

            start_time = datetime(date.year, date.month, date.day, tfh, tfm)
            end_time = datetime(date.year, date.month, date.day, tth, ttm)

            new_slot = models.AvailableSlot(
                doctor_id=doctor_id,
                start_time=start_time,
                end_time=end_time,
                is_booked=False,
                note=''
            )
            db_sql.add(new_slot)
            counts['available_slots'] += 1

    db_sql.commit()
    print(f"  ✅ Available Slots: {counts['available_slots']}")

    # ===================================================================
    # STEP 4: Migrate Bookings (from doctors/{id}/bookings)
    # ===================================================================
    print("\n[4/6] Migrating BOOKINGS...")
    doctor_docs = db_firestore.collection('doctors').stream()
    for doctor_doc in doctor_docs:
        doctor_id = doctor_doc.id
        if not db_sql.query(models.User).filter(models.User.id == doctor_id).first():
            continue

        bookings = db_firestore.collection('doctors').document(doctor_id)\
            .collection('bookings').stream()
        
        for booking_doc in bookings:
            booking_data = booking_doc.to_dict()
            booking_id = booking_doc.id

            # Skip if already exists
            if db_sql.query(models.Booking).filter(models.Booking.id == booking_id).first():
                continue

            date_time = ts_to_dt(booking_data.get('dateTime'))
            end_time = ts_to_dt(booking_data.get('endTime'))
            if date_time is None:
                continue

            patient_id = booking_data.get('patientId', '')
            # Verify patient exists in users, skip FK check if not
            patient_exists = db_sql.query(models.User).filter(models.User.id == patient_id).first()

            new_booking = models.Booking(
                id=booking_id,
                patient_id=patient_id if patient_exists else None,
                doctor_id=doctor_id,
                doctor_name=booking_data.get('doctorName', ''),
                patient_name=booking_data.get('patientName', ''),
                specialty=booking_data.get('specialty', ''),
                date_time=date_time,
                end_time=end_time,
                status=booking_data.get('status', 'upcoming'),
            )
            db_sql.add(new_booking)
            counts['bookings'] += 1

    db_sql.commit()
    print(f"  ✅ Bookings: {counts['bookings']}")

    # ===================================================================
    # STEP 5: Migrate Workout Sessions (from patients/{id}/Sessions)
    # ===================================================================
    print("\n[5/6] Migrating WORKOUT SESSIONS...")
    patient_docs = db_firestore.collection('patients').stream()
    for patient_doc in patient_docs:
        patient_id = patient_doc.id
        if not db_sql.query(models.User).filter(models.User.id == patient_id).first():
            continue

        sessions = db_firestore.collection('patients').document(patient_id)\
            .collection('Sessions').stream()
        
        for session_doc in sessions:
            session_data = session_doc.to_dict()

            timestamp = ts_to_dt(session_data.get('timestamp'))
            accuracy = session_data.get('accuracy')
            if accuracy is not None:
                accuracy = str(round(float(accuracy), 1)) if isinstance(accuracy, (int, float)) else str(accuracy)

            new_session = models.WorkoutSession(
                patient_id=patient_id,
                correct_reps=int(session_data.get('correctReps', 0)),
                incorrect_reps=int(session_data.get('incorrectReps', 0)),
                total_sets=int(session_data.get('currentSet', session_data.get('targetSets', 0))),
                exercise_type=session_data.get('exerciseType', 'Squat'),
                mode=session_data.get('mode', 'Beginner'),
                accuracy=accuracy,
                session_complete=session_data.get('sessionComplete', False),
                timestamp=timestamp,
            )
            db_sql.add(new_session)
            counts['workout_sessions'] += 1

    db_sql.commit()
    print(f"  ✅ Workout Sessions: {counts['workout_sessions']}")

    # ===================================================================
    # STEP 6: Migrate Radiology Reports (from patients/{id}/radiology_reports)
    # ===================================================================
    print("\n[6/6] Migrating RADIOLOGY REPORTS...")
    patient_docs = db_firestore.collection('patients').stream()
    for patient_doc in patient_docs:
        patient_id = patient_doc.id
        if not db_sql.query(models.User).filter(models.User.id == patient_id).first():
            continue

        reports = db_firestore.collection('patients').document(patient_id)\
            .collection('radiology_reports').stream()
        
        for report_doc in reports:
            report_data = report_doc.to_dict()

            doctor_id = report_data.get('doctorId', '')
            # Verify doctor FK
            doctor_exists = db_sql.query(models.User).filter(models.User.id == doctor_id).first()

            created_at = ts_to_dt(report_data.get('createdAt'))

            new_report = models.RadiologyReport(
                patient_id=patient_id,
                doctor_id=doctor_id if doctor_exists else None,
                modality=report_data.get('modality', ''),
                body_part=report_data.get('bodyPart', ''),
                prediction=report_data.get('prediction', ''),
                confidence=safe_str(report_data.get('confidence', '')),
                final_report=report_data.get('finalReport', ''),
                rag_guidelines=report_data.get('ragGuidelines', []),
                heatmap_base64=report_data.get('heatmapBase64'),
                created_at=created_at,
            )
            db_sql.add(new_report)
            counts['radiology_reports'] += 1

    db_sql.commit()
    print(f"  ✅ Radiology Reports: {counts['radiology_reports']}")

    # ===================================================================
    # STEP 7: Migrate Admins (from 'admins' collection)
    # ===================================================================
    print("\n[7/7] Migrating ADMINS...")
    docs = db_firestore.collection('admins').stream()
    for doc in docs:
        data = doc.to_dict()
        admin_id = doc.id
        
        if not db_sql.query(models.Admin).filter(models.Admin.id == admin_id).first():
            full_name = data.get('fullName', '')
            if not full_name:
                first = data.get('firstName', '')
                last = data.get('lastName', '')
                full_name = f"{first} {last}".strip()
            
            new_admin = models.Admin(
                id=admin_id,
                email=data.get('email', ''),
                password="pbkdf2:sha256:600000$unknown$...", # Placeholder as password is not in Firestore
                full_name=full_name
            )
            db_sql.add(new_admin)
            counts['admins'] += 1
    
    db_sql.commit()
    print(f"  ✅ Admins: {counts['admins']}")

    # ===================================================================
    # FINAL SUMMARY
    # ===================================================================
    print("\n" + "="*50)
    print("✅ MIGRATION COMPLETE!")
    print("="*50)
    print(f"  Users:              {counts['users']}")
    print(f"  Doctors:            {counts['doctors']}")
    print(f"  Patients:           {counts['patients']}")
    print(f"  Available Slots:    {counts['available_slots']}")
    print(f"  Bookings:           {counts['bookings']}")
    print(f"  Workout Sessions:   {counts['workout_sessions']}")
    print(f"  Radiology Reports:  {counts['radiology_reports']}")
    print(f"  Admins:             {counts['admins']}")
    print("="*50)

except Exception as e:
    db_sql.rollback()
    print(f"\n[ERROR] Migration failed: {e}")
    import traceback
    traceback.print_exc()
finally:
    db_sql.close()
