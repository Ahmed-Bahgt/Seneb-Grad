import requests

BASE_URL = "https://ahmedbahgt-tamren-tech-backend.hf.space"

users_to_add = [
    {
        "email": "doctor.ahmed@tamren.tech",
        "full_name": "د. أحمد بهجت",
        "phone": "01000000001",
        "role": "doctor",
        "password": "password123",
        "id": "doc_1001"
    },
    {
        "email": "doctor.sara@tamren.tech",
        "full_name": "د. سارة أحمد",
        "phone": "01000000002",
        "role": "doctor",
        "password": "password123",
        "id": "doc_1002"
    },
    {
        "email": "patient.ali@tamren.tech",
        "full_name": "علي محمود",
        "phone": "01100000001",
        "role": "patient",
        "password": "password123",
        "id": "pat_2001"
    },
    {
        "email": "patient.mona@tamren.tech",
        "full_name": "منى خالد",
        "phone": "01100000002",
        "role": "patient",
        "password": "password123",
        "id": "pat_2002"
    }
]

def seed_database():
    print("🚀 بدء إضافة البيانات الوهمية للسيرفر...")
    
    for user in users_to_add:
        try:
            response = requests.post(f"{BASE_URL}/users/register", json=user)
            if response.status_code == 200:
                print(f"✅ تم إضافة: {user['full_name']} ({user['role']})")
            elif response.status_code == 400 and "already registered" in response.text:
                print(f"⚠️ موجود مسبقاً: {user['full_name']}")
            else:
                print(f"❌ خطأ أثناء إضافة {user['full_name']}: {response.text}")
        except Exception as e:
            print(f"❌ خطأ في الاتصال: {e}")

if __name__ == "__main__":
    seed_database()
