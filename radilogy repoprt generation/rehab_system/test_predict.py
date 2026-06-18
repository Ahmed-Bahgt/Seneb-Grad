import requests
import json

# Use the test image in rehab_system folder
with open('test_image.png', 'rb') as f:
    image_bytes = f.read()

print('Sending X-ray image to /predict (Wrist, X-ray)...')
print('This may take 30-60 seconds for model inference...')

resp = requests.post(
    'http://localhost:8001/predict',
    files={'file': ('test_image.png', image_bytes, 'image/png')},
    data={
        'body_part': 'Wrist',
        'modality': 'X-ray',
        'api_key': ''
    },
    timeout=120
)

print(f'Status: {resp.status_code}')
result = resp.json()

print()
print('===== PREDICTION RESULT =====')
print(f'  Prediction     : {result.get("prediction")}')
print(f'  Confidence     : {result.get("confidence")}')
print(f'  Specialist CNN : {result.get("specialist_used")}')
heatmap = result.get("heatmap_image")
print(f'  Heatmap image  : {"YES - base64 (" + str(len(heatmap)) + " chars)" if heatmap else "NO"}')
print()
print('===== FINAL REPORT =====')
report = result.get('final_report', '')
print(report[:800])
print()
print('===== RAG GUIDELINES =====')
for i, g in enumerate(result.get('rag_guidelines', [])):
    print(f'[{i+1}] {g[:300]}')
    print()
print('MODEL TEST COMPLETE!')
