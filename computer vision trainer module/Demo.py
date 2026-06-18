import streamlit as st
from pathlib import Path

st.set_page_config(page_title="AI Fitness Trainer — Examples", layout="centered")
st.title("AI Fitness Trainer — Form Examples")

# --- Configure your available training types and where example videos live ---
# Put your example videos in `my_examples/` next to this script.
# Filenames should match the pattern: <shortname>_<form>.mp4
# Example: my_examples/squat_correct.mp4  (this can be "video of myself")
BASE_DIR = Path("my_examples")

# --- UPDATED EXERCISE SELECTION ---
TRAINING_TYPES = {
    "Squat": "squat", 
    "Resisted Abduction": "abduction",
    "Internal Rotation": "internal_rotation"
}
FORM_OPTIONS = {"Correct": "correct", "Incorrect": "incorrect"}

# --- UI: choose training and form ---
col1, col2 = st.columns([1, 1])
with col1:
    training_choice = st.selectbox("Training type", list(TRAINING_TYPES.keys()))
with col2:
    form_choice = st.selectbox("Form", list(FORM_OPTIONS.keys()))

# --- compute sample path and show immediately ---
short = TRAINING_TYPES[training_choice]
form = FORM_OPTIONS[form_choice]
sample_path = BASE_DIR / f"{short}_{form}.mp4"

if sample_path.exists():
    st.subheader(f"Example — {training_choice} · {form_choice}")
    st.video(str(sample_path))
else:
    st.warning(
        "Example not found for that selection. \n\n"
        "Add a video at: "
        f"`{sample_path}` \n\n"
        "(e.g., place your recorded 5-second sample of yourself with correct form there)."
    )