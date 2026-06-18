import requests
import json
import uuid

BASE_URL = "http://localhost:8000"
TEST_UID = str(uuid.uuid4())
TEST_ADMIN_UID = str(uuid.uuid4())

def print_result(name, res):
    print(f"--- {name} ---")
    print(f"Status: {res.status_code}")
    print(f"Response: {res.text}\n")

print("Starting API Tests...")

# 1. Test Admin Register
print("1. Testing Admin Register (/admin/register)")
admin_data = {
    "id": TEST_ADMIN_UID,
    "email": f"admin_{TEST_ADMIN_UID[:8]}@test.com",
    "password": "password123",
    "full_name": "Test Admin"
}
r_admin_reg = requests.post(f"{BASE_URL}/admin/register", json=admin_data)
print_result("Admin Register", r_admin_reg)

# 2. Test Admin Login
print("2. Testing Admin Login (/admin/login)")
admin_login = {
    "email": admin_data["email"],
    "password": admin_data["password"]
}
r_admin_log = requests.post(f"{BASE_URL}/admin/login", json=admin_login)
print_result("Admin Login", r_admin_log)

# 3. Test Patient Register
print("3. Testing Patient Sync (/users/register)")
patient_data = {
    "id": TEST_UID,
    "email": f"patient_{TEST_UID[:8]}@test.com",
    "password": "firebase_managed",
    "full_name": "Test Patient",
    "phone": "01012345678",
    "role": "patient"
}
r_patient_reg = requests.post(f"{BASE_URL}/users/register", json=patient_data)
print_result("Patient Register", r_patient_reg)

# 4. Test Create Booking
print("4. Testing Create Booking (/bookings/create)")
booking_id = f"booking_{TEST_UID[:8]}"
booking_data = {
    "id": booking_id,
    "patient_id": TEST_UID,
    "doctor_id": "doc_123",
    "doctor_name": "Dr. Smith",
    "patient_name": "Test Patient",
    "specialty": "Physiotherapy",
    "date_time": "2026-05-15T10:00:00Z",
    "end_time": "2026-05-15T11:00:00Z",
    "status": "upcoming"
}
r_booking = requests.post(f"{BASE_URL}/bookings/create", json=booking_data)
print_result("Create Booking", r_booking)

# 5. Test Log Session
print("5. Testing Log Session (/sessions/log)")
session_data = {
    "patient_id": TEST_UID,
    "correct_reps": 10,
    "incorrect_reps": 2,
    "total_sets": 3,
    "exercise_type": "Squat",
    "mode": "Beginner",
    "accuracy": "83.3",
    "session_complete": True
}
r_session = requests.post(f"{BASE_URL}/sessions/log", json=session_data)
print_result("Log Session", r_session)

print("Tests completed.")
