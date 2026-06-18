from pydantic import BaseModel, EmailStr
from typing import Optional, List, Any
from datetime import datetime

# --- USER SCHEMAS ---
class UserBase(BaseModel):
    email: EmailStr
    full_name: str
    phone: str
    role: str

class UserCreate(UserBase):
    password: str
    id: Optional[str] = None

class AdminCreate(BaseModel):
    id: Optional[str] = None
    email: EmailStr
    password: str
    full_name: str

class AdminResponse(BaseModel):
    id: str
    email: EmailStr
    full_name: str
    class Config:
        from_attributes = True

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class UserResponse(UserBase):
    id: str
    created_at: datetime
    class Config:
        from_attributes = True

# --- DOCTOR SCHEMAS ---
class DoctorBase(BaseModel):
    degree: Optional[str] = None
    graduation_date: Optional[str] = None
    certificate_url: Optional[str] = None

class DoctorResponse(DoctorBase):
    id: str
    is_verified: bool
    approval_status: str
    class Config:
        from_attributes = True

# --- PATIENT SCHEMAS ---
class PatientResponse(BaseModel):
    id: str
    assigned_doctor_id: Optional[str] = None
    class Config:
        from_attributes = True

# --- SLOT SCHEMAS ---
class SlotCreate(BaseModel):
    start_time: datetime
    end_time: datetime
    note: Optional[str] = None

class SlotResponse(BaseModel):
    id: int
    doctor_id: str
    start_time: datetime
    end_time: datetime
    is_booked: bool
    class Config:
        from_attributes = True

# --- BOOKING SCHEMAS ---
class BookingCreate(BaseModel):
    id: str
    patient_id: str
    doctor_id: str
    doctor_name: str
    patient_name: Optional[str] = None
    specialty: Optional[str] = None
    date_time: datetime
    end_time: datetime
    status: str = "upcoming"

# --- SESSION SCHEMAS ---
class SessionCreate(BaseModel):
    patient_id: str
    correct_reps: int
    incorrect_reps: int
    total_sets: int
    exercise_type: str = "Squat"
    mode: str = "Beginner"
    accuracy: Optional[str] = None
    session_complete: bool = False
    video_url: Optional[str] = None
