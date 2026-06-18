# Doctor Exercise Builder — 5-step wizard that produces a YAML exercise config
# without the doctor ever typing a measurement number.
# Uses OpenRouter (OpenAI-compatible) for AI suggestions in Step 1.

import os
import sys
import cv2
import json
import time
import yaml
import tempfile

import av
import numpy as np
import streamlit as st
from streamlit_webrtc import webrtc_streamer

BASE_DIR = os.path.abspath(os.path.join(__file__, "../../"))
sys.path.append(BASE_DIR)

from helpers.utils import get_mediapipe_pose, find_angle
from exercises.generic_processor import GenericProcessor, _lm

# ── Constants ──────────────────────────────────────────────────────────────────
_COLORS = [
    [255, 80,  80],
    [0,   255, 255],
    [0,   153, 255],
    [255, 255, 0],
    [255, 165, 0],
]
_DISPLAY_Y  = [215, 170, 125, 80, 35]
_RTC_CONFIG = {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
_DEFAULT_MODEL = "google/gemini-2.0-flash-001"

_STATE_OPTIONS = ["s1", "s2", "s3"]

_LANDMARKS = [
    "nose",
    "left_shoulder", "right_shoulder",
    "left_elbow",    "right_elbow",
    "left_wrist",    "right_wrist",
    "left_hip",      "right_hip",
    "left_knee",     "right_knee",
    "left_ankle",    "right_ankle",
    "left_foot",     "right_foot",
]

# Measurement types that need NO extra landmark parameters
_PARAM_FREE = {"torso_angle", "lateral_trunk_angle"}

def _compound_meas_inputs(cid, existing_meas):
    """Render the right landmark parameter widgets for a compound measurement.
    Returns a complete measurement dict, or None if the type was just changed."""
    meas_b_type = st.selectbox(
        "Measurement type",
        ["torso_angle", "lateral_trunk_angle", "knee_valgus_ratio",
         "angle", "vertical_angle", "distance_ratio"],
        index=["torso_angle", "lateral_trunk_angle", "knee_valgus_ratio",
               "angle", "vertical_angle", "distance_ratio"].index(
                   existing_meas.get("type", "torso_angle")
                   if existing_meas and existing_meas.get("type") in
                   ["torso_angle", "lateral_trunk_angle", "knee_valgus_ratio",
                    "angle", "vertical_angle", "distance_ratio"]
                   else "torso_angle"),
        key=f"meas_b_type_{cid}")

    meas_b = {"type": meas_b_type}

    if meas_b_type in _PARAM_FREE:
        st.caption("No landmark parameters needed for this type.")

    elif meas_b_type == "knee_valgus_ratio":
        side = st.selectbox(
            "Side", ["bilateral_max", "left", "right"],
            index=["bilateral_max", "left", "right"].index(
                existing_meas.get("side", "bilateral_max")
                if existing_meas else "bilateral_max"),
            key=f"meas_b_side_{cid}")
        meas_b["side"] = side

    elif meas_b_type == "angle":
        col_p1, col_v, col_p3 = st.columns(3)
        with col_p1:
            meas_b["p1"] = st.selectbox(
                "p1", _LANDMARKS,
                index=_LANDMARKS.index(existing_meas.get("p1", "left_hip")
                                       if existing_meas else "left_hip"),
                key=f"meas_b_p1_{cid}")
        with col_v:
            meas_b["vertex"] = st.selectbox(
                "vertex", _LANDMARKS,
                index=_LANDMARKS.index(existing_meas.get("vertex", "left_knee")
                                       if existing_meas else "left_knee"),
                key=f"meas_b_vertex_{cid}")
        with col_p3:
            meas_b["p3"] = st.selectbox(
                "p3", _LANDMARKS,
                index=_LANDMARKS.index(existing_meas.get("p3", "left_ankle")
                                       if existing_meas else "left_ankle"),
                key=f"meas_b_p3_{cid}")

    elif meas_b_type == "vertical_angle":
        col_p1, col_v = st.columns(2)
        with col_p1:
            meas_b["p1"] = st.selectbox(
                "p1", _LANDMARKS,
                index=_LANDMARKS.index(existing_meas.get("p1", "left_shoulder")
                                       if existing_meas else "left_shoulder"),
                key=f"meas_b_p1_{cid}")
        with col_v:
            meas_b["vertex"] = st.selectbox(
                "vertex", _LANDMARKS,
                index=_LANDMARKS.index(existing_meas.get("vertex", "left_hip")
                                       if existing_meas else "left_hip"),
                key=f"meas_b_vertex_{cid}")

    elif meas_b_type == "distance_ratio":
        col_p1, col_p2 = st.columns(2)
        with col_p1:
            meas_b["p1"] = st.selectbox(
                "Landmark 1", _LANDMARKS,
                index=_LANDMARKS.index(existing_meas.get("p1", "left_ankle")
                                       if existing_meas else "left_ankle"),
                key=f"meas_b_p1_{cid}")
        with col_p2:
            meas_b["p2"] = st.selectbox(
                "Landmark 2", _LANDMARKS,
                index=_LANDMARKS.index(existing_meas.get("p2", "left_hip")
                                       if existing_meas else "left_hip"),
                key=f"meas_b_p2_{cid}")

    return meas_b

# ── Pose singleton (shared with Live Stream page) ──────────────────────────────
@st.cache_resource
def _get_pose():
    return get_mediapipe_pose()

# ── Measurement helper (subset of GenericProcessor._compute) ──────────────────
def _compute_meas(meas, lms, fw, fh):
    """Compute one measurement config against a landmarks list. Returns float or None."""
    def lm(name):
        return _lm(lms, name, fw, fh)

    try:
        mtype = meas.get("type")

        if mtype == "angle":
            return find_angle(lm(meas["p1"]), lm(meas["vertex"]), lm(meas["p3"]))

        if mtype == "vertical_angle":
            v = lm(meas["vertex"])
            return find_angle(lm(meas["p1"]), np.array([v[0], 0]), v)

        if mtype in ("bilateral_avg_angle", "bilateral_max_angle",
                     "bilateral_min_angle", "bilateral_diff_angle"):
            la = find_angle(lm(meas["left"]["p1"]),
                            lm(meas["left"]["vertex"]),
                            lm(meas["left"]["p3"]))
            ra = find_angle(lm(meas["right"]["p1"]),
                            lm(meas["right"]["vertex"]),
                            lm(meas["right"]["p3"]))
            return {
                "bilateral_avg_angle":  (la + ra) / 2,
                "bilateral_max_angle":  max(la, ra),
                "bilateral_min_angle":  min(la, ra),
                "bilateral_diff_angle": abs(la - ra),
            }[mtype]

        if mtype == "torso_angle":
            ls, rs = lm("left_shoulder"),  lm("right_shoulder")
            lh, rh = lm("left_hip"),       lm("right_hip")
            ms = np.array([(ls[0] + rs[0]) // 2, (ls[1] + rs[1]) // 2])
            mh = np.array([(lh[0] + rh[0]) // 2, (lh[1] + rh[1]) // 2])
            return find_angle(ms, np.array([mh[0], 0]), mh)

        if mtype == "lateral_trunk_angle":
            ls, rs = lm("left_shoulder"),  lm("right_shoulder")
            lh, rh = lm("left_hip"),       lm("right_hip")
            mid_s  = np.array([(ls[0]+rs[0])//2, (ls[1]+rs[1])//2], dtype=float)
            mid_h  = np.array([(lh[0]+rh[0])//2, (lh[1]+rh[1])//2], dtype=float)
            dx = float(mid_s[0] - mid_h[0])
            dy = float(mid_h[1] - mid_s[1])
            return float(np.degrees(np.arctan2(abs(dx), max(dy, 1.0))))

        if mtype == "distance_ratio":
            p1 = lm(meas["p1"])
            p2 = lm(meas["p2"])
            ls, rs = lm("left_shoulder"), lm("right_shoulder")
            sw = max(abs(rs[0] - ls[0]), 1)
            return float(np.linalg.norm(p1.astype(float) - p2.astype(float))) / sw

        if mtype == "knee_valgus_ratio":
            ls, rs = lm("left_shoulder"), lm("right_shoulder")
            sw = max(abs(rs[0] - ls[0]), 1)
            side_cfg = meas.get("side", "bilateral_max")

            def _valgus_one(sn):
                k  = lm(f"{sn}_knee");  a = lm(f"{sn}_ankle");  h = lm(f"{sn}_hip")
                t  = float(k[1] - h[1]) / max(float(a[1] - h[1]), 1.0)
                mx = h[0] + t * (a[0] - h[0])
                return (1 if sn == "left" else -1) * float(k[0] - mx) / sw

            if side_cfg == "bilateral_max":
                return max(_valgus_one("left"), _valgus_one("right"))
            return _valgus_one(side_cfg)

    except Exception:
        pass
    return None

# ── OpenRouter call ────────────────────────────────────────────────────────────
def _openrouter_suggest(name, description, view, mode, api_key, model):
    """Ask OpenRouter to generate a JSON exercise config. Returns dict or None."""
    try:
        from openai import OpenAI

        client = OpenAI(
            base_url="https://openrouter.ai/api/v1",
            api_key=api_key,
        )

        bilateral_hint = (
            "Front view: prefer bilateral measurement types (bilateral_avg_angle etc.) "
            "or lateral_trunk_angle / knee_valgus_ratio for lower-body front exercises."
            if view == "front"
            else "Side view: prefer vertical_angle, angle, torso_angle, or distance_ratio."
        )

        hold_hint = (
            "\nThis is a TIMED HOLD / isometric exercise. "
            "The primary_measurement should reflect the POSITION being held (e.g. knee angle at 90°). "
            "s3 zone = the correct hold position. s1 = rest. Form checks should fire when "
            "the person deviates from the correct hold posture while in s3."
            if mode == "hold"
            else ""
        )

        prompt = f"""You are a physiotherapy exercise configuration expert for real-time pose analysis.
Generate a JSON configuration for the exercise below.

Exercise: {name}
Description: {description}
Camera view: {view}
Exercise mode: {mode}{hold_hint}
{bilateral_hint}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
AVAILABLE MEASUREMENT TYPES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ANGLE TYPES:
• "angle" — 3-point angle at vertex.  Needs: p1, vertex, p3.
  Use for: elbow bend, knee bend, hip flexion (side), shoulder rotation.

• "vertical_angle" — angle from vertical. Needs: p1, vertex.
  Use for: torso lean (side view), arm raise from hanging position, tibial angle.

• "bilateral_avg_angle" — average of same angle on both sides.
  Needs: left{{p1,vertex,p3}}, right{{p1,vertex,p3}}.
  Use for: symmetric arm raises, bilateral hip abduction (front view).

• "bilateral_max_angle" — maximum of left/right. Same structure.
  Use for: "worst-side" tracking, asymmetric loading.

• "bilateral_min_angle" — minimum of left/right. Same structure.
  Use for: ensuring BOTH arms reach minimum ROM.

• "bilateral_diff_angle" — absolute left-right difference. Same structure.
  Use for: asymmetry detection.

BODY-SPECIFIC TYPES:
• "torso_angle" — forward trunk lean from vertical (SIDE VIEW). No extra fields.
  Use for: squat/deadlift back angle, trunk flexion.

• "lateral_trunk_angle" — sideways trunk lean (FRONT VIEW). No extra fields.
  Use for: Trendelenburg sign, lateral trunk shift, scoliosis exercises,
  single-leg exercises where compensatory lean is key.

• "distance_ratio" — Euclidean distance between two landmarks, normalised by shoulder width.
  Needs: p1, p2 (landmark names).
  Use for: heel-to-buttock (prone knee flexion), chin-to-chest (cervical flexion),
  hand-to-floor reach test, trunk side-bend reach distance.

• "knee_valgus_ratio" — knee collapse inward relative to hip-ankle plumb line.
  Needs: side ("left" / "right" / "bilateral_max").
  Use for: squat/lunge knee alignment (front view), patellofemoral rehab,
  single-leg squat valgus.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LANDMARK NAMES (use exactly):
nose, left_shoulder, right_shoulder, left_elbow, right_elbow,
left_wrist, right_wrist, left_hip, right_hip,
left_knee, right_knee, left_ankle, right_ankle, left_foot, right_foot

MediaPipe indices (for visibility_check.indices):
nose=0, left_shoulder=11, right_shoulder=12, left_elbow=13, right_elbow=14,
left_wrist=15, right_wrist=16, left_hip=23, right_hip=24,
left_knee=25, right_knee=26, left_ankle=27, right_ankle=28

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FORM CHECK FIELDS EXPLAINED:
• affects_rep: true — rep is counted as INCORRECT if this fires. ONLY use for errors that
  occur EXCLUSIVELY when form is genuinely wrong (e.g. knee valgus, elbow flare).
  NEVER use for thresholds that are crossed during normal movement (e.g. arm angle < 70
  fires on every upward rep — the state machine already handles incomplete ROM).
• skip_in_states: ["s1"] — do NOT fire this check while person is at rest position.
• require_s2_seen: true — only fire after the person has already started moving (prevents
  false positives at the very start of the session).
• measurement_b + condition_b — COMPOUND AND condition. The check only fires when BOTH
  the primary measurement AND this secondary measurement simultaneously meet their conditions.
  Use for: checks that are only relevant in a specific part of the movement arc, e.g.
  "warn about back sway only when knees are also loaded (value > 60)".

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Return ONLY valid JSON (no markdown fences, no explanation):
{{
  "primary_measurement": {{...}},
  "visibility_check": {{
    "indices": [...],
    "error_msg": "short description"
  }},
  "form_checks": [
    {{
      "id": "UNIQUE_UPPER_SNAKE_ID",
      "label_en": "IMPERATIVE ENGLISH INSTRUCTION IN ALL CAPS",
      "label_ar": "Arabic translation",
      "condition_op": ">" or "<",
      "threshold": <float>,
      "measurement": {{...}},
      "affects_rep": false,
      "skip_in_states": [],
      "require_s2_seen": false,
      "measurement_b": null,
      "condition_b": null
    }}
  ]
}}

Generate 3–5 clinically relevant form checks specific to this exercise and camera view.
Thresholds must be realistic (e.g. torso_angle > 15, bilateral_diff_angle > 20, knee_valgus_ratio > 0.12).
Use lateral_trunk_angle, distance_ratio, or knee_valgus_ratio where they add clinical value."""

        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
        )
        text = resp.choices[0].message.content.strip()

        # Strip markdown code fences if the model wrapped the JSON
        if "```" in text:
            for part in text.split("```"):
                part = part.strip().lstrip("json").strip()
                try:
                    return json.loads(part)
                except Exception:
                    continue

        return json.loads(text)

    except Exception as e:
        st.error(f"OpenRouter error: {e}")
        return None

# ── Video calibration helpers ──────────────────────────────────────────────────
def _process_calib_video(uploaded_file, primary_meas):
    """Process every frame of an uploaded video; return [(frame_idx, value), ...]."""
    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
        tmp.write(uploaded_file.read())
        tmp_path = tmp.name

    pose  = _get_pose()
    signal = []
    try:
        cap = cv2.VideoCapture(tmp_path)
        idx = 0
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            fh, fw = frame.shape[:2]
            kp = pose.process(frame)
            if kp.pose_landmarks:
                val = _compute_meas(primary_meas, kp.pose_landmarks.landmark, fw, fh)
                if val is not None:
                    signal.append((idx, float(val)))
            idx += 1
        cap.release()
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    return signal


def _peaks_valleys(vals):
    """Return (peak_values, valley_values) via simple local-extrema scan."""
    peaks, valleys = [], []
    for i in range(1, len(vals) - 1):
        if vals[i] >= vals[i - 1] and vals[i] >= vals[i + 1]:
            peaks.append(vals[i])
        if vals[i] <= vals[i - 1] and vals[i] <= vals[i + 1]:
            valleys.append(vals[i])
    return peaks, valleys

# ── Shared mutable capture state (WebRTC thread ↔ Streamlit main thread) ───────
class _CaptureState:
    def __init__(self):
        self.latest_primary = None   # step 2: latest primary measurement value
        self.latest_checks  = {}     # step 3: {check_id: latest value}

# ── Assemble final YAML config dict ───────────────────────────────────────────
def _assemble_cfg(b):
    gr     = b.get("gemini_result") or {}
    checks = b.get("form_checks", [])

    clean_checks = []
    for i, chk in enumerate(checks):
        op     = chk.get("condition_op", ">")
        thresh = chk.get("threshold", 20.0)

        entry = {
            "id":              chk["id"],
            "label_en":        chk["label_en"],
            "label_ar":        chk.get("label_ar", chk["label_en"]),
            "color":           _COLORS[i % len(_COLORS)],
            "display_y":       _DISPLAY_Y[i % len(_DISPLAY_Y)],
            "sound":           "incorrect",
            "measurement":     chk["measurement"],
            "condition":       f"value {op} {thresh}",
            "affects_rep":     chk.get("affects_rep", False),
        }

        # Advanced fields — only write if non-empty/non-default to keep YAML clean
        skip = chk.get("skip_in_states", [])
        if skip:
            entry["skip_in_states"] = skip

        if chk.get("require_s2_seen"):
            entry["require_s2_seen"] = True

        meas_b = chk.get("measurement_b")
        cond_b = chk.get("condition_b", "").strip()
        if meas_b and cond_b:
            entry["measurement_b"] = meas_b
            entry["condition_b"]   = cond_b

        clean_checks.append(entry)

    cfg = {
        "name":                 b["name"],
        "description":          b.get("description", ""),
        "view":                 b.get("view", "front"),
        "inactive_thresh":      15.0,
        "feedback_persistence": "frame",
        "visibility_check":     gr.get("visibility_check",
                                       {"indices": [0], "error_msg": "(Body not visible)"}),
        "states":               gr.get("states", {"s1": [0, 30], "s2": [30, 60], "s3": [60, 90]}),
        "primary_measurement":  gr.get("primary_measurement", {}),
        "form_checks":          clean_checks,
    }

    if b.get("mode") == "hold":
        cfg["mode"]          = "hold"
        cfg["hold_duration"] = float(b.get("hold_duration", 30))

    return cfg

# ── Step 1: Exercise info + AI ─────────────────────────────────────────────────
def _step1():
    b = st.session_state["_eb"]

    st.subheader("Step 1: What exercise are you building?")

    # ── Basic info ────────────────────────────────────────────────────────────
    col_form, col_view = st.columns([3, 1])
    with col_form:
        b["name"] = st.text_input(
            "Exercise Name", value=b.get("name", ""),
            placeholder="e.g. Shoulder External Rotation")
        b["description"] = st.text_area(
            "Describe the movement",
            value=b.get("description", ""),
            placeholder="e.g. Stand facing camera, elbow at 90°, rotate arm outward",
            height=80)
    with col_view:
        b["view"] = st.radio(
            "Camera View", ["front", "side"],
            index=0 if b.get("view", "front") == "front" else 1)

    # ── Exercise mode ─────────────────────────────────────────────────────────
    st.markdown("---")
    col_mode, col_dur = st.columns([1, 1])
    with col_mode:
        mode_label = st.radio(
            "Exercise Mode",
            ["Repetitions", "Timed Hold (isometric)"],
            index=0 if b.get("mode", "rep") == "rep" else 1,
            horizontal=True,
            help="Repetitions: count full movement cycles. "
                 "Timed Hold: count how many times the patient holds a position for a set duration.")
        b["mode"] = "rep" if mode_label == "Repetitions" else "hold"
    with col_dur:
        if b["mode"] == "hold":
            b["hold_duration"] = st.slider(
                "Hold duration (seconds)", min_value=5, max_value=120,
                value=int(b.get("hold_duration") or 30), step=5,
                help="How many seconds the patient must sustain the position to count one rep.")
        else:
            b["hold_duration"] = None

    # ── API / Model ───────────────────────────────────────────────────────────
    st.markdown("---")
    col_key, col_model = st.columns([2, 2])
    with col_key:
        api_key = os.environ.get("OPENROUTER_API_KEY", "")
        if not api_key:
            api_key = st.text_input(
                "OpenRouter API Key", type="password",
                value=b.get("_api_key", ""),
                help="Get one at openrouter.ai — never stored permanently.")
            b["_api_key"] = api_key
        else:
            st.caption("✅ OPENROUTER_API_KEY env var detected.")
    with col_model:
        model = st.text_input("Model", value=b.get("_model", _DEFAULT_MODEL),
                              help="Any model slug on openrouter.ai")
        b["_model"] = model

    ready = bool(b.get("name") and b.get("description"))
    if st.button("🤖 Generate with AI", type="primary", disabled=not ready):
        if not api_key:
            st.error("Enter your OpenRouter API key.")
        else:
            with st.spinner("Asking AI to design your exercise..."):
                result = _openrouter_suggest(
                    b["name"], b["description"], b["view"], b["mode"], api_key, model)
            if result:
                # Clear stale widget states from any previous generation
                for k in list(st.session_state.keys()):
                    if k.startswith(("en_", "ar_", "thresh1_", "op_", "rep_",
                                     "skip_", "req_", "cond_b_", "has_compound_",
                                     "meas_b_type_", "meas_b_side_",
                                     "meas_b_p1_", "meas_b_vertex_",
                                     "meas_b_p3_", "meas_b_p2_")):
                        del st.session_state[k]
                b["gemini_result"] = result
                b["form_checks"]   = result.get("form_checks", [])
                st.rerun()

    # ── Editable form-check cards ─────────────────────────────────────────────
    if b.get("gemini_result"):
        # Show which primary measurement the AI chose
        pm = (b.get("gemini_result") or {}).get("primary_measurement", {})
        if pm:
            pm_type = pm.get("type", "unknown")
            _MEAS_EXPLAIN = {
                "angle":                "3-joint angle",
                "vertical_angle":       "angle from vertical",
                "bilateral_avg_angle":  "average of both sides",
                "bilateral_max_angle":  "worst side (max)",
                "bilateral_min_angle":  "weakest side (min)",
                "bilateral_diff_angle": "left-right asymmetry",
                "torso_angle":          "forward trunk lean",
                "lateral_trunk_angle":  "sideways trunk lean",
                "distance_ratio":       "distance between two points (normalised)",
                "knee_valgus_ratio":    "knee collapse inward",
                "rotation_ratio":       "forearm rotation across body",
            }
            st.info(
                f"**AI chose primary measurement:** `{pm_type}` — "
                f"{_MEAS_EXPLAIN.get(pm_type, pm_type)}. "
                "This drives the rep/hold state machine.")

        st.markdown("---")
        st.markdown("### AI-Suggested Form Checks")
        st.caption(
            "Edit labels, thresholds, and advanced options. "
            "Delete checks that don't apply. Then Confirm.")

        checks   = b["form_checks"]
        to_delete = []

        for i, chk in enumerate(checks):
            cid = chk.get("id", str(i))
            with st.expander(f"**Check {i+1}: {chk.get('label_en', '')}**", expanded=True):

                # ── Main row ─────────────────────────────────────────────────
                c1, c2, c3 = st.columns([3, 3, 1])
                with c1:
                    chk["label_en"] = st.text_input(
                        "English", value=chk.get("label_en", ""), key=f"en_{cid}")
                    chk["label_ar"] = st.text_input(
                        "Arabic",  value=chk.get("label_ar", ""), key=f"ar_{cid}")
                with c2:
                    chk["threshold"] = st.number_input(
                        "Default threshold", value=float(chk.get("threshold", 20.0)),
                        step=1.0, format="%.1f", key=f"thresh1_{cid}")
                    op_idx = 0 if chk.get("condition_op", ">") == ">" else 1
                    chk["condition_op"] = st.radio(
                        "Fires when value is", [">", "<"],
                        index=op_idx, horizontal=True, key=f"op_{cid}")
                with c3:
                    st.markdown(" ")
                    chk["affects_rep"] = st.checkbox(
                        "Fails rep?", value=chk.get("affects_rep", False), key=f"rep_{cid}",
                        help="Count this rep as incorrect when this check fires. "
                             "Only use for errors that NEVER occur during normal movement.")
                    if st.button("🗑", key=f"del_{i}"):
                        to_delete.append(i)

                # ── Advanced options ──────────────────────────────────────────
                with st.expander("⚙ Advanced options", expanded=False):
                    adv1, adv2 = st.columns(2)
                    with adv1:
                        skip_val = [s for s in chk.get("skip_in_states", []) if s in _STATE_OPTIONS]
                        chk["skip_in_states"] = st.multiselect(
                            "Skip in states",
                            _STATE_OPTIONS,
                            default=skip_val,
                            key=f"skip_{cid}",
                            help="Don't fire this check when the person is in these states. "
                                 "Tip: add s1 to avoid false positives at rest.")
                        chk["require_s2_seen"] = st.checkbox(
                            "Only fire after movement starts",
                            value=bool(chk.get("require_s2_seen", False)),
                            key=f"req_{cid}",
                            help="Prevents false positives at session start — "
                                 "check only activates once the person has begun moving.")
                    with adv2:
                        has_compound = st.checkbox(
                            "Add compound AND condition",
                            value=bool(chk.get("condition_b", "")),
                            key=f"has_compound_{cid}",
                            help="This check fires ONLY when BOTH this measurement AND the "
                                 "secondary measurement simultaneously meet their conditions. "
                                 "Example: warn about back sway only when knee is also loaded (angle > 60).")
                        if has_compound:
                            st.caption("Second measurement — must ALSO fire for the check to activate:")
                            existing_b = chk.get("measurement_b") or {}
                            chk["measurement_b"] = _compound_meas_inputs(cid, existing_b)
                            cond_b_default = chk.get("condition_b", "value > 15")
                            chk["condition_b"] = st.text_input(
                                "Condition on second measurement",
                                value=cond_b_default,
                                key=f"cond_b_{cid}",
                                placeholder='e.g. "value > 15"',
                                help='Use "value" as the variable. Supports >, <, >=, <=.')
                        else:
                            chk["measurement_b"] = None
                            chk["condition_b"]   = None

        for idx in reversed(to_delete):
            checks.pop(idx)
            st.rerun()

        if st.button("Confirm & Next →", type="primary"):
            b["step"] = 2
            st.rerun()

# ── Step 2: Calibrate rest & peak zones ────────────────────────────────────────
def _step2():
    b     = st.session_state["_eb"]
    pmeas = (b.get("gemini_result") or {}).get("primary_measurement", {})
    mode  = b.get("mode", "rep")

    st.subheader("Step 2: Calibrate Rest & Target Positions")

    if mode == "hold":
        st.caption(
            "Hold mode: capture where the patient **starts** (rest) and where they must **hold** (target). "
            "The system learns from your body — you never type a number.")
        lbl_s1, lbl_s3 = "Start position (s1)", "Target hold position (s3)"
        btn_s1, btn_s3 = "📌 Capture Start", "📌 Capture Target Hold"
    else:
        st.caption(
            "The system learns the measurement numbers from your body — you never type them.")
        lbl_s1, lbl_s3 = "Rest (s1)", "Peak (s3)"
        btn_s1, btn_s3 = "📌 Capture Rest", "📌 Capture Peak"

    if "s2_cap" not in st.session_state:
        st.session_state["s2_cap"] = _CaptureState()
    cap = st.session_state["s2_cap"]

    tab_live, tab_video = st.tabs(["📹 Live Webcam", "📂 Upload Video"])

    # ── Live tab ──────────────────────────────────────────────────────────────
    with tab_live:
        st.markdown(f"**1.** Stand in **{lbl_s1}** → click *{btn_s1}*")
        st.markdown(f"**2.** Move to **{lbl_s3}** → click *{btn_s3}*")

        mc1, mc2 = st.columns(2)
        with mc1:
            v1 = b.get("s1_val")
            st.metric(lbl_s1, f"{v1:.1f}" if v1 is not None else "—")
            if st.button(btn_s1, key="cap_s1"):
                v = cap.latest_primary
                if v is not None:
                    b["s1_val"] = float(v)
                    st.rerun()
                else:
                    st.warning("No pose detected yet — start the webcam first.")
        with mc2:
            v3 = b.get("s3_val")
            st.metric(lbl_s3, f"{v3:.1f}" if v3 is not None else "—")
            if st.button(btn_s3, key="cap_s3"):
                v = cap.latest_primary
                if v is not None:
                    b["s3_val"] = float(v)
                    st.rerun()
                else:
                    st.warning("No pose detected yet — start the webcam first.")

        pose_inst = _get_pose()

        def _zone_cb(frame):
            img       = frame.to_ndarray(format="bgr24")
            fh, fw    = img.shape[:2]
            kp        = pose_inst.process(img)
            if kp.pose_landmarks:
                val = _compute_meas(pmeas, kp.pose_landmarks.landmark, fw, fh)
                if val is not None:
                    cap.latest_primary = float(val)
                    cv2.putText(img, f"{val:.2f}",
                                (fw // 2 - 70, 90),
                                cv2.FONT_HERSHEY_SIMPLEX, 3.0,
                                (0, 255, 255), 6, cv2.LINE_AA)
            return av.VideoFrame.from_ndarray(img, format="bgr24")

        webrtc_streamer(
            key="eb-s2-live",
            video_frame_callback=_zone_cb,
            rtc_configuration=_RTC_CONFIG,
            media_stream_constraints={"video": True, "audio": False},
        )

    # ── Video tab ─────────────────────────────────────────────────────────────
    with tab_video:
        st.markdown("Upload a short clip (5–15 s) of 2–3 correct reps (or entries into the hold position).")
        uploaded = st.file_uploader(
            "Video clip", type=["mp4", "avi", "mov", "mkv"],
            key="s2_vid_upload")

        if uploaded:
            if st.button("Analyse Video", key="analyse_vid"):
                if not pmeas:
                    st.error("No primary measurement from Step 1. Use the live tab.")
                else:
                    with st.spinner("Processing frames..."):
                        sig = _process_calib_video(uploaded, pmeas)

                    if len(sig) < 10:
                        st.error("Too few frames detected. Try a longer or clearer clip.")
                    else:
                        vals      = [v for _, v in sig]
                        idxs      = [i for i, _ in sig]
                        k         = max(1, min(5, len(vals) // 4))
                        smoothed  = np.convolve(vals, np.ones(k) / k, mode="same").tolist()
                        peaks, valleys = _peaks_valleys(smoothed)
                        st.session_state["_eb_video_sig"] = {
                            "idxs":      idxs,
                            "vals":      smoothed,
                            "s1_guess":  float(np.median(valleys)) if valleys else float(min(vals)),
                            "s3_guess":  float(np.median(peaks))   if peaks   else float(max(vals)),
                        }
                        st.rerun()

        sig = st.session_state.get("_eb_video_sig")
        if sig:
            import pandas as pd
            df = pd.DataFrame({"Frame": sig["idxs"], "Measurement": sig["vals"]})
            st.line_chart(df.set_index("Frame"))

            vc1, vc2 = st.columns(2)
            with vc1:
                s1_v = st.number_input(f"{lbl_s1} value",
                                       value=float(sig["s1_guess"]),
                                       step=1.0, format="%.1f")
            with vc2:
                s3_v = st.number_input(f"{lbl_s3} value",
                                       value=float(sig["s3_guess"]),
                                       step=1.0, format="%.1f")
            if st.button("✅ Use These Values", key="use_vid_vals"):
                b["s1_val"] = s1_v
                b["s3_val"] = s3_v
                st.rerun()

    # ── Zone summary + navigation ─────────────────────────────────────────────
    st.markdown("---")
    if b.get("s1_val") is not None and b.get("s3_val") is not None:
        lo  = min(b["s1_val"], b["s3_val"])
        hi  = max(b["s1_val"], b["s3_val"])
        rng = hi - lo

        if rng < 5:
            st.warning(
                f"{lbl_s1} and {lbl_s3} are too close (< 5 units). "
                "Please recapture — make sure you move to the full target position.")
        else:
            buf = max(5.0, rng * 0.12)

            if b.get("gemini_result") is None:
                b["gemini_result"] = {}
            b["gemini_result"]["states"] = {
                "s1": [round(lo - buf, 2), round(lo + buf, 2)],
                "s2": [round(lo + buf, 2), round(hi - buf, 2)],
                "s3": [round(hi - buf, 2), round(hi + buf, 2)],
            }
            st.success(
                f"✅  {lbl_s1} ≈ **{lo:.1f}**  |  {lbl_s3} ≈ **{hi:.1f}**  |  "
                f"Buffer ± {buf:.1f}  |  transition zone: {lo+buf:.1f} → {hi-buf:.1f}")

            nb, _, nn = st.columns([1, 3, 1])
            with nb:
                if st.button("← Back", key="s2_back"):
                    b["step"] = 1
                    st.rerun()
            with nn:
                if st.button("Confirm Zones & Next →", type="primary", key="s2_next"):
                    b["step"] = 3
                    st.rerun()
    else:
        if st.button("← Back", key="s2_back_only"):
            b["step"] = 1
            st.rerun()

# ── Step 3: Form-check threshold calibration ───────────────────────────────────
def _step3():
    b      = st.session_state["_eb"]
    checks = b.get("form_checks", [])

    st.subheader("Step 3: Calibrate Form-Check Thresholds")

    if not checks:
        st.info("No form checks to calibrate.")
        nb, _, nn = st.columns([1, 3, 1])
        with nb:
            if st.button("← Back", key="s3_back_empty"):
                b["step"] = 2
                st.rerun()
        with nn:
            if st.button("Next →", type="primary", key="s3_next_empty"):
                b["step"] = 4
                st.rerun()
        return

    st.caption(
        "Sliders are pre-filled by the AI. "
        "Optionally start the webcam, stand in the **BAD position** for a check, "
        "and click *Use live value* to auto-calibrate that threshold.")

    if "s3_cap" not in st.session_state:
        st.session_state["s3_cap"] = _CaptureState()
    cap3 = st.session_state["s3_cap"]

    pose_inst = _get_pose()

    def _check_cb(frame):
        img    = frame.to_ndarray(format="bgr24")
        fh, fw = img.shape[:2]
        kp     = pose_inst.process(img)
        if kp.pose_landmarks:
            lms = kp.pose_landmarks.landmark
            for chk in checks:
                val = _compute_meas(chk.get("measurement", {}), lms, fw, fh)
                if val is not None:
                    cap3.latest_checks[chk["id"]] = float(val)
        return av.VideoFrame.from_ndarray(img, format="bgr24")

    with st.expander("📹 Optional live capture", expanded=False):
        webrtc_streamer(
            key="eb-s3-live",
            video_frame_callback=_check_cb,
            rtc_configuration=_RTC_CONFIG,
            media_stream_constraints={"video": True, "audio": False},
        )

    st.markdown("---")

    for i, chk in enumerate(checks):
        cid      = chk["id"]
        op       = chk.get("condition_op", ">")
        default  = float(chk.get("threshold", 20.0))
        live_val = cap3.latest_checks.get(cid)

        skip_note = ""
        if chk.get("skip_in_states"):
            skip_note = f" *(skipped in: {', '.join(chk['skip_in_states'])})*"
        if chk.get("require_s2_seen"):
            skip_note += " *(only after movement starts)*"

        st.markdown(f"**{chk['label_en']}**{skip_note} — fires when `value {op} threshold`")
        tc1, tc2, tc3 = st.columns([2, 2, 1])

        with tc1:
            t = st.number_input(
                "Threshold", value=default, step=1.0, format="%.1f",
                key=f"s3_t_{i}")
            chk["threshold"] = t

        with tc2:
            if live_val is not None:
                st.metric("Live measurement now", f"{live_val:.3f}")
                if st.button("Use live value", key=f"s3_use_{i}"):
                    chk["threshold"] = round(
                        live_val * 0.90 if op == ">" else live_val * 1.10, 2)
                    st.rerun()
            else:
                st.caption("Start webcam above, stand in bad position, then use live value.")

        with tc3:
            chk["affects_rep"] = st.checkbox(
                "Fails rep", value=chk.get("affects_rep", False), key=f"s3_rep_{i}")

        st.divider()

    nb, _, nn = st.columns([1, 3, 1])
    with nb:
        if st.button("← Back", key="s3_back"):
            b["step"] = 2
            st.rerun()
    with nn:
        if st.button("Next →", type="primary", key="s3_next"):
            b["step"] = 4
            st.rerun()

# ── Step 4: Test live ──────────────────────────────────────────────────────────
def _cleanup_test():
    p = st.session_state.pop("_test_yaml", None)
    st.session_state.pop("s4_proc", None)
    if p and os.path.exists(p):
        try:
            os.unlink(p)
        except Exception:
            pass


def _step4():
    b    = st.session_state["_eb"]
    mode = b.get("mode", "rep")

    st.subheader("Step 4: Test Your Exercise")
    reps_label = "holds" if mode == "hold" else "reps"
    st.caption(
        f"Perform 3 {reps_label} to confirm counting and feedback work correctly. "
        + (f"Hold each position for {b.get('hold_duration', 30)}s." if mode == "hold" else ""))

    cfg_dict = _assemble_cfg(b)

    if "_test_yaml" not in st.session_state:
        tmp = tempfile.NamedTemporaryFile(
            mode="w", suffix=".yaml", delete=False, encoding="utf-8")
        yaml.dump(cfg_dict, tmp, allow_unicode=True, default_flow_style=False)
        tmp.close()
        st.session_state["_test_yaml"] = tmp.name

    if "s4_proc" not in st.session_state:
        st.session_state["s4_proc"] = GenericProcessor(
            yaml_path=st.session_state["_test_yaml"],
            flip_frame=True,
            reps_per_set=3,
            target_sets=1,
            rest_time=5,
            language="en",
        )
    proc      = st.session_state["s4_proc"]
    pose_inst = _get_pose()

    def _test_cb(frame):
        img        = frame.to_ndarray(format="bgr24")
        img, _     = proc.process(img, pose_inst)
        return av.VideoFrame.from_ndarray(img, format="bgr24")

    webrtc_streamer(
        key="eb-s4-test",
        video_frame_callback=_test_cb,
        rtc_configuration=_RTC_CONFIG,
        media_stream_constraints={"video": True, "audio": False},
    )

    nb, _, col_r, col_n = st.columns([1, 2, 1, 1])
    with nb:
        if st.button("← Back", key="s4_back"):
            _cleanup_test()
            b["step"] = 3
            st.rerun()
    with col_r:
        if st.button("🔄 Retry", key="s4_retry"):
            _cleanup_test()
            st.rerun()
    with col_n:
        if st.button("✅ Save →", type="primary", key="s4_next"):
            _cleanup_test()
            b["step"] = 5
            st.rerun()

# ── Step 5: Save ───────────────────────────────────────────────────────────────
def _step5():
    b = st.session_state["_eb"]

    st.subheader("Step 5: Save Exercise")

    cfg_dict = _assemble_cfg(b)

    col_preview, col_save = st.columns([3, 2])

    with col_preview:
        st.markdown("**YAML preview**")
        st.code(yaml.dump(cfg_dict, allow_unicode=True, default_flow_style=False),
                language="yaml")

    with col_save:
        safe = b["name"].lower().replace(" ", "_").replace("/", "_")
        filename = st.text_input("Filename (.yaml)", value=safe)
        if not filename.endswith(".yaml"):
            filename += ".yaml"
        out_path = os.path.join(BASE_DIR, "exercises", "configs", filename)
        st.caption(f"Will save to: `exercises/configs/{filename}`")

        st.markdown("---")
        if st.button("💾 Save Exercise", type="primary"):
            with open(out_path, "w", encoding="utf-8") as f:
                yaml.dump(cfg_dict, f, allow_unicode=True, default_flow_style=False)
            st.success(
                f"✅ **{b['name']}** saved!  "
                "Navigate to **Live Stream** and it will appear in the exercise dropdown.")
            st.balloons()
            if st.button("Build another exercise"):
                st.session_state["_eb"] = _init_builder()
                st.rerun()

    nb, _ = st.columns([1, 4])
    with nb:
        if st.button("← Back", key="s5_back"):
            b["step"] = 4
            st.rerun()

# ── Builder state init ─────────────────────────────────────────────────────────
def _init_builder():
    return {
        "step":          1,
        "name":          "",
        "description":   "",
        "view":          "front",
        "mode":          "rep",
        "hold_duration": 30,
        "gemini_result": None,
        "form_checks":   [],
        "s1_val":        None,
        "s3_val":        None,
    }

# ══════════════════════════════════════════════════════════════════════════════
# Page
# ══════════════════════════════════════════════════════════════════════════════
st.set_page_config(layout="wide")
st.title("⚙️ Exercise Builder")
st.caption(
    "Build a custom rehabilitation exercise in 5 steps — "
    "no measurement numbers required.")

if "_eb" not in st.session_state:
    st.session_state["_eb"] = _init_builder()

b = st.session_state["_eb"]

# ── Step progress bar ──────────────────────────────────────────────────────────
STEP_LABELS = [
    "1  Exercise Info",
    "2  Calibrate Zones",
    "3  Form Checks",
    "4  Test Live",
    "5  Save",
]
prog_cols = st.columns(5)
for ci, (col, label) in enumerate(zip(prog_cols, STEP_LABELS)):
    snum = ci + 1
    if snum == b["step"]:
        col.markdown(f"**:blue[{label}]**")
    elif snum < b["step"]:
        col.markdown(f":green[{label} ✓]")
    else:
        col.markdown(f":gray[{label}]")

st.divider()

# ── Route ──────────────────────────────────────────────────────────────────────
{1: _step1, 2: _step2, 3: _step3, 4: _step4, 5: _step5}[b["step"]]()
