import requests

# New API key provided by the user
OPENROUTER_KEY = "YOUR_OPENROUTER_API_KEY_HERE"

with open('test_image.png', 'rb') as f:
    image_bytes = f.read()

print("=" * 60)
print("TESTING FULL PIPELINE (with NEW OpenRouter API key)")
print("=" * 60)
print("Sending Wrist X-ray image...")
print("Pipeline steps:")
print("  1. Dispatcher -> Specialist CNN (MURA domain)")
print("  2. Researcher -> RAG Clinical Guidelines")
print("  3. Communicator -> OpenRouter (Report Generation)")
print()

# Using 127.0.0.1 instead of localhost to bypass IPv6 issues
resp = requests.post(
    'http://127.0.0.1:8001/predict',
    files={'file': ('test_image.png', image_bytes, 'image/png')},
    data={
        'body_part': 'Wrist',
        'modality': 'X-ray',
        'api_key': OPENROUTER_KEY
    },
    timeout=120
)

print(f'HTTP Status: {resp.status_code}')
result = resp.json()

print()
print("=" * 60)
print("STEP 1 - DISPATCHER (CNN Result):")
print("=" * 60)
print(f"  Specialist CNN used : {result.get('specialist_used')}")
print(f"  Prediction          : {result.get('prediction')}")
print(f"  Confidence          : {result.get('confidence')}")
heatmap = result.get("heatmap_image")
print(f"  Grad-CAM Heatmap    : {'Generated (' + str(len(heatmap)) + ' chars base64)' if heatmap else 'NOT generated'}")

print()
print("=" * 60)
print("STEP 2 - RESEARCHER (RAG Guidelines):")
print("=" * 60)
guidelines = result.get('rag_guidelines', [])
print(f"  Guidelines found: {len(guidelines)}")
for i, g in enumerate(guidelines):
    print(f"  [{i+1}] {g[:200]}...")

print()
print("=" * 60)
print("STEP 3 - COMMUNICATOR (Final Doctor's Report):")
print("=" * 60)
report = result.get('final_report', '')
print(report)
print()
print("=" * 60)
print("PIPELINE TEST COMPLETE!")
print("=" * 60)
