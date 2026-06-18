import os
import sys
import base64
import shutil

from fastapi import FastAPI, File, UploadFile, Form
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

# Ensure the rehab_system directory is on the path so pipeline imports work
sys.path.insert(0, os.path.dirname(__file__))

from pipeline import process_medical_image
from rag_builder import build_vector_store

# Build RAG vector store on first run if it doesn't exist
VECTOR_STORE = os.path.join(os.path.dirname(__file__), "rag_vector_store.pkl")
if not os.path.exists(VECTOR_STORE):
    print("[*] Vector store not found — building for the first time...")
    os.chdir(os.path.dirname(__file__))
    build_vector_store()

app = FastAPI(title="Radiology AI API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

MURA_DOMAINS = ["Wrist", "Elbow", "Shoulder", "Forearm", "Hand", "Finger", "Humerus"]

BODY_PARTS = MURA_DOMAINS + ["Chest", "Knee", "Hip", "Spine", "Ankle"]


@app.get("/")
def health():
    return {"status": "ok", "message": "Radiology AI API is running"}


@app.post("/predict")
async def predict(
    file: UploadFile = File(...),
    body_part: str = Form(default="Wrist"),
    modality: str = Form(default="X-ray"),
    api_key: str = Form(default=""),
):
    # Save uploaded image to temp dir
    temp_dir = os.path.join(os.path.dirname(__file__), "temp")
    os.makedirs(temp_dir, exist_ok=True)
    image_path = os.path.join(temp_dir, "uploaded_image.png")

    with open(image_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    # Change working directory so relative paths inside pipeline.py work
    original_dir = os.getcwd()
    os.chdir(os.path.dirname(__file__))

    try:
        result = process_medical_image(image_path, body_part, modality, api_key)
    finally:
        os.chdir(original_dir)

    # Read GradCAM heatmap as base64 if available
    heatmap_b64 = None
    cnn = result.get("cnn_findings") or {}
    gradcam_path = cnn.get("gradcam_path")
    if gradcam_path and os.path.exists(gradcam_path):
        with open(gradcam_path, "rb") as img_f:
            heatmap_b64 = base64.b64encode(img_f.read()).decode()

    prediction = cnn.get("prediction", "Analysis complete")
    confidence_raw = cnn.get("confidence", 0.0)
    confidence_str = f"{round(float(confidence_raw) * 100, 1)}%" if confidence_raw else "N/A"

    rag_texts = [g["text"][:500] for g in result.get("rag_guidelines", [])]

    return JSONResponse({
        "prediction": prediction,
        "confidence": confidence_str,
        "specialist_used": result.get("specialist_used", False),
        "final_report": result.get("final_report", ""),
        "rag_guidelines": rag_texts,
        "heatmap_image": heatmap_b64,
    })


@app.get("/body-parts")
def get_body_parts():
    return {"body_parts": BODY_PARTS, "mura_domains": MURA_DOMAINS}
