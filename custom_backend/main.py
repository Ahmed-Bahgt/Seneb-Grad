import os
import sys

# Force UTF-8 for stdout/stderr to avoid charmap errors on Windows
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# Add custom_backend path and radiology path first so all local imports succeed
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RADIOLOGY_PATH = os.path.join(BASE_DIR, "radilogy repoprt generation", "rehab_system")
if RADIOLOGY_PATH not in sys.path:
    sys.path.insert(0, RADIOLOGY_PATH)

from fastapi import FastAPI, Depends, HTTPException, status, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from datetime import datetime
from typing import List
import models, schemas, database, utils
from database import engine, get_db, SessionLocal
import shutil
import base64
from nutrition_service import nutrition_service
from medical_service import medical_service
from clinical_service import clinical_service

try:
    from pipeline import process_medical_image
except ImportError:
    print("Warning: Radiology pipeline not found. Radiology endpoints will fail.")

# Create tables in the database
models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="Tamren Tech Custom API")

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # In production, specify origins!
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- INITIALIZE DEFAULT ADMIN ---
def init_admin():
    db = SessionLocal()
    try:
        admin_email = "admin@tamren.tech"
        admin = db.query(models.Admin).filter(models.Admin.email == admin_email).first()
        if not admin:
            print("[*] Creating default admin account...")
            new_admin = models.Admin(
                email=admin_email,
                password_hash=utils.hash_password("admin123"),
                full_name="System Admin"
            )
            db.add(new_admin)
            db.commit()
            print("[SUCCESS] Default admin created.")
        else:
            # Check if current password is a valid bcrypt hash
            if not admin.password_hash.startswith("$2b$") and not admin.password_hash.startswith("$2a$"):
                print("[*] Updating legacy admin password to secure hash...")
                admin.password_hash = utils.hash_password("admin123")
                db.commit()
                print("[SUCCESS] Admin password secured.")
    finally:
        db.close()

init_admin()

@app.get("/")
def home():
    return {"message": "Welcome to Tamren Tech Custom SQL API", "status": "online"}

# --- AUTH / USER ENDPOINTS ---

@app.post("/users/register", response_model=schemas.UserResponse)
def register_user(user: schemas.UserCreate, db: Session = Depends(get_db)):
    # Check if user exists
    db_user = db.query(models.User).filter(models.User.email == user.email).first()
    if db_user:
        throw_error(status.HTTP_400_BAD_REQUEST, "Email already registered")
    
    # Create user
    new_user = models.User(
        id=user.id if user.id else None,
        email=user.email,
        password_hash=utils.hash_password(user.password),
        role=user.role,
        full_name=user.full_name,
        phone=user.phone
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    # If doctor, add to doctors table
    if user.role == "doctor":
        new_doctor = models.Doctor(id=new_user.id, full_name=user.full_name)
        db.add(new_doctor)
        db.commit()
    
    # If patient, add to patients table
    elif user.role == "patient":
        new_patient = models.Patient(id=new_user.id, full_name=user.full_name)
        db.add(new_patient)
        db.commit()
        
    return new_user

@app.post("/users/login")
def login_user(login_data: schemas.UserLogin, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.email == login_data.email).first()
    if not user or not utils.verify_password(login_data.password, user.password_hash):
        throw_error(status.HTTP_401_UNAUTHORIZED, "Invalid email or password")
    
    return {
        "status": "success",
        "id": user.id,
        "email": user.email,
        "role": user.role,
        "full_name": user.full_name
    }

# --- PROFILE ENDPOINTS ---

@app.get("/profile/{uid}", response_model=schemas.UserResponse)
def get_profile(uid: str, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == uid).first()
    if not user:
        throw_error(status.HTTP_404_NOT_FOUND, "User not found")
    return user

@app.get("/users/all")
def get_all_users(db: Session = Depends(get_db)):
    """Endpoint to view all registered users in the database."""
    users = db.query(models.User).all()
    return [
        {
            "id": u.id, 
            "email": u.email, 
            "full_name": u.full_name, 
            "role": u.role, 
            "phone": u.phone
        } 
        for u in users
    ]

@app.delete("/users/delete-dummy")
def delete_dummy_users(db: Session = Depends(get_db)):
    emails_to_delete = [
        "doctor.ahmed@tamren.tech",
        "doctor.sara@tamren.tech",
        "patient.ali@tamren.tech",
        "patient.mona@tamren.tech"
    ]
    deleted_users = db.query(models.User).filter(models.User.email.in_(emails_to_delete)).delete(synchronize_session=False)
    db.query(models.Doctor).filter(models.Doctor.id.in_(["doc_1001", "doc_1002"])).delete(synchronize_session=False)
    db.query(models.Patient).filter(models.Patient.id.in_(["pat_2001", "pat_2002"])).delete(synchronize_session=False)
    db.commit()
    return {"message": f"Deleted {deleted_users} dummy users."}

# --- SLOT & BOOKING ENDPOINTS ---

@app.post("/slots")
def add_slot(slot: schemas.SlotCreate, doctor_id: str, db: Session = Depends(get_db)):
    # Verify doctor exists
    doctor = db.query(models.User).filter(models.User.id == doctor_id, models.User.role == "doctor").first()
    if not doctor:
        throw_error(status.HTTP_404_NOT_FOUND, "Doctor not found")
        
    new_slot = models.AvailableSlot(
        doctor_id=doctor_id,
        start_time=slot.start_time,
        end_time=slot.end_time,
        note=slot.note
    )
    db.add(new_slot)
    db.commit()
    return {"message": "Slot added successfully"}

@app.get("/slots/available", response_model=List[schemas.SlotResponse])
def get_available_slots(db: Session = Depends(get_db)):
    return db.query(models.AvailableSlot).filter(models.AvailableSlot.is_booked == False).all()

@app.post("/book-slot")
def book_slot(slot_id: int, patient_id: str, db: Session = Depends(get_db)):
    # Verify patient exists
    patient = db.query(models.User).filter(models.User.id == patient_id).first()
    if not patient:
        throw_error(status.HTTP_404_NOT_FOUND, "Patient not found")
        
    slot = db.query(models.AvailableSlot).filter(models.AvailableSlot.id == slot_id).first()
    if not slot or slot.is_booked:
        throw_error(status.HTTP_400_BAD_REQUEST, "Slot unavailable")
    
    slot.is_booked = True
    slot.patient_id = patient_id
    db.commit()
    return {"message": "Slot booked successfully"}

@app.delete("/slots/{slot_id}")
def delete_slot(slot_id: int, db: Session = Depends(get_db)):
    slot = db.query(models.AvailableSlot).filter(models.AvailableSlot.id == slot_id).first()
    if not slot:
        throw_error(404, "Slot not found")
    db.delete(slot)
    db.commit()
    return {"message": "Slot deleted"}

@app.delete("/slots/doctor/{doctor_id}")
def delete_all_doctor_slots(doctor_id: str, db: Session = Depends(get_db)):
    """Delete all non-booked slots for a doctor (used when re-syncing slots)."""
    deleted = db.query(models.AvailableSlot).filter(
        models.AvailableSlot.doctor_id == doctor_id,
        models.AvailableSlot.is_booked == False
    ).delete()
    db.commit()
    return {"message": f"Deleted {deleted} slots for doctor {doctor_id}"}

# --- RADIOLOGY INTEGRATION ---

@app.post("/predict")
async def predict_radiology(
    file: UploadFile = File(...),
    body_part: str = Form(default="Wrist"),
    modality: str = Form(default="X-ray"),
    api_key: str = Form(default=""),
    patient_id: str = Form(default=""),
    doctor_id: str = Form(default=""),
    db: Session = Depends(get_db)
):
    # Verify patient and doctor only if IDs are supplied
    if patient_id and not db.query(models.User).filter(models.User.id == patient_id).first():
        throw_error(404, "Patient not found")
    if doctor_id and not db.query(models.User).filter(models.User.id == doctor_id).first():
        throw_error(404, "Doctor not found")

    temp_dir = os.path.join(RADIOLOGY_PATH, "temp")
    os.makedirs(temp_dir, exist_ok=True)
    image_path = os.path.abspath(os.path.join(temp_dir, f"rad_{int(datetime.now().timestamp())}.png"))

    with open(image_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    original_dir = os.getcwd()
    os.chdir(RADIOLOGY_PATH)
    try:
        result = process_medical_image(image_path, body_part, modality, api_key)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Radiology processing failed: {str(e)}")
    finally:
        os.chdir(original_dir)

    # --- Build Flutter-compatible response (mirrors api_server.py) ---
    cnn = result.get("cnn_findings") or {}

    # Read GradCAM heatmap from file and encode as base64
    heatmap_b64 = None
    gradcam_path = cnn.get("gradcam_path")
    if gradcam_path:
        if not os.path.isabs(gradcam_path):
            gradcam_path = os.path.join(RADIOLOGY_PATH, gradcam_path)
        if os.path.exists(gradcam_path):
            with open(gradcam_path, "rb") as img_f:
                heatmap_b64 = base64.b64encode(img_f.read()).decode()

    prediction = cnn.get("prediction", "Analysis complete")
    confidence_raw = cnn.get("confidence", 0.0)
    confidence_str = f"{round(float(confidence_raw) * 100, 1)}%" if confidence_raw else "N/A"
    rag_texts = [
        g["text"][:500] for g in result.get("rag_guidelines", [])
        if isinstance(g, dict) and "text" in g
    ]

    # Save to database only when both IDs are provided
    if patient_id and doctor_id:
        new_report = models.RadiologyReport(
            patient_id=patient_id,
            doctor_id=doctor_id,
            modality=modality,
            body_part=body_part,
            prediction=prediction,
            confidence=confidence_str,
            final_report=result.get("final_report", ""),
            rag_guidelines=rag_texts,
            heatmap_base64=heatmap_b64 or ""
        )
        db.add(new_report)
        db.commit()

    return JSONResponse({
        "prediction": prediction,
        "confidence": confidence_str,
        "specialist_used": result.get("specialist_used", False),
        "final_report": result.get("final_report", ""),
        "rag_guidelines": rag_texts,
        "heatmap_image": heatmap_b64,
    })

@app.get("/doctors", response_model=List[schemas.UserResponse])
def get_doctors(db: Session = Depends(get_db)):
    return db.query(models.User).filter(models.User.role == "doctor").all()
@app.post("/nutrition/analyze")
async def analyze_meal(
    file: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    try:
        # Read image
        content = await file.read()
        
        # 1. Detect food
        food_text = nutrition_service.detect_food_from_image(content)
        if not food_text:
            throw_error(400, "Could not detect any food in the image.")
            
        # 2. Parse and Calculate
        foods = nutrition_service.parse_food_list(food_text)
        analysis = nutrition_service.analyze_meal(foods)
        
        return {
            "status": "success",
            "detected_text": food_text,
            "analysis": analysis
        }
    except Exception as e:
        throw_error(500, f"Nutrition analysis failed: {str(e)}")

@app.post("/nutrition/chat")
async def nutrition_chat(
    question: str = Form(...),
    meal_data: str = Form(...), # JSON string of previous analysis
    db: Session = Depends(get_db)
):
    try:
        import json
        meal_json = json.loads(meal_data)
        response = nutrition_service.chat(question, meal_json)
        return {"response": response}
    except Exception as e:
        throw_error(500, f"Chat failed: {str(e)}")

@app.post("/nutrition/recalculate")
async def recalculate_nutrition(
    data: dict,
    db: Session = Depends(get_db)
):
    try:
        ingredients = data.get("ingredients", [])
        # Re-map quantity and re-run analysis logic
        analysis = nutrition_service.analyze_meal(ingredients)
        return analysis
    except Exception as e:
        throw_error(500, f"Recalculation failed: {str(e)}")

@app.post("/medical/chat")
async def medical_chat(
    question: str = Form(...),
    context_type: str = Form(default="general"),
    db: Session = Depends(get_db)
):
    try:
        response = medical_service.medical_chat(question, context_type)
        return {"response": response}
    except Exception as e:
        throw_error(500, f"Medical chat failed: {str(e)}")

@app.post("/doctor/analyze-session")
async def analyze_clinical_session(
    session_data: dict
):
    try:
        # We now accept the session data directly from the Flutter app's Firestore payload
        # This completely decouples the AI analysis from the SQL sync state.
        # 1. Generate Charts
        reps_chart, sets_chart = clinical_service.generate_analytics_charts(session_data)
        
        # 2. Get AI Analysis
        analysis_text = clinical_service.analyze_clinical_session(session_data)
        
        # Convert charts to base64 for easy transport to mobile
        with open(reps_chart, "rb") as f:
            reps_base64 = base64.b64encode(f.read()).decode('utf-8')
        with open(sets_chart, "rb") as f:
            sets_base64 = base64.b64encode(f.read()).decode('utf-8')
            
        return {
            "status": "success",
            "analysis": analysis_text,
            "reps_chart": reps_base64,
            "sets_chart": sets_base64
        }
    except Exception as e:
        throw_error(500, f"Clinical analysis failed: {str(e)}")

@app.post("/doctor/clinical-chat")
async def clinical_chat(
    data: dict,
    db: Session = Depends(get_db)
):
    """
    Interactive follow-up chat for the Seneb Clinical Agent.
    Supports natural language questions AND custom graph generation (Python REPL).
    
    Body: {
        "session_id": int,
        "message": str,
        "conversation_history": [{"role": "user"|"assistant", "content": str}],
        "session_data": dict  (optional, if not provided will fetch from DB)
    }
    """
    try:
        user_message = data.get("message", "")
        conversation_history = data.get("conversation_history", [])
        session_data = data.get("session_data", {})

        # If no session_data passed, fetch from DB using session_id
        if not session_data and data.get("session_id"):
            session = db.query(models.WorkoutSession).filter(
                models.WorkoutSession.id == data["session_id"]
            ).first()
            if session:
                session_data = {
                    "id": session.id,
                    "correct_reps": session.correct_reps,
                    "incorrect_reps": session.incorrect_reps,
                    "accuracy": session.accuracy,
                    "exercise_type": session.exercise_type,
                    "mode": session.mode,
                    "total_sets": session.total_sets,
                }

        if not user_message:
            throw_error(400, "Message cannot be empty")

        result = clinical_service.follow_up_chat(
            user_message=user_message,
            session_data=session_data,
            conversation_history=conversation_history,
        )
        return result

    except Exception as e:
        throw_error(500, f"Clinical chat failed: {str(e)}")

# --- ADMIN ENDPOINTS ---

@app.post("/admin/login")
def admin_login(login_data: schemas.UserLogin, db: Session = Depends(get_db)):
    # Query database for admin
    admin = db.query(models.Admin).filter(models.Admin.email == login_data.email).first()
    
    if admin and utils.verify_password(login_data.password, admin.password_hash):
        return {
            "status": "success", 
            "token": f"admin_token_{admin.id}", 
            "role": "admin",
            "full_name": admin.full_name
        }
    throw_error(status.HTTP_401_UNAUTHORIZED, "Invalid admin credentials")

@app.post("/admin/register")
def register_admin(admin_data: schemas.AdminCreate, db: Session = Depends(get_db)):
    # Check if admin already exists
    existing_admin = db.query(models.Admin).filter(models.Admin.email == admin_data.email).first()
    if existing_admin:
        throw_error(status.HTTP_400_BAD_REQUEST, "Admin email already registered")
    
    new_admin = models.Admin(
        id=admin_data.id if admin_data.id else None,  # Use Firebase UID if provided
        email=admin_data.email,
        password_hash=utils.hash_password(admin_data.password),
        full_name=admin_data.full_name
    )
    db.add(new_admin)
    db.commit()
    db.refresh(new_admin)
    return {"message": "Admin created successfully", "id": new_admin.id}

@app.get("/admin/pending-doctors")
def get_pending_doctors(db: Session = Depends(get_db)):
    # Join with User table to get names
    results = db.query(models.Doctor, models.User.full_name, models.User.email)\
        .join(models.User, models.Doctor.id == models.User.id)\
        .filter(models.Doctor.approval_status == "pending").all()
    
    return [
        {
            "id": d.Doctor.id,
            "full_name": d.full_name,
            "email": d.email,
            "degree": d.Doctor.degree,
            "certificate_url": d.Doctor.certificate_url,
            "approval_status": d.Doctor.approval_status
        } for d in results
    ]

@app.post("/admin/approve-doctor")
def approve_doctor(doctor_id: str, status: str, db: Session = Depends(get_db)):
    doctor = db.query(models.Doctor).filter(models.Doctor.id == doctor_id).first()
    if not doctor:
        throw_error(404, "Doctor not found")
    doctor.approval_status = status
    if status == "approved":
        doctor.is_verified = True
    db.commit()
    return {"message": f"Doctor {status}"}

# --- WORKOUT SESSIONS ---

@app.post("/sessions/log")
def log_session(session_data: schemas.SessionCreate, db: Session = Depends(get_db)):
    new_session = models.WorkoutSession(
        patient_id=session_data.patient_id,
        correct_reps=session_data.correct_reps,
        incorrect_reps=session_data.incorrect_reps,
        total_sets=session_data.total_sets,
        exercise_type=session_data.exercise_type,
        mode=session_data.mode,
        accuracy=session_data.accuracy,
        session_complete=session_data.session_complete,
        video_url=session_data.video_url,
    )
    db.add(new_session)
    db.commit()
    return {"message": "Session logged"}

@app.get("/sessions/{patient_id}")
def get_sessions(patient_id: str, db: Session = Depends(get_db)):
    sessions = db.query(models.WorkoutSession).filter(
        models.WorkoutSession.patient_id == patient_id
    ).order_by(models.WorkoutSession.timestamp.desc()).all()
    return [
        {
            "id": s.id,
            "patient_id": s.patient_id,
            "correct_reps": s.correct_reps,
            "incorrect_reps": s.incorrect_reps,
            "total_sets": s.total_sets,
            "exercise_type": s.exercise_type,
            "mode": s.mode,
            "accuracy": s.accuracy,
            "session_complete": s.session_complete,
            "video_url": s.video_url,
            "timestamp": s.timestamp.isoformat() if s.timestamp else None,
        } for s in sessions
    ]

# --- BOOKINGS ---

@app.post("/bookings/create")
def create_booking(booking_data: schemas.BookingCreate, db: Session = Depends(get_db)):
    # Check if booking already exists
    existing = db.query(models.Booking).filter(models.Booking.id == booking_data.id).first()
    if existing:
        return {"message": "Booking already exists", "id": existing.id}
    
    new_booking = models.Booking(
        id=booking_data.id,
        patient_id=booking_data.patient_id,
        doctor_id=booking_data.doctor_id,
        doctor_name=booking_data.doctor_name,
        patient_name=booking_data.patient_name,
        specialty=booking_data.specialty,
        date_time=booking_data.date_time,
        end_time=booking_data.end_time,
        status=booking_data.status,
    )
    db.add(new_booking)
    db.commit()
    return {"message": "Booking created", "id": new_booking.id}

@app.get("/bookings/{patient_id}")
def get_bookings(patient_id: str, db: Session = Depends(get_db)):
    bookings = db.query(models.Booking).filter(
        models.Booking.patient_id == patient_id
    ).order_by(models.Booking.date_time.desc()).all()
    return [
        {
            "id": b.id,
            "patient_id": b.patient_id,
            "doctor_id": b.doctor_id,
            "doctor_name": b.doctor_name,
            "patient_name": b.patient_name,
            "specialty": b.specialty,
            "date_time": b.date_time.isoformat() if b.date_time else None,
            "end_time": b.end_time.isoformat() if b.end_time else None,
            "status": b.status,
        } for b in bookings
    ]

@app.delete("/bookings/{booking_id}")
def cancel_booking(booking_id: str, db: Session = Depends(get_db)):
    booking = db.query(models.Booking).filter(models.Booking.id == booking_id).first()
    if not booking:
        throw_error(404, "Booking not found")
    booking.status = "cancelled"
    db.commit()
    return {"message": "Booking cancelled"}

# Helper for errors
def throw_error(code, detail):
    raise HTTPException(status_code=code, detail=detail)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
