import streamlit as st
import time
import os
from pipeline import process_medical_image
from rag_builder import build_vector_store

# Auto-initialize RAG Database if it doesn't exist yet
if not os.path.exists("rag_vector_store.pkl"):
    st.toast("Building RAG Vector Database for the first time...")
    build_vector_store()

st.set_page_config(page_title="Universal Rehab AI", page_icon="🏥", layout="wide")

st.title("🏥 Universal AI Radiology & Rehabilitation System")
st.markdown("### Powered by Dynamic Routing & Clinical RAG")

st.sidebar.header("Patient Data Input")

# UI-Driven Dynamic Router Settings
modality = st.sidebar.selectbox("Select Modality", ["X-ray", "MRI", "CT Scan"])

# Notice we include MURA body parts AND general body parts
body_part = st.sidebar.selectbox(
    "Select Body Part", 
    ["Wrist", "Elbow", "Shoulder", "Forearm", "Hand", "Finger", "Humerus", 
     "Chest", "Knee", "Hip", "Spine", "Ankle"]
)

uploaded_file = st.sidebar.file_uploader("Upload Medical Image", type=["png", "jpg", "jpeg", "dcm"])

st.sidebar.markdown("---")
st.sidebar.header("System Settings")
api_key = st.sidebar.text_input("OpenRouter API Key", type="password", help="Get your free key from openrouter.ai")

if st.sidebar.button("Analyze Image"):
    if uploaded_file is None:
        st.error("Please upload an image first.")
    elif not api_key:
        st.error("Please enter your OpenRouter API Key in the sidebar.")
    else:
        with st.spinner(f"Analyzing {body_part} {modality}..."):
            # Save uploaded file to temp directory for PyTorch to read
            import os
            os.makedirs("temp", exist_ok=True)
            image_path = os.path.join("temp", "uploaded_image.png")
            with open(image_path, "wb") as f:
                f.write(uploaded_file.getbuffer())
                
            # Call our Universal Pipeline with the REAL image path and API key
            result = process_medical_image(image_path, body_part, modality, api_key)
            
            st.success("Analysis Complete!")
            
            col1, col2 = st.columns(2)
            
            with col1:
                st.subheader("Image Analysis")
                st.image(uploaded_file, caption=f"Uploaded {body_part} {modality}", use_container_width=True)
                if result["specialist_used"] and result["cnn_findings"].get("gradcam_path"):
                    st.image(result["cnn_findings"]["gradcam_path"], caption=f"Grad-CAM Heatmap", use_container_width=True)
                st.markdown("### 🚦 Router Status")
                if result["specialist_used"]:
                    st.info(f"✅ **Specialist CNN Activated**: Image falls within MURA domain ({body_part}). High-precision custom model used.")
                    st.write(f"**Custom CNN Finding:** {result['cnn_findings']['prediction']}")
                    st.write(f"**Confidence:** {result['cnn_findings']['confidence'] * 100}%")
                else:
                    st.warning(f"⚠️ **Generalist Activated**: {body_part} is outside custom CNN domain. Routing directly to VLM for zero-shot analysis.")
            
            with col2:
                st.subheader("📋 Final Doctor's Report (MedGemma)")
                st.write(result["final_report"])
                
                st.markdown("### 📚 Evidence-Based RAG Guidelines")
                if result["rag_guidelines"]:
                    for idx, guide in enumerate(result["rag_guidelines"]):
                        with st.expander(f"Reference {idx+1}: {guide['metadata']['source']}"):
                            st.write(guide['text'])
                else:
                    st.write("No specific guidelines retrieved.")
