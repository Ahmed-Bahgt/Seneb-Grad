import os
import sys
import cv2
import time
import tempfile
import streamlit as st
from pathlib import Path

BASE_DIR = os.path.abspath(os.path.join(__file__, '../../'))
sys.path.append(BASE_DIR)

from helpers.utils import get_mediapipe_pose
from helpers.thresholds import (
    get_thresholds_squats_beginner,
    get_thresholds_squats_pro,
    get_thresholds_abduction,
    get_thresholds_internal_rotation,
)
from exercises.process_frame_squat import ProcessFrameSquat
from exercises.ProcessFrameAbduction import ProcessFrameAbduction
from exercises.process_frame_internal_rotation import ProcessFrameInternalRotation

st.set_page_config(page_title="AI Fitness Trainer Analysis", layout="wide")
st.title('AI Fitness Trainer Analysis')

# -------------------- Exercise selection --------------------
TRAINING_TYPES = ["-- choose training --", "Squats", "Resisted Abduction", "Internal Rotation"]
if "training_choice" not in st.session_state:
    st.session_state["training_choice"] = TRAINING_TYPES[0]
training_choice = st.selectbox("Select Training Type", TRAINING_TYPES, key="training_choice")

# -------------------- Mode selection (Squats only) --------------------
mode = None
if training_choice == "Squats":
    mode = st.radio('Select Mode', ['Beginner', 'Pro'], horizontal=True)

# -------------------- Thresholds --------------------
thresholds = None
if training_choice == "Squats":
    thresholds = get_thresholds_squats_beginner() if mode == "Beginner" else get_thresholds_squats_pro()
elif training_choice == "Resisted Abduction":
    thresholds = get_thresholds_abduction()
elif training_choice == "Internal Rotation":
    thresholds = get_thresholds_internal_rotation()
else:
    st.info("Choose a training type to enable analysis.")

# -------------------- Processor selection --------------------
process_frame_map = {
    "Squats":             ProcessFrameSquat,
    "Resisted Abduction": ProcessFrameAbduction,
    "Internal Rotation":  ProcessFrameInternalRotation,
}

ProcessFrameClass = process_frame_map.get(training_choice)

if ProcessFrameClass is None:
    st.stop()

upload_process_frame = ProcessFrameClass(thresholds=thresholds)

# -------------------- Pose estimator (cached across reruns) --------------------
@st.cache_resource
def _load_pose():
    return get_mediapipe_pose()

pose = _load_pose()

# -------------------- Session-state defaults --------------------
if 'download' not in st.session_state:
    st.session_state['download'] = False
if "uploaded_tempfile_path" not in st.session_state:
    st.session_state["uploaded_tempfile_path"] = None
if "uploaded_filename" not in st.session_state:
    st.session_state["uploaded_filename"] = None
if "analyze_pressed" not in st.session_state:
    st.session_state["analyze_pressed"] = False

# -------------------- Output filename --------------------
safe_name = training_choice.lower().replace(" ", "_") if training_choice != "-- choose training --" else "unknown"
output_video_file = f"analyzed_{safe_name}_{int(time.time())}.mp4"

# -------------------- Upload form --------------------
MAX_MB = 300
ALLOWED = {"mp4", "mov", "avi", "mkv"}

with st.form('Upload', clear_on_submit=True):
    up_file = st.file_uploader("Upload a Video (max {} MB)".format(MAX_MB), type=list(ALLOWED))
    uploaded = st.form_submit_button("Upload")

    if up_file and uploaded:
        fname = up_file.name
        ext = Path(fname).suffix.lower().lstrip(".")
        size_mb = len(up_file.getbuffer()) / (1024 * 1024)
        if ext not in ALLOWED:
            st.error(f"Unsupported file type: .{ext}")
        elif size_mb > MAX_MB:
            st.error(f"File too large: {size_mb:.1f} MB (limit {MAX_MB} MB)")
        else:
            tfile = tempfile.NamedTemporaryFile(delete=False, suffix=f".{ext}")
            try:
                tfile.write(up_file.read())
                tfile.flush()
                tfile.close()
                st.session_state["uploaded_tempfile_path"] = tfile.name
                st.session_state["uploaded_filename"] = fname
                st.session_state["analyze_pressed"] = False
                st.success(f"Uploaded: {fname}")
            except Exception as e:
                st.error(f"Failed to save upload: {e}")
                try:
                    os.remove(tfile.name)
                except Exception:
                    pass

# -------------------- Status panel --------------------
col_s1, col_s2, col_s3 = st.columns(3)
with col_s1:
    st.markdown("**Training**")
    st.write(training_choice)
with col_s2:
    st.markdown("**Mode**")
    st.write(mode or "N/A")
with col_s3:
    st.markdown("**Uploaded file**")
    st.write(st.session_state.get("uploaded_filename") or "No file")

st.markdown("---")

# -------------------- Analyze button --------------------
uploaded_path = st.session_state.get("uploaded_tempfile_path")
ready_for_analysis = (
    training_choice != "-- choose training --"
    and uploaded_path is not None
)

if not ready_for_analysis:
    if training_choice == "-- choose training --":
        st.info("Please select a training type to enable analysis.")
    elif not uploaded_path:
        st.info("Training selected — now upload a video to enable analysis.")
    st.markdown(
        """<div style="margin-top:8px;">
          <button disabled style="background:#9ea7ad;color:white;padding:10px 20px;
            border-radius:8px;border:none;font-weight:600;cursor:not-allowed;">
            Analyze video</button></div>""",
        unsafe_allow_html=True,
    )
else:
    if st.button("Analyze video"):
        st.session_state["analyze_pressed"] = True

# -------------------- Processing --------------------
stframe = st.empty()
download_button = st.empty()

if st.session_state.get("analyze_pressed"):
    temp_path = st.session_state.get("uploaded_tempfile_path")
    if not temp_path or not os.path.exists(temp_path):
        st.warning("Please upload a video first.")
    else:
        vf = None
        video_output = None
        try:
            vf = cv2.VideoCapture(temp_path)
            frame_count = int(vf.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
            fps = int(vf.get(cv2.CAP_PROP_FPS) or 30)
            width  = int(vf.get(cv2.CAP_PROP_FRAME_WIDTH)  or 640)
            height = int(vf.get(cv2.CAP_PROP_FRAME_HEIGHT) or 480)

            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            video_output = cv2.VideoWriter(output_video_file, fourcc, fps, (width, height))

            txt = st.sidebar.markdown('<b>Input Video</b>', unsafe_allow_html=True)
            ip_video = st.sidebar.video(temp_path)
            progress = st.progress(0)
            processed_frames = 0

            while vf.isOpened():
                ret, frame = vf.read()
                if not ret:
                    break

                # frame is BGR from cv2 — pass directly (wrapper handles BGR→RGB internally)
                out_frame, _ = upload_process_frame.process(frame, pose)

                # display: st.image expects RGB
                stframe.image(cv2.cvtColor(out_frame, cv2.COLOR_BGR2RGB), channels="RGB")

                # write: VideoWriter expects BGR
                video_output.write(out_frame)

                processed_frames += 1
                if frame_count > 0:
                    progress.progress(min(100, int(processed_frames / frame_count * 100)))

            progress.progress(100)
            vf.release()
            video_output.release()
            stframe.empty()
            ip_video.empty()
            txt.empty()

            if os.path.exists(output_video_file):
                with open(output_video_file, "rb") as f:
                    download_button.download_button(
                        'Download Analyzed Video',
                        data=f,
                        file_name=os.path.basename(output_video_file),
                    )
                    st.session_state['download'] = True

            st.success("Analysis complete.")

        except Exception as ex:
            st.error(f"Processing failed: {ex}")
        finally:
            try:
                if vf is not None and vf.isOpened():
                    vf.release()
            except Exception:
                pass
            try:
                if video_output is not None:
                    video_output.release()
            except Exception:
                pass
            try:
                if temp_path and os.path.exists(temp_path):
                    os.remove(temp_path)
            except Exception:
                pass
            st.session_state["uploaded_tempfile_path"] = None
            st.session_state["uploaded_filename"] = None
            st.session_state["analyze_pressed"] = False

# -------------------- Clean up output after download --------------------
if os.path.exists(output_video_file) and st.session_state.get('download'):
    try:
        os.remove(output_video_file)
    except Exception:
        pass
    st.session_state['download'] = False
    download_button.empty()
