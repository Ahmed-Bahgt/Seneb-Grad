

# Get thresholds for squats beginner mode
def get_thresholds_squats_beginner():

    _ANGLE_HIP_KNEE_VERT = {
                            'NORMAL' : (0,  30),
                            'TRANS'  : (35, 65),
                            'PASS'   : (70, 95)
                           }    

        
    thresholds = {
                    'HIP_KNEE_VERT': _ANGLE_HIP_KNEE_VERT,

                    'HIP_THRESH'   : [10, 60],
                    'ANKLE_THRESH' : 45,
                    'KNEE_THRESH'  : [50, 70, 95],

                    'OFFSET_THRESH'    : 50.0,
                    'INACTIVE_THRESH'  : 15.0,

                    'CNT_FRAME_THRESH' : 50
                            
                }

    return thresholds



# Get thresholds for squats pro mode
def get_thresholds_squats_pro():

    _ANGLE_HIP_KNEE_VERT = {
                            'NORMAL' : (0,  30),
                            'TRANS'  : (35, 65),
                            'PASS'   : (80, 95)
                           }    

        
    thresholds = {
                    'HIP_KNEE_VERT': _ANGLE_HIP_KNEE_VERT,

                    'HIP_THRESH'   : [15, 50],
                    'ANKLE_THRESH' : 30,
                    'KNEE_THRESH'  : [50, 80, 95],

                    'OFFSET_THRESH'    : 50.0,
                    'INACTIVE_THRESH'  : 15.0,

                    'CNT_FRAME_THRESH' : 50
                            
                 }
                 
    return thresholds



def get_thresholds_abduction():
    return {'SHOULDER_ABDUCTION': {'NORMAL': (0, 45), 'TRANS': (45, 64), 'PASS': (64, 120)},
            'ARMS_TOO_HIGH': 125,
            'ELBOW_BENT_THRESH': 140, 'ASYMMETRY_THRESH': 20, 'OFFSET_THRESH': 35.0, 'INACTIVE_THRESH': 15.0, 'BACK_THRESH': 10}
    

def get_thresholds_internal_rotation():
    return {
        # 'STATE_RATIO' measures (Wrist X - Elbow X) / Shoulder Width. 
        # State 1 (Outward): Wrist is far outside the elbow.
        # State 3 (Inward): Wrist crosses the stomach toward the opposite shoulder.
        
        'ROTATION_RATIO': {
            'NORMAL': (-0.05, 1.0),   # S1: Wrist is outside
            'TRANS': (-0.25, -0.05),  # S2: Wrist is moving inward
            'PASS': (-1.0, -0.25)     # S3: Wrist has crossed the torso
        },
        
        # Form Failures (Fails the rep)
        'ELBOW_FLARE_THRESH': 0.4,  # Fails if elbow drifts outside shoulder width
        'WRIST_ALIGNMENT_THRESH': 0.22,  # Vertical distance between wrist and elbow (raised from 0.15)
        
        # Form Cautions (Yellow warnings)
        'TORSO_TWIST_THRESH': 0.85,      # Drop in visible shoulder width
        
        'INACTIVE_THRESH': 15.0
    }




