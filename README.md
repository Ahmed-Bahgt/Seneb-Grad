# 🩺 Seneb — AI-Powered Physical Therapy & Rehabilitation Platform

> **Graduation Project** · Faculty of Computer Science · 2026

Seneb is a full-stack healthcare platform that connects **doctors** and **patients** through an intelligent mobile application backed by AI-driven services. The system covers the full rehabilitation journey — from X-ray diagnosis to guided exercise sessions, clinical reporting, and personalized nutrition.

---

## 📌 Project Overview

The platform is built to solve a real-world challenge in the Egyptian healthcare system: patients undergoing physical therapy often receive little to no follow-up between clinic visits. Seneb bridges this gap by giving doctors the tools to monitor, prescribe, and analyze — and giving patients a guided, interactive experience from home.

### The Core Pillars

| Pillar | Description |
|---|---|
| 🦴 **X-Ray Analysis** | CNN-based multi-body-part classifier with Grad-CAM heatmaps + LLM report generation |
| 🏋️ **Live Exercise Sessions** | Real-time pose estimation using MediaPipe with rep counting and form correction |
| 🤖 **Clinical AI Agent** | Gemini-powered clinical report generation with session analytics and charts |
| 🔬 **Medical Chatbot** | RAG-enhanced chatbot pulling live PubMed research for evidence-based answers |
| 🥗 **Nutrition AI** | Meal analysis from photos/text using Egyptian food database + chatbot |
| 👨‍⚕️ **Doctor Dashboard** | Full patient management, availability scheduling, booking system, and messaging |

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter Mobile App                          │
│          (Doctor Portal)          (Patient Portal)              │
└────────────────────┬────────────────────────┬───────────────────┘
                     │                        │
         ┌───────────▼────────────┐           │
         │   Firebase Services    │           │
         │  Auth · Firestore      │           │
         │  Storage · Messaging   │           │
         └───────────┬────────────┘           │
                     │                        │
         ┌───────────▼────────────────────────▼───────────────────┐
         │            FastAPI Custom Backend (Python)              │
         │                                                         │
         │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │
         │  │  X-Ray / CNN │  │ Clinical AI  │  │  Nutrition  │  │
         │  │  + Grad-CAM  │  │   (Gemini)   │  │   Service   │  │
         │  └──────────────┘  └──────────────┘  └─────────────┘  │
         │  ┌──────────────┐  ┌──────────────┐                    │
         │  │ Medical Chat │  │  PostgreSQL   │                    │
         │  │  + PubMed RAG│  │   Database   │                    │
         │  └──────────────┘  └──────────────┘                    │
         └─────────────────────────────────────────────────────────┘
                     │
         ┌───────────▼────────────┐
         │   Hugging Face Space   │
         │  (Model Hosting +      │
         │   API Deployment)      │
         └────────────────────────┘
```

---

## 🔄 Application Flow

### For Doctors

1. **Register & Verification** → Doctor registers with credentials, account is verified by admin before access is granted.
2. **Dashboard** → View all assigned patients, upcoming sessions, and pending tasks.
3. **Patient Management** → Add patients, view full history, assign exercise programs.
4. **Exercise Builder** → Build custom rehab plans by selecting exercises per body part and difficulty.
5. **Set Availability** → Define weekly available time slots for patient bookings.
6. **X-Ray Analysis** → Upload an X-ray image → AI classifies the condition (e.g., Wrist Fracture, Knee OA) → Grad-CAM heatmap shows areas of concern → LLM generates a full radiology report.
7. **Clinical Reports** → After each session, the AI generates a structured clinical report with charts showing rep quality and session effectiveness.
8. **Medical Chatbot** → Ask clinical questions → System queries PubMed in real time → Returns evidence-based answers citing medical literature.
9. **Patient Chat** → Real-time messaging with any patient.

### For Patients

1. **Register & Login** → Patient creates an account and logs in.
2. **Book an Appointment** → Browse available doctor slots and book a session.
3. **Home Dashboard** → View upcoming sessions, today's exercises, and notifications.
4. **Live Exercise Session** → Patient performs assigned exercises:
   - Camera activates → MediaPipe detects body pose in real time.
   - System counts correct and incorrect reps based on joint angles.
   - Audio & visual feedback guides the patient during the session.
   - Session data (reps, errors, accuracy) is sent to the backend.
5. **Community Feed** → Browse and share posts with other patients for motivation.
6. **Nutrition Chatbot** → Take a photo of a meal or describe it → AI analyzes nutritional content (calories, macros, vitamins) → Full dietary advice in Arabic or English.
7. **Medical Hub** → Access to general health information and educational content.

---

## 🤖 AI Pipeline — X-Ray Radiology System

```
Patient X-Ray Image
        │
        ▼
 Dispatcher Agent
 (Identifies body part: Wrist, Knee, Shoulder, Hip, Elbow, Hand, Forearm)
        │
        ▼
 Specialist CNN (MURA-trained)
 (Binary Classification: Normal / Abnormal + Confidence Score)
        │
        ▼
 Grad-CAM Module
 (Generates heatmap overlay highlighting affected regions)
        │
        ▼
 RAG Researcher Agent
 (Retrieves relevant clinical guidelines from local vector store)
        │
        ▼
 Communicator Agent (OpenRouter LLM)
 (Generates a structured, professional radiology report)
        │
        ▼
 Final Output: Prediction + Heatmap + Clinical Report
```

---

## 🏋️ AI Pipeline — Live Exercise Session

```
Patient Camera Feed (Flutter)
        │
        ▼
 MediaPipe Pose Estimation
 (33 body landmarks detected in real-time)
        │
        ▼
 Exercise Logic Module
 (Joint angle calculation per exercise, e.g., knee angle for squats)
        │
        ▼
 Rep Counter & Error Detector
 (Counts correct/incorrect reps based on angle thresholds)
        │
        ▼
 Session Complete → Data sent to Backend
        │
        ▼
 Seneb Clinical Agent (Gemini AI)
 (Generates structured clinical analysis report + charts)
        │
        ▼
 Doctor receives the full session report
```

---

## 🛠️ Tech Stack

### Mobile App
- **Framework:** Flutter (Dart)
- **State Management:** `setState` + Provider
- **Pose Estimation:** Google ML Kit / MediaPipe
- **Auth & Database:** Firebase Auth + Cloud Firestore
- **Storage:** Firebase Storage
- **Real-time Messaging:** Firebase Realtime / Firestore streams

### Backend
- **Framework:** FastAPI (Python)
- **Database:** PostgreSQL (Neon Cloud)
- **AI / ML:**
  - `PyTorch` — CNN model for X-ray classification (trained on MURA dataset)
  - `Google Gemini 2.5 Flash` — Clinical analysis & nutrition AI
  - `OpenRouter` — LLM for radiology report generation
  - `MediaPipe` — Pose estimation pipeline
  - `Scikit-learn / FAISS` — RAG vector store for clinical guidelines
  - `Biopython (Entrez)` — Live PubMed research retrieval
- **Deployment:** Docker + Nginx on Hugging Face Spaces

### Infrastructure
- **Model Hosting:** Hugging Face Spaces
- **Container:** Docker + Docker Compose
- **Reverse Proxy:** Nginx

---

## 📁 Project Structure

```
seneb/
├── lib/
│   ├── screens/
│   │   ├── doctor/         # Doctor-facing screens
│   │   │   ├── doctor_home_screen.dart
│   │   │   ├── xray_screen.dart
│   │   │   ├── medical_chatbot_screen.dart
│   │   │   ├── patient_reports_screen.dart
│   │   │   └── exercise_builder_screen.dart
│   │   └── patient/        # Patient-facing screens
│   │       ├── patient_home_screen.dart
│   │       ├── session_live_stream_screen.dart
│   │       ├── nutrition_chatbot_screen.dart
│   │       └── patient_community_screen.dart
│   ├── services/           # API & Firebase service layers
│   ├── utils/              # Exercise logic, pose analyzers, helpers
│   └── widgets/            # Reusable UI components
├── custom_backend/         # FastAPI Python backend
│   ├── main.py             # All API routes
│   ├── clinical_service.py # Gemini clinical AI agent
│   ├── medical_service.py  # PubMed RAG chatbot
│   ├── nutrition_service.py# Nutrition analysis AI
│   └── models.py           # Database models (SQLAlchemy)
├── radilogy repoprt generation/
│   └── rehab_system/
│       ├── pipeline.py     # Full X-ray AI pipeline
│       ├── inference.py    # CNN inference + Grad-CAM
│       └── rag_builder.py  # Clinical guidelines vector store
├── Dockerfile
├── docker-compose.yml
└── .env.production.example # Template for environment variables
```

---

## ⚙️ Setup & Configuration

### 1. Clone the repository
```bash
git clone https://github.com/Ahmed-Bahgt/Seneb-Grad.git
cd Seneb-Grad
```

### 2. Backend Setup
```bash
cd custom_backend
cp ../.env.production.example .env
# Fill in your API keys in .env
pip install -r requirements.txt
uvicorn main:app --reload
```

### 3. Flutter App Setup
```bash
# Copy the example config and fill in your keys
cp lib/utils/api_config.example.dart lib/utils/api_config.dart
# Edit api_config.dart with your backend URL and API keys

flutter pub get
flutter run
```

### 4. Deploy with Docker
```bash
cp .env.production.example .env
# Edit .env with real credentials
docker compose up -d --build
```

---

## 🔑 Required API Keys

| Key | Service | Used For |
|-----|---------|---------|
| `GEMINI_API_KEY` | Google AI Studio | Clinical analysis & nutrition AI |
| `OPENROUTER_API_KEY` | OpenRouter | Radiology report generation |
| `POSTGRES_URL` | Neon / PostgreSQL | Database connection |
| Firebase Config | Firebase Console | Auth, Firestore, Storage |

> All keys should be placed in `.env` (backend) and `lib/utils/api_config.dart` (Flutter app). **Never commit real keys to version control.**

---

## 👨‍💻 Team

Developed as a graduation project by **Ahmed Bahgat** and team.

**Supervised by:** [Supervisor Name]  
**Institution:** [Faculty Name]  
**Year:** 2026
