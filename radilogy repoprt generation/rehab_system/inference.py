import torch
import torchvision.transforms as transforms
import torchvision.models as models
from PIL import Image
import numpy as np
import cv2
import os

# Create temp directory for Grad-CAM
os.makedirs("temp", exist_ok=True)

def get_mura_model(model_path):
    """
    Loads the PyTorch model for MURA dataset.
    Assuming a standard DenseNet169 architecture.
    """
    print(f"[*] Loading Custom PyTorch Model from {model_path}...")
    
    # Try to load as state_dict first (standard approach)
    try:
        model = models.densenet121(pretrained=False) # Changed from 169 to 121 based on checkpoint size (1024 features)
        num_ftrs = model.classifier.in_features
        model.classifier = torch.nn.Linear(num_ftrs, 1) # Binary classification
        
        state_dict = torch.load(model_path, map_location=torch.device('cpu'))
        # Handle DataParallel if used during training
        if "module." in list(state_dict.keys())[0]:
            state_dict = {k.replace("module.", ""): v for k, v in state_dict.items()}
            
        model.load_state_dict(state_dict)
    except Exception as e:
        print(f"[-] Failed to load state_dict, error: {e}")
        raise ValueError("Could not load the PyTorch model. Make sure best_xray_model.pth is a DenseNet121 state_dict.")
        
    model.eval()
    return model

def predict_and_gradcam(image_path, model_path=None):
    if model_path is None:
        # Check multiple possible locations
        path1 = os.path.join(os.path.dirname(__file__), "..", "best_xray_model.pth")
        path2 = os.path.join(os.path.dirname(__file__), "best_xray_model.pth")
        
        if os.path.exists(path1):
            model_path = path1
        elif os.path.exists(path2):
            model_path = path2
        else:
            model_path = path1 # Default to path1
            
    """
    Runs inference and generates a simple Grad-CAM heatmap.
    """
    model = get_mura_model(model_path)
    
    # Standard MURA transformations
    transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])
    
    # Load and preprocess image
    image = Image.open(image_path).convert('RGB')
    input_tensor = transform(image).unsqueeze(0)
    
    # --- Real Grad-CAM using gradient hooks on DenseNet121's last denseblock ---
    gradients = []
    activations = []

    def _forward_hook(module, inp, out):
        activations.append(out)

    def _backward_hook(module, grad_inp, grad_out):
        gradients.append(grad_out[0])

    target_layer = model.features.denseblock4
    h_fwd = target_layer.register_forward_hook(_forward_hook)
    h_bwd = target_layer.register_full_backward_hook(_backward_hook)

    # Forward pass with gradients enabled
    model.zero_grad()
    output = model(input_tensor)
    probability = torch.sigmoid(output).item()

    # Backprop through the predicted class score
    output[0, 0].backward()

    h_fwd.remove()
    h_bwd.remove()

    # Threshold for MURA
    prediction = "Abnormal" if probability >= 0.5 else "Normal"
    confidence = probability if probability >= 0.5 else (1 - probability)

    # Compute Grad-CAM heatmap
    pooled_grads = torch.mean(gradients[0], dim=[0, 2, 3])
    activation_map = activations[0][0].detach()          # shape: [C, H, W]
    for i in range(activation_map.shape[0]):
        activation_map[i] *= pooled_grads[i]

    heatmap_np = torch.mean(activation_map, dim=0).cpu().numpy()
    heatmap_np = np.maximum(heatmap_np, 0)               # ReLU
    if heatmap_np.max() > 0:
        heatmap_np = heatmap_np / heatmap_np.max()
    heatmap_np = np.uint8(255 * heatmap_np)
    heatmap_np = cv2.resize(heatmap_np, (224, 224))

    img_cv = cv2.imread(image_path)
    img_cv = cv2.resize(img_cv, (224, 224))
    heatmap_colored = cv2.applyColorMap(heatmap_np, cv2.COLORMAP_JET)
    superimposed_img = heatmap_colored * 0.4 + img_cv
    gradcam_path = "temp/gradcam_output.png"
    cv2.imwrite(gradcam_path, superimposed_img)
    
    return {
        "prediction": prediction,
        "confidence": round(confidence, 4),
        "gradcam_path": gradcam_path
    }

if __name__ == "__main__":
    # Test
    # predict_and_gradcam("some_image.png")
    pass
