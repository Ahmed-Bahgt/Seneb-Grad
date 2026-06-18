"""
Run once to pre-generate all voice feedback MP3 clips (EN + AR).
  python scripts/generate_audio.py
"""
import os
from gtts import gTTS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EN_DIR = os.path.join(ROOT, 'static', 'audio', 'en')
AR_DIR = os.path.join(ROOT, 'static', 'audio', 'ar')
os.makedirs(EN_DIR, exist_ok=True)
os.makedirs(AR_DIR, exist_ok=True)

EN_CLIPS = {
    '1': 'One',   '2': 'Two',   '3': 'Three', '4': 'Four',  '5': 'Five',
    '6': 'Six',   '7': 'Seven', '8': 'Eight', '9': 'Nine',  '10': 'Ten',
    'incorrect':      'Incorrect rep',
    'reset_counters': 'Set complete, take a rest',
    'arms_too_high':       'Arms are too high',
    'keep_arms_straight':  'Keep your arms straight',
    'level_arms':          'Level your arms',
    'dont_sway_back':      "Don't sway your back",
    'elbow_left_side':     'Keep your elbow at your side',
    'keep_forearm_level':  'Keep your forearm level',
    'dont_twist_torso':    "Don't twist your torso",
    'bend_backwards':  'Bend backwards',
    'bend_forward':    'Bend forward',
    'knee_over_toe':   'Knee is falling over your toe',
    'squat_too_deep':  'Squat is too deep',
}

AR_CLIPS = {
    '1': 'واحد',  '2': 'اثنان', '3': 'ثلاثة', '4': 'أربعة', '5': 'خمسة',
    '6': 'ستة',   '7': 'سبعة',  '8': 'ثمانية','9': 'تسعة',  '10': 'عشرة',
    'incorrect':      'تكرار خاطئ',
    'reset_counters': 'انتهت المجموعة، خذ راحة',
    'arms_too_high':       'ذراعاك مرتفعتان',
    'keep_arms_straight':  'حافظ على استقامة ذراعيك',
    'level_arms':          'سوِّ ذراعيك',
    'dont_sway_back':      'لا تهتز بظهرك',
    'elbow_left_side':     'الكوع بعيد عن جانبك',
    'keep_forearm_level':  'حافظ على ساعدك أفقياً',
    'dont_twist_torso':    'لا تلوي جذعك',
    'bend_backwards':  'انحنِ للخلف',
    'bend_forward':    'انحنِ للأمام',
    'knee_over_toe':   'الركبة تتجاوز إصبع القدم',
    'squat_too_deep':  'الجلسة عميقة جداً',
}

def generate(clips, out_dir, lang):
    for cue_id, text in clips.items():
        out_path = os.path.join(out_dir, f'{cue_id}.mp3')
        tts = gTTS(text=text, lang=lang, slow=False)
        tts.save(out_path)
        print(f'  [{lang}] {cue_id}.mp3  ("{text}")')

print('Generating English clips …')
generate(EN_CLIPS, EN_DIR, 'en')
print('\nGenerating Arabic clips …')
generate(AR_CLIPS, AR_DIR, 'ar')
print(f'\nDone — {len(EN_CLIPS)} EN + {len(AR_CLIPS)} AR clips generated.')
