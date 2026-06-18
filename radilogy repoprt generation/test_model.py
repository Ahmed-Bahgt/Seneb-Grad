"""
Test script for best_xray_model.pth
يختبر تحميل الموديل ويعرض معلوماته
"""

import os
import sys
import torch
import torchvision.models as models
import torchvision.transforms as transforms
from PIL import Image
import numpy as np

MODEL_PATH = os.path.join(os.path.dirname(__file__), "best_xray_model.pth")
TEST_IMAGE = os.path.join(os.path.dirname(__file__), "rehab_system", "test_image.png")

print("=" * 60)
print("🔍 Testing best_xray_model.pth")
print("=" * 60)

# ── Step 1: Load the raw checkpoint ──────────────────────────
print(f"\n[1] Loading checkpoint from:\n    {MODEL_PATH}")
checkpoint = torch.load(MODEL_PATH, map_location="cpu", weights_only=False)

# Show what type of object was saved
print(f"\n    Type: {type(checkpoint)}")

if isinstance(checkpoint, dict):
    print(f"    Keys: {list(checkpoint.keys())[:10]}")
    # Try to detect architecture hints
    sample_key = list(checkpoint.keys())[0]
    print(f"    Sample key: {sample_key}")
    
    # Detect architecture from key names
    if "densenet" in sample_key or "denseblock" in sample_key or "norm." in sample_key:
        arch = "DenseNet"
    elif "layer" in sample_key:
        arch = "ResNet"
    elif "features" in sample_key:
        arch = "DenseNet (via features)"
    else:
        arch = "Unknown"
    print(f"    Detected architecture hint: {arch}")
    print(f"    Total parameter tensors: {len(checkpoint)}")
else:
    print(f"    Object saved directly (not a state_dict)")

# ── Step 2: Try DenseNet121 (binary classifier) ───────────────
print("\n[2] Trying DenseNet121 (binary - Normal/Abnormal)...")
try:
    model121 = models.densenet121(weights=None)
    num_ftrs = model121.classifier.in_features
    import torch.nn as nn
    model121.classifier = nn.Linear(num_ftrs, 1)

    state_dict = checkpoint if isinstance(checkpoint, dict) else checkpoint.state_dict()
    # Handle DataParallel prefix
    if any("module." in k for k in state_dict.keys()):
        state_dict = {k.replace("module.", ""): v for k, v in state_dict.items()}

    model121.load_state_dict(state_dict, strict=True)
    model121.eval()
    print("    ✅ DenseNet121 (1 output) loaded SUCCESSFULLY!")
    LOADED_MODEL = model121
    ARCH = "DenseNet121-binary"
except Exception as e:
    print(f"    ❌ DenseNet121 binary failed: {e}")
    LOADED_MODEL = None

# ── Step 3: Try DenseNet121 (14-class) ───────────────────────
if LOADED_MODEL is None:
    print("\n[3] Trying DenseNet121 (14-class CheXNet style)...")
    try:
        model_14 = models.densenet121(weights=None)
        num_ftrs = model_14.classifier.in_features
        model_14.classifier = nn.Linear(num_ftrs, 14)
        state_dict = checkpoint if isinstance(checkpoint, dict) else checkpoint.state_dict()
        if any("module." in k for k in state_dict.keys()):
            state_dict = {k.replace("module.", ""): v for k, v in state_dict.items()}
        model_14.load_state_dict(state_dict, strict=True)
        model_14.eval()
        print("    ✅ DenseNet121 (14 outputs - CheXNet) loaded SUCCESSFULLY!")
        LOADED_MODEL = model_14
        ARCH = "DenseNet121-14class"
    except Exception as e:
        print(f"    ❌ DenseNet121 14-class failed: {e}")

# ── Step 4: Try DenseNet169 ───────────────────────────────────
if LOADED_MODEL is None:
    print("\n[4] Trying DenseNet169 (binary)...")
    try:
        model169 = models.densenet169(weights=None)
        num_ftrs = model169.classifier.in_features
        model169.classifier = nn.Linear(num_ftrs, 1)
        state_dict = checkpoint if isinstance(checkpoint, dict) else checkpoint.state_dict()
        if any("module." in k for k in state_dict.keys()):
            state_dict = {k.replace("module.", ""): v for k, v in state_dict.items()}
        model169.load_state_dict(state_dict, strict=True)
        model169.eval()
        print("    ✅ DenseNet169 (1 output) loaded SUCCESSFULLY!")
        LOADED_MODEL = model169
        ARCH = "DenseNet169-binary"
    except Exception as e:
        print(f"    ❌ DenseNet169 failed: {e}")

# ── Step 5: Try ResNet50 ──────────────────────────────────────
if LOADED_MODEL is None:
    print("\n[5] Trying ResNet50 (binary)...")
    try:
        model_r50 = models.resnet50(weights=None)
        num_ftrs = model_r50.fc.in_features
        model_r50.fc = nn.Linear(num_ftrs, 1)
        state_dict = checkpoint if isinstance(checkpoint, dict) else checkpoint.state_dict()
        if any("module." in k for k in state_dict.keys()):
            state_dict = {k.replace("module.", ""): v for k, v in state_dict.items()}
        model_r50.load_state_dict(state_dict, strict=True)
        model_r50.eval()
        print("    ✅ ResNet50 (1 output) loaded SUCCESSFULLY!")
        LOADED_MODEL = model_r50
        ARCH = "ResNet50-binary"
    except Exception as e:
        print(f"    ❌ ResNet50 failed: {e}")

# ── Step 6: Try loading as full model object ──────────────────
if LOADED_MODEL is None and not isinstance(checkpoint, dict):
    print("\n[6] Checkpoint appears to be a full model object, using directly...")
    try:
        LOADED_MODEL = checkpoint
        LOADED_MODEL.eval()
        ARCH = "Full model object"
        print("    ✅ Full model object used directly!")
    except Exception as e:
        print(f"    ❌ Failed: {e}")

# ── Step 7: Run inference on test image ──────────────────────
if LOADED_MODEL is not None:
    print(f"\n[7] Running inference with {ARCH}...")
    
    transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406],
                             std=[0.229, 0.224, 0.225]),
    ])
    
    # Use test image if exists, else create a dummy one
    if os.path.exists(TEST_IMAGE):
        img = Image.open(TEST_IMAGE).convert("RGB")
        print(f"    Using test image: {TEST_IMAGE}")
    else:
        print("    No test image found — using random noise image")
        img = Image.fromarray(np.random.randint(0, 255, (224, 224, 3), dtype=np.uint8))
    
    input_tensor = transform(img).unsqueeze(0)
    
    with torch.no_grad():
        output = LOADED_MODEL(input_tensor)
    
    print(f"\n    Raw output shape : {output.shape}")
    print(f"    Raw output values: {output}")
    
    if output.shape[1] == 1:
        prob = torch.sigmoid(output).item()
        pred = "Abnormal" if prob >= 0.5 else "Normal"
        conf = prob if prob >= 0.5 else (1 - prob)
        print(f"\n    🎯 Prediction  : {pred}")
        print(f"    📊 Confidence  : {conf * 100:.1f}%")
        print(f"    🔢 Raw sigmoid : {prob:.4f}")
    elif output.shape[1] == 14:
        probs = torch.sigmoid(output)[0]
        CHEXNET_LABELS = [
            "Atelectasis", "Cardiomegaly", "Effusion", "Infiltration",
            "Mass", "Nodule", "Pneumonia", "Pneumothorax",
            "Consolidation", "Edema", "Emphysema", "Fibrosis",
            "Pleural Thickening", "Hernia"
        ]
        print("\n    📋 CheXNet 14-class results:")
        for label, prob in zip(CHEXNET_LABELS, probs.tolist()):
            bar = "█" * int(prob * 20)
            print(f"       {label:<22}: {prob:.3f}  {bar}")
    else:
        probs = torch.softmax(output, dim=1)[0]
        print(f"\n    Probabilities: {probs.tolist()}")

    print("\n" + "=" * 60)
    print(f"✅ Model test COMPLETE! Architecture: {ARCH}")
    print("=" * 60)
else:
    print("\n" + "=" * 60)
    print("❌ FAILED to load the model with any known architecture.")
    print("   Please check the model file or provide the correct architecture.")
    print("=" * 60)
    sys.exit(1)
