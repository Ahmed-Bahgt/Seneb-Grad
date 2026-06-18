import os
import time
import json
from rag_builder import retrieve_guidelines

import requests
from inference import predict_and_gradcam

# --- REAL VLM (MedGemma via OpenRouter) ---
def call_medgemma(prompt, api_key, image_path=None):
    """
    Calls MedGemma via OpenRouter API.
    """
    print(f"[*] Sending real request to MedGemma via OpenRouter...")
    
    if not api_key:
        print("[-] WARNING: No API key provided.")
        return _mock_vlm_response("No API key provided in the UI.")
        
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    data = {
        "model": "qwen/qwen3-vl-235b-a22b-thinking", # User requested model
        "messages": [
            {"role": "system", "content": "You are a senior orthopedic rehabilitation doctor."},
            {"role": "user", "content": prompt}
        ],
        "max_tokens": 2000
    }
    
    try:
        response = requests.post("https://openrouter.ai/api/v1/chat/completions", headers=headers, json=data)
        if response.status_code != 200:
            error_msg = f"API returned {response.status_code}: {response.text}"
            print(f"[-] OpenRouter {error_msg}")
            return _mock_vlm_response(error_msg)
        return response.json()['choices'][0]['message']['content']
    except Exception as e:
        error_msg = f"Connection Exception: {e}"
        print(f"[-] OpenRouter API Error: {error_msg}")
        return _mock_vlm_response(error_msg)

def _mock_vlm_response(error_reason):
    return f"""**⚠️ OPENROUTER API CONNECTION FAILED ⚠️**

**Reason:** `{error_reason}`

*Please check that your OPENROUTER_API_KEY is correct, has credits, and the site is not blocked on your network.*

---
**[OFFLINE FALLBACK REPORT]**
Based on the provided information, the patient should undergo conservative management consisting of cryotherapy, progressive range-of-motion exercises, and NSAIDs. Please consult the attached clinical guidelines for the specific step-by-step protocol."""

# --- REAL SPECIALIST CNN (Trained on MURA) ---
def run_custom_cnn(image_path):
    """
    Runs the custom PyTorch model located at best_xray_model.pth
    """
    print(f"[*] Running custom specialist PyTorch CNN on {image_path}...")
    try:
        results = predict_and_gradcam(image_path)
        return results
    except Exception as e:
        print(f"[-] Error running PyTorch model: {e}")
        return {
            "prediction": f"Error loading model: {e}",
            "confidence": 0.0,
            "gradcam_path": None
        }

# --- THE DYNAMIC ROUTER PIPELINE ---
def process_medical_image(image_path, body_part, modality, api_key):
    """
    The main Universal Dynamic Router Pipeline.
    """
    print("\n" + "="*50)
    print("🚀 STARTING UNIVERSAL DIAGNOSTIC ROUTER 🚀")
    print("="*50)
    
    result = {
        "body_part": body_part,
        "modality": modality,
        "specialist_used": False,
        "cnn_findings": None,
        "rag_guidelines": [],
        "final_report": ""
    }

    # 1. THE DISPATCHER (Routing Logic)
    mura_domains = ["Wrist", "Elbow", "Shoulder", "Forearm", "Hand", "Finger", "Humerus"]
    
    if modality == "X-ray" and body_part in mura_domains:
        print(f"[ROUTER] Routing to SPECIALIST (Custom CNN) for {body_part} {modality}")
        result["specialist_used"] = True
        cnn_results = run_custom_cnn(image_path)
        result["cnn_findings"] = cnn_results
        condition_detected = cnn_results["prediction"]
    else:
        print(f"[ROUTER] Routing to GENERALIST (MedGemma) for {body_part} {modality}")
        result["specialist_used"] = False
        condition_detected = f"General condition in {body_part}"

    # 2. THE RESEARCHER (Universal RAG)
    print(f"[RAG] Searching clinical guidelines for: {body_part} {condition_detected}")
    search_query = f"{body_part} {condition_detected} rehabilitation physical therapy"
    guidelines = retrieve_guidelines(search_query, top_k=2)
    
    rag_context = ""
    if guidelines:
        for g in guidelines:
            rag_context += f"- {g['text']} (Source: {g['metadata']['source']})\n\n"
            result["rag_guidelines"].append(g)
        print(f"[RAG] Found {len(guidelines)} highly relevant clinical guidelines.")
    else:
        rag_context = "No specific guidelines found in the local database."
        print("[RAG] No specific guidelines found.")

    # 3. THE COMMUNICATOR (Final Synthesis via MedGemma)
    print("[COMMUNICATOR] Synthesizing final report with VLM...")
    
    # Construct the massive prompt for MedGemma
    prompt = f"""
    You are an expert orthopedic specialist and rehabilitation doctor.
    
    Patient Data:
    - Modality: {modality}
    - Body Part: {body_part}
    """
    
    if result["specialist_used"]:
        prompt += f"""
    - Custom AI Specialist Findings: {result['cnn_findings']['prediction']} (Confidence: {result['cnn_findings']['confidence']})
        """
        
    prompt += f"""
    Evidence-Based Clinical Guidelines Retrieved (RAG):
    {rag_context}
    
    Please write a professional, evidence-based Doctor's Report and Rehabilitation Plan for this patient.
    """
    
    final_report = call_medgemma(prompt, api_key, image_path)
    result["final_report"] = final_report
    
    print("✅ Pipeline processing complete!")
    return result

if __name__ == "__main__":
    # Test the pipeline
    process_medical_image("dummy_path.png", "Wrist", "X-ray")
