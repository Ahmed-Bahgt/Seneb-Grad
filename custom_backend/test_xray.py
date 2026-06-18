import sys
import os

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

BASE_DIR = r"d:\Flutter\tamren_tech-Admin"
RADIOLOGY_PATH = os.path.join(BASE_DIR, "radilogy repoprt generation", "rehab_system")
sys.path.insert(0, RADIOLOGY_PATH)

try:
    from pipeline import process_medical_image
    print('Import successful!')
    img_path = os.path.join(RADIOLOGY_PATH, 'test_image.png')
    os.chdir(RADIOLOGY_PATH)
    res = process_medical_image(img_path, 'Wrist', 'X-ray', 'YOUR_OPENROUTER_API_KEY_HERE')
    print('Prediction:', res.get('prediction'))
    print('Final Report:', res.get('final_report')[:100] if res.get('final_report') else 'None')
    print('Success')
except Exception as e:
    import traceback
    print('Error:', e)
    traceback.print_exc()
