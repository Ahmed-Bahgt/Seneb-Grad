import av
import os
import sys
import cv2
import time
import base64
import queue
import glob as _glob

import yaml
import streamlit as st
from streamlit_webrtc import VideoHTMLAttributes, webrtc_streamer
from aiortc.contrib.media import MediaRecorder

_sound_queue: queue.Queue = queue.Queue(maxsize=4)

BASE_DIR = os.path.abspath(os.path.join(__file__, '../../'))
sys.path.append(BASE_DIR)

from helpers.utils import get_mediapipe_pose
from exercises.generic_processor import GenericProcessor

# --- Pre-load all audio files as base64 at startup (avoids per-play file I/O) ---
def _preload_audio():
    cache = {}
    for lang_dir in ('en', 'ar'):
        audio_dir = os.path.join(BASE_DIR, 'static', 'audio', lang_dir)
        if not os.path.exists(audio_dir):
            continue
        for fpath in _glob.glob(os.path.join(audio_dir, '*.mp3')):
            name = os.path.splitext(os.path.basename(fpath))[0]
            with open(fpath, 'rb') as f:
                cache[(lang_dir, name)] = base64.b64encode(f.read()).decode()
    return cache

_AUDIO_CACHE = _preload_audio()

# --- Scan YAML configs once at module load ---
def _load_exercise_configs():
    configs_dir = os.path.join(BASE_DIR, 'exercises', 'configs')
    result = {}
    for path in sorted(_glob.glob(os.path.join(configs_dir, '*.yaml'))):
        with open(path, encoding='utf-8') as f:
            cfg = yaml.safe_load(f)
        name = cfg.get('name', os.path.basename(path))
        result[name] = {'path': path, 'cfg': cfg}
    return result

_EXERCISE_CONFIGS = _load_exercise_configs()

# 1. Page Config
st.set_page_config(layout="wide")
st.title('AI Fitness Trainer: Pose Analysis')

# Make the video element fill the available column width
st.markdown("""
<style>
    video { width: 100% !important; min-height: 480px; }
</style>
""", unsafe_allow_html=True)

# --- CLASS TO MANAGE STATE ---
class TrainingManager:
    def __init__(self):
        self.started = False
        self.countdown_start_time = None # Replaces frame_counter

# Initialize the manager in session state so it doesn't reset on every UI click
if 'training_manager' not in st.session_state:
    st.session_state['training_manager'] = TrainingManager()
manager = st.session_state['training_manager']


# --- SIDEBAR CONTROLS ---
with st.sidebar:
    st.header("Workout Settings")

    exercise_names = list(_EXERCISE_CONFIGS.keys())
    exercise = st.radio('Select Exercise', exercise_names)

    st.markdown("---")

    target_reps       = st.number_input("Reps per Set", min_value=1, max_value=100, value=10, step=1)
    target_sets       = st.number_input("Total Sets",   min_value=1, max_value=20,  value=3,  step=1)
    rest_time_seconds = st.number_input("Rest Between Sets (sec)", min_value=5, max_value=300, value=30, step=5)

    st.markdown("---")
    st.radio("Language / اللغة", ["English", "العربية", "كلاهما (Both)"],
             horizontal=True, key="language_label")
    st.checkbox("Voice Feedback / الصوت", value=True, key="voice_enabled")


# --- INSTANTIATE PROCESSOR ---
_LANG_CODE = {'English': 'en', 'العربية': 'ar', 'كلاهما (Both)': 'both'}
lang_code = _LANG_CODE.get(st.session_state.get('language_label', 'English'), 'en')

_ex_entry = _EXERCISE_CONFIGS.get(exercise, {})
live_process_frame = GenericProcessor(
    yaml_path=_ex_entry['path'],
    flip_frame=True,
    reps_per_set=target_reps,
    target_sets=target_sets,
    rest_time=rest_time_seconds,
    language=lang_code,
) if _ex_entry else None

# Cache the pose wrapper so it isn't recreated on every Streamlit rerun
@st.cache_resource
def _load_pose():
    return get_mediapipe_pose()

pose = _load_pose()

if 'download' not in st.session_state:
    st.session_state['download'] = False

output_video_file = f'output_live.flv'

# Function to manage the appearance and active states
def video_frame_callback(frame: av.VideoFrame):
    image = frame.to_ndarray(format="bgr24")
    
# ---------------------------------------------------------
    # PART 1: VISIBILITY CHECK & 3-SECOND COUNTDOWN
    # ---------------------------------------------------------
    if not manager.started:
        results = pose.process(image)
        body_fully_visible = False
        
        if results.pose_landmarks:
            landmarks = results.pose_landmarks.landmark

            vis_cfg      = _ex_entry.get('cfg', {}).get('visibility_check', {})
            req_indices  = vis_cfg.get('indices',   [0])
            error_msg    = vis_cfg.get('error_msg', "(Body not fully visible)")

            # Check if required landmarks are visible
            all_visible = True
            for idx in req_indices:
                lm = landmarks[idx]
                if not (0 < lm.y < 1 and 0 < lm.x < 1 and lm.visibility > 0.5):
                    all_visible = False
                    break
                    
            body_fully_visible = all_visible
            font = cv2.FONT_HERSHEY_SIMPLEX
            
            if body_fully_visible:
                # 1. Start the timer if it hasn't started yet
                if manager.countdown_start_time is None:
                    manager.countdown_start_time = time.time()
                
                # 2. Calculate how much time has passed
                elapsed_time = time.time() - manager.countdown_start_time
                time_left = 3.0 - elapsed_time

                # 3. Show Countdown or Start
                if time_left > 0:
                    # Show the countdown text (e.g., "GET READY: 3")
                    cv2.putText(image, f"GET READY: {int(time_left) + 1}", (50, 100), font, 1.5, (0, 255, 255), 3)
                    
                    # Draw a shrinking visual loading bar
                    bar_width = int((time_left / 3.0) * 200)
                    cv2.rectangle(image, (50, 130), (50 + bar_width, 150), (0, 255, 255), -1)
                else:
                    # Time is up! Start the exercise logic
                    manager.started = True
            else:
                # --- FAIL STATE (Reset Timer) ---
                manager.countdown_start_time = None
                cv2.putText(image, "ADJUST YOUR POSITION", (50, 100), font, 1, (0, 0, 255), 2)
                cv2.putText(image, error_msg, (50, 140), font, 0.6, (0, 0, 255), 1)

        else:
            # No body detected at all
            manager.countdown_start_time = None
            cv2.putText(image, "PLEASE STAND IN FRAME", (50, 100), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 0, 0), 2)

        return av.VideoFrame.from_ndarray(image, format="bgr24")

    # ---------------------------------------------------------
    # PART 2: ACTUAL TRAINING LOGIC
    # ---------------------------------------------------------
    else:
        # Executes the appropriate logic based on sidebar selection
        image, play_sound = live_process_frame.process(image, pose)
        if play_sound:
            try:
                _sound_queue.put_nowait(play_sound)
            except queue.Full:
                pass
        return av.VideoFrame.from_ndarray(image, format="bgr24")


def out_recorder_factory() -> MediaRecorder:
    return MediaRecorder(output_video_file)


ctx = webrtc_streamer(
    key="fitness-pose-analysis",
    video_frame_callback=video_frame_callback,
    rtc_configuration={"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]},
    media_stream_constraints={"video": {"width": {'min':720, 'ideal':720, 'max':720, 'exact':720}}, "audio": False},
    video_html_attrs=VideoHTMLAttributes(autoPlay=True, controls=False, muted=False),
    out_recorder_factory=out_recorder_factory
)

# ... (your ctx = webrtc_streamer block is just above this) ...

@st.fragment(run_every=1.0)
def _voice_player():
    if not st.session_state.get('voice_enabled', True):
        while True:
            try:
                _sound_queue.get_nowait()
            except queue.Empty:
                break
        return

    # drain to latest — only play the most recent cue
    cue = None
    while True:
        try:
            cue = _sound_queue.get_nowait()
        except queue.Empty:
            break

    if cue is None:
        return

    lang     = st.session_state.get('language_label', 'English')
    lang_dir = 'ar' if lang == 'العربية' else 'en'
    b64      = _AUDIO_CACHE.get((lang_dir, cue))
    if not b64:
        return

    # Create the audio element in the PARENT document so it survives the next
    # fragment re-run (which replaces this iframe's content and would kill a
    # plain <audio> tag before the clip finishes playing).
    st.components.v1.html(f'''<script>
(function(){{
    try {{
        var a = parent.document.createElement('audio');
        a.src = 'data:audio/mp3;base64,{b64}';
        parent.document.body.appendChild(a);
        a.play().catch(function(){{}});
        a.onended = function(){{
            try{{ parent.document.body.removeChild(a); }}catch(e){{}}
        }};
    }} catch(e) {{
        new Audio('data:audio/mp3;base64,{b64}').play().catch(function(){{}});
    }}
}})();
</script>''', height=0)

_voice_player()

# Reset the countdown/started state whenever the stream is not running
if not ctx.state.playing:
    manager.started = False
    manager.countdown_start_time = None

# 1. Only process the video file if the camera is STOPPED
if not ctx.state.playing and os.path.exists(output_video_file):
    try:
        # 2. Read the file into memory so we can close the hard drive handle instantly
        with open(output_video_file, 'rb') as op_vid:
            video_bytes = op_vid.read()
            
        # 3. Create the download button using the memory bytes
        st.download_button(
            label='Download Video', 
            data=video_bytes, 
            file_name='output_live.flv',
            mime='video/x-flv'
        )
        
        # 4. Safely attempt to clean up the file
        try:
            os.remove(output_video_file)
        except PermissionError:
            # If Windows is still holding onto it, don't crash. 
            # The MediaRecorder will simply overwrite this file next time!
            pass 
            
    except Exception as e:
        # A gentle warning if the file is caught in a weird state
        st.warning(f"Video is finalizing, please wait a moment...")