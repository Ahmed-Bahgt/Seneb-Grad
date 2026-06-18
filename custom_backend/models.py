import uuid
from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Text, JSON
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base

def generate_uuid():
    return str(uuid.uuid4())

class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, index=True, default=generate_uuid) # UUID from Firebase or Auth
    email = Column(String, unique=True, index=True)
    password_hash = Column(String)
    role = Column(String) # 'patient' | 'doctor' | 'admin'
    full_name = Column(String)
    phone = Column(String)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Admin(Base):
    __tablename__ = "admins"

    id = Column(String, primary_key=True, index=True, default=generate_uuid)
    email = Column(String, unique=True, index=True)
    password_hash = Column(String)
    full_name = Column(String)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Doctor(Base):
    __tablename__ = "doctors"

    id = Column(String, ForeignKey("users.id"), primary_key=True)
    full_name = Column(String) # حقل مكرر للسهولة
    degree = Column(String)
    graduation_date = Column(String)
    certificate_url = Column(String)
    is_verified = Column(Boolean, default=False)
    approval_status = Column(String, default="pending") # pending | approved | rejected
    qualifications = Column(JSON) # Store list of qualifications

    user = relationship("User")

class Patient(Base):
    __tablename__ = "patients"

    id = Column(String, ForeignKey("users.id"), primary_key=True)
    full_name = Column(String) # حقل مكرر للسهولة
    assigned_doctor_id = Column(String, ForeignKey("users.id"), nullable=True)
    assigned_program = Column(JSON, nullable=True)

    user = relationship("User", foreign_keys=[id])
    doctor = relationship("User", foreign_keys=[assigned_doctor_id])

class AvailableSlot(Base):
    __tablename__ = "available_slots"

    id = Column(Integer, primary_key=True, index=True)
    doctor_id = Column(String, ForeignKey("users.id"))
    start_time = Column(DateTime(timezone=True))
    end_time = Column(DateTime(timezone=True))
    is_booked = Column(Boolean, default=False)
    patient_id = Column(String, ForeignKey("users.id"), nullable=True)
    note = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class RadiologyReport(Base):
    __tablename__ = "radiology_reports"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(String, ForeignKey("users.id"))
    doctor_id = Column(String, ForeignKey("users.id"))
    modality = Column(String)
    body_part = Column(String)
    prediction = Column(String)
    confidence = Column(String)
    final_report = Column(Text)
    rag_guidelines = Column(JSON)
    heatmap_base64 = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class WorkoutSession(Base):
    __tablename__ = "workout_sessions"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(String, ForeignKey("users.id"))
    correct_reps = Column(Integer)
    incorrect_reps = Column(Integer)
    total_sets = Column(Integer)
    exercise_type = Column(String, default="Squat")
    mode = Column(String, default="Beginner")
    accuracy = Column(String, nullable=True)
    session_complete = Column(Boolean, default=False)
    video_url = Column(String, nullable=True)
    errors_triggered = Column(JSON)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())

class Booking(Base):
    __tablename__ = "bookings"

    id = Column(String, primary_key=True, index=True)
    patient_id = Column(String, ForeignKey("users.id"))
    doctor_id = Column(String, ForeignKey("users.id"))
    doctor_name = Column(String)
    patient_name = Column(String, nullable=True)
    specialty = Column(String, nullable=True)
    date_time = Column(DateTime(timezone=True))
    end_time = Column(DateTime(timezone=True))
    status = Column(String, default="upcoming")  # upcoming | completed | cancelled
    created_at = Column(DateTime(timezone=True), server_default=func.now())

