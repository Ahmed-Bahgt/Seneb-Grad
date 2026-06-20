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

## 🏋️ AI Pipeline — Live Exercise Session (Computer Vision Module)

This is the engine behind every **Live Exercise Session** a patient runs from the mobile app. It lives in `computer vision trainer module/` and is built entirely on **MediaPipe Pose**.

> 📂 **Module location:** `computer vision trainer module/`

### What it does, in one picture

```
Patient Camera Feed (Flutter app)
        │
        ▼
 MediaPipe Pose
 (helpers/utils.py — _PoseWrapper)
 (33 landmarks (x, y, z, visibility), EMA-smoothed across frames)
        │
        ▼
 Exercise Processor
 (one of: ProcessFrameSquat / ProcessFrameInternalRotation /
  ProcessFrameAbduction — hand-written — or GenericProcessor
  driven by exercises/configs/*.yaml)
        │
        ▼
 Compute Angle / Ratio
 (the specific measurement for that exercise)
        │
        ▼
 Classify State
 (s1 rest → s2 transition → s3 peak)
        │
        ▼
 Grade Rep + Update Counters
 (correct / incorrect rep, set count, accuracy)
        │
        ▼
 Run Form Checks
 (flags specific posture errors, e.g. knee over toe)
        │
        ▼
 Draw Skeleton + Feedback
 (on-screen overlay + sound cue id)
        │
        ▼
 Set / Training Complete?
 ──── no → loop back to Camera Feed
        │ yes
        ▼
 workout_log.json
 (reps, errors, accuracy)
        │
        ▼
 Seneb Clinical Agent (Gemini)
 (Generates structured clinical report + charts)
        │
        ▼
 Doctor receives the full session report
```

### The doctor-facing side: building a new exercise with no code

The "Exercise Builder" screen on the doctor portal (referenced in the Application Flow above) is backed by an AI-assisted wizard in this module:

```
Doctor describes an exercise in plain English
        │
        ▼
 OpenRouter LLM
 (Suggests primary measurement, state thresholds, and form checks)
        │
        ▼
 Live Camera Calibration
 (streamlit-webrtc — doctor sees real measurement values live)
        │
        ▼
 Tune Form-Check Thresholds
 (review/edit each AI-suggested check against live values)
        │
        ▼
 exercises/configs/new_exercise.yaml
        │
        ▼
 GenericProcessor runs it immediately — no code required
```

### 🗂️ File map — `computer vision trainer module/`

| Path | What it is |
|---|---|
| `exercises/process_frame_squat.py` | 🦵 Squat trainer (side view) |
| `exercises/process_frame_internal_rotation.py` | 🔄 Internal rotation trainer (front view) |
| `exercises/ProcessFrameAbduction.py` | 🙆 Shoulder abduction trainer (front view) |
| `exercises/generic_processor.py` | ⚙️ Config-driven engine — runs *any* exercise from a YAML file |
| `exercises/configs/*.yaml` | 📄 Per-exercise definitions consumed by `GenericProcessor` |
| `pages/⚙️_Exercise_Builder.py` | 🧙 Streamlit wizard — AI-assisted exercise creation, no code |
| `helpers/utils.py` | 🧍 MediaPipe pose wrapper + angle math + drawing/overlay helpers |
| `helpers/thresholds.py` | 🎯 Hand-tuned thresholds for the 3 hand-written trainers |
| `scripts/generate_audio.py` | 🔊 Pre-generates EN + AR voice feedback clips |
| `training_agent.py` | 🤖 Post-session clinical report via Gemini |

### 🏃 The three trainers

All three `ProcessFrame*` classes share the exact same shape, so they're drop-in interchangeable from whatever calls them:

```python
__init__(thresholds, flip_frame, reps_per_set, target_sets, rest_time, language)
process(frame, pose) -> (frame, play_sound)
```

| | 🦵 Squat | 🔄 Internal Rotation | 🙆 Shoulder Abduction |
|---|---|---|---|
| **File** | `exercises/process_frame_squat.py` | `exercises/process_frame_internal_rotation.py` | `exercises/ProcessFrameAbduction.py` |
| **Camera view** | Side | Front | Front |
| **Primary measurement** | Knee vertical angle | `rotation_ratio = (wrist_x − elbow_x) / shoulder_width` on the active arm | Avg. left/right shoulder angle (hip→shoulder→elbow) |
| **Special handling** | Camera-alignment check (`offset_angle`) — pauses & asks the patient to turn if not side-on | "Arm lock" — detects the working arm once per set and holds it fixed | Tracks elbow angle + torso lean as secondary signals |
| **Form checks** | 🔻 Bend backwards/forward · 🦶 Knee over toe · 📉 Squat too deep · 💡 *Lower your hips* hint | 💪 Elbow left your side · 📏 Keep forearm level · 🌀 Don't twist torso | 🙅 Arms too high · 📏 Keep arms straight · ⚖️ Even your arms · 🌀 Don't sway back |
| **Thresholds source** | `helpers/thresholds.py` → `get_thresholds_squats_beginner()` / `_pro()` | `helpers/thresholds.py` → `get_thresholds_internal_rotation()` | `helpers/thresholds.py` → `get_thresholds_abduction()` |

### ⚙️ The generic, config-driven engine — `exercises/generic_processor.py`

`GenericProcessor` re-implements the same state-machine / rep-counting / feedback pipeline as the three hand-written trainers above, but driven entirely by a YAML file instead of Python code. This is what lets a doctor add a brand-new exercise as **pure data** through the Exercise Builder, with no engineering involved.

**Measurement types it understands:**

| Type | Use it for |
|---|---|
| `angle` | 3-point joint angle (elbow bend, knee bend) |
| `vertical_angle` | Lean from vertical (torso lean, arm raise) |
| `bilateral_avg/max/min/diff_angle` | Compare left vs. right side |
| `rotation_ratio` | Internal/external rotation across the body |
| `torso_angle` | Forward trunk lean (side view) |
| `lateral_trunk_angle` | Sideways trunk lean (front view) |
| `distance_ratio` | Normalized distance between two landmarks |
| `knee_valgus_ratio` | Knee collapsing inward (front view) |
| `wrist_y_diff`, `elbow_flare_ratio`, `ratio_vs_baseline` | Internal-rotation-specific checks |

**Two exercise modes:**

| Mode | Behavior |
|---|---|
| `rep` (default) | Same `s1 → s2 → s3 → s1` rep-grading as the hand-written trainers |
| `hold` | Isometric/timed hold — a rep = sustaining `s3` for `hold_duration` seconds, with a live progress bar; leaving early (<50% through) counts as incorrect |

**Configs included (`exercises/configs/`):**

| Config | What it demonstrates |
|---|---|
| `squat_beginner.yaml` | Re-implements the squat trainer as config |
| `internal_rotation.yaml` | Re-implements the rotation trainer as config |
| `shoulder_abduction.yaml` | Re-implements the abduction trainer as config |
| `dumbbell_lateral_raise.yaml` | A **brand-new exercise**, defined purely in YAML — no Python required |

### 🧙 `pages/⚙️_Exercise_Builder.py` — the AI-assisted wizard

A Streamlit page so a doctor can create a working exercise config **without writing a measurement formula by hand**:

| Step | What happens |
|---|---|
| **1. Describe it** | Doctor enters a name, plain-language description, camera view, and mode. An OpenRouter LLM call (default `google/gemini-2.0-flash-001`) proposes a measurement, state thresholds, and 3–5 form checks. |
| **2. Calibrate live** | A `streamlit-webrtc` camera feed shows the proposed measurement's real value live, so the doctor can set `s1`/`s2`/`s3` ranges by eye — or upload a calibration video and let peak/valley detection do it automatically. |
| **3. Tune form checks** | Review/edit each AI-suggested check's threshold against live values. |
| **4. Assemble** | `_assemble_cfg` turns the wizard state into a clean YAML dict matching `GenericProcessor`'s schema. |
| **5. Ship it** | The YAML lands in `exercises/configs/`, immediately usable for a live session. |

It reuses the same landmark math as `GenericProcessor` (via a standalone `_compute_meas`), so calibration numbers match exactly what the real session will produce.

### 🧍 `helpers/utils.py` — the MediaPipe layer + shared helpers

**1. MediaPipe pose detection — `get_mediapipe_pose()` / `_PoseWrapper`**

Wraps the newer **MediaPipe Tasks `PoseLandmarker` API** behind the old `mp.solutions.pose`-style interface (`pose.process(frame) → result.pose_landmarks.landmark[i].x/y`), so none of the trainers had to change when MediaPipe's API changed underneath them.

| Concern | How it's handled |
|---|---|
| Model selection | `model_complexity` 0/1/2 → lite / full / heavy `.task` model, auto-downloaded once from Google's storage bucket |
| Thread safety | `PoseLandmarker` is created **lazily, per-thread** (`threading.local`) — avoids a crash when a model built on the Streamlit main thread is called from the WebRTC callback thread |
| Smoothing | Manual **exponential moving average** (`α = 0.5`) across frames, replacing the old `smooth_landmarks=True` behavior that the new Tasks API dropped. Resets when detection is lost. |
| Output shape | Minimal `_PoseResult` / `_LandmarkList` / `_Landmark(x, y, z, visibility)` — matches what every `process(frame, pose)` expects |

**2. Geometry helpers**

- **`find_angle(p1, p2, p3)`** — the angle at vertex `p2` between rays to `p1`/`p3`. Guards against divide-by-zero and clamps `cos θ` to `[-1, 1]`.
- **`get_landmark_array(...)`** — normalized MediaPipe landmark → pixel coordinates.
- **`get_landmark_features(...)`** — pulls a whole limb's coordinates (shoulder/elbow/wrist/hip/knee/ankle/foot) for `'left'`/`'right'`/`'nose'` in one call.

**3. Drawing / overlay helpers**

- **`draw_text(...)`** — rounded-rect background box behind every feedback label and counter; can overlay a ✅/❌ icon (`right.png` / `wrong.png`).
- **`draw_text_arabic(...)`** — reshapes Arabic text (`arabic_reshaper`), applies RTL layout (`python-bidi`), renders via PIL with a cached TrueType font, composites back into the OpenCV BGR frame. (OpenCV's native `putText` can't do Arabic shaping or RTL.)
- **`draw_dotted_line(...)`** — dotted alignment guideline (e.g. plumb lines).

> ⚠️ **Path note:** `right.png`/`wrong.png` and the Arabic font are resolved relative to the working directory / project root at import time. If this module is moved or invoked from elsewhere, check these paths first.

### 🎯 `helpers/thresholds.py`

Hand-tuned dictionaries for the 3 hand-written trainers only — `GenericProcessor` reads its thresholds from YAML instead.

| Function | Covers |
|---|---|
| `get_thresholds_squats_beginner()` | Squat — beginner difficulty |
| `get_thresholds_squats_pro()` | Squat — pro difficulty (deeper bend, stricter back/ankle limits) |
| `get_thresholds_abduction()` | Abduction — arms-too-high angle, elbow floor, asymmetry, back-sway tolerance |
| `get_thresholds_internal_rotation()` | Rotation — state bands, elbow-flare limit, wrist alignment, torso-twist tolerance |

### 🔊 `scripts/generate_audio.py`

```bash
python scripts/generate_audio.py
```

Pre-generates **every** voice feedback clip — rep counts 1–10, `incorrect`, `reset_counters`, and every per-exercise correction cue — in **both English and Arabic** (`gTTS`), saved to `static/audio/en/` and `static/audio/ar/`. The `play_sound` string every trainer returns is the filename (minus `.mp3`) of the clip to play — so this script is the single source of truth for which sound IDs must exist.

### 🤖 `training_agent.py`

Post-session clinical reporting. Takes the session video + `workout_log.json`, uploads the video to **Gemini (`gemini-1.5-pro`)**, and prompts it — with the JSON numbers injected directly so stats are exact, not guessed — for:

1. 📊 Summary statistics
2. ⚠️ Error analysis
3. 🩺 Clinical breakdown (where form broke down, fatigue patterns)
4. 💡 Doctor's recommendation for next session

This is the "Seneb Clinical Agent (Gemini AI)" step in the high-level pipeline diagram above.

### 🔁 Concepts shared by every trainer

| Concept | Summary |
|---|---|
| **State machine** | Every exercise reduces to one number per frame, bucketed into `s1` (rest) → `s2` (transition) → `s3` (peak). A rep is graded from the sequence of states visited since the last `s1`. |
| **Rep grading** | `s1→s2→s3→s1` with no flags = ✅ correct. Only reaching `s2` = ⚠️ incomplete ROM (flagged on-screen ~45 frames). Any posture flag during the sequence = ❌ incorrect, regardless of range. |
| **Sets, rest & accuracy** | After `reps_per_set`, freeze on a rest-timer screen for `rest_time` seconds. Set accuracy (`correct / total`) drives the feedback message and whether it counts as an "effective set." |
| **Grace period** | The first frames of a set aren't graded — gives the patient time to get into position. |
| **Inactivity reset** | No state change for `INACTIVE_THRESH` seconds → counters reset (handles someone walking away). |
| **Bilingual feedback** | Every check has an EN + AR label/voice line, controlled by `language` (`'en'` / `'ar'` / `'both'`). |

**`workout_log.json`** — written once, when `SET_COUNT` reaches `target_sets`. This is the file that gets sent to the backend and is the bridge to `training_agent.py`'s clinical report:

```json
{
  "exercise": "Shoulder Abduction",
  "total_sets_completed": 3,
  "effective_sets": 2,
  "total_correct_reps": 24,
  "total_incorrect_reps": 6,
  "errors_triggered": ["ARMS TOO HIGH", "INCOMPLETE ROM"]
}
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
├── computer vision trainer module/   # 🏋️ Real-time pose, rep counting & form correction — see section above
│   ├── exercises/
│   │   ├── process_frame_squat.py
│   │   ├── process_frame_internal_rotation.py
│   │   ├── ProcessFrameAbduction.py
│   │   ├── generic_processor.py
│   │   └── configs/
│   │       ├── squat_beginner.yaml
│   │       ├── internal_rotation.yaml
│   │       ├── shoulder_abduction.yaml
│   │       └── dumbbell_lateral_raise.yaml
│   ├── pages/
│   │   └── ⚙️_Exercise_Builder.py
│   ├── helpers/
│   │   ├── utils.py
│   │   └── thresholds.py
│   ├── scripts/
│   │   └── generate_audio.py
│   └── training_agent.py
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

## 👨‍💻 Team

Developed as a graduation project by **Ahmed Bahgat** , **Ahmed Hossam** , **Mohamed Ayoub** , **Ebrahim Mohamed** , **Farah Ahmed** , **Laila Mohamed Samir** .

**Supervised by:** [Dr.Noha Gamal El-Din]  
**Institution:** [School of Information Technology and Computer Science
Program of Artificial Intelligence ]  
**Year:** 2026
