import time
import cv2
import numpy as np
import json
from helpers.utils import find_angle, get_landmark_features, draw_text, draw_text_arabic

class ProcessFrameInternalRotation:
    def __init__(self, thresholds, flip_frame=False, reps_per_set=10, target_sets=3, rest_time=30, language='en'):
        self.flip_frame = flip_frame
        self.thresholds = thresholds
        self.reps_per_set = reps_per_set
        self.target_sets = target_sets
        self.rest_time = rest_time
        self.language = language

        self.font = cv2.FONT_HERSHEY_SIMPLEX
        self.linetype = cv2.LINE_AA

        self.COLORS = {
            'blue': (0, 127, 255),
            'red': (255, 50, 50),
            'green': (0, 255, 127),
            'light_green': (100, 233, 127),
            'yellow': (255, 255, 0),
            'magenta': (255, 0, 255),
            'white': (255, 255, 255),
            'light_blue': (102, 204, 255)
        }

        self.dict_features = {
            'left': {'shoulder': 11, 'elbow': 13, 'wrist': 15, 'hip': 23, 'knee': 25, 'ankle': 27, 'foot': 31},
            'right': {'shoulder': 12, 'elbow': 14, 'wrist': 16, 'hip': 24, 'knee': 26, 'ankle': 28, 'foot': 32},
            'nose': 0
        }

        self.state_tracker = {
            'state_seq': [],
            'start_inactive_time': time.perf_counter(),
            'INACTIVE_TIME': 0.0,
            'DISPLAY_TEXT': np.full((3,), False),
            'COUNT_FRAMES': np.zeros((3,), dtype=np.int64),
            'INCORRECT_POSTURE': False,
            'prev_state': None,
            'curr_state': None,
            'REP_COUNT': 0,
            'IMPROPER_REP': 0,
            'SET_COUNT': 0,
            'EFFECTIVE_SET_COUNT': 0, 
            'DISPLAY_MESSAGE': None,     
            'WAITING_FOR_RESET': False,
            'REST_START_TIME': None,     # Timer for resting between sets
            'BASE_SHOULDER_WIDTH': None, 
            'ACTIVE_ARM': None,          # Arm Lock
            'ROM_WARNING_TIMER': 0,      # Timer for Half-Rep warnings
            'IS_INITIALIZING': True,
            # --- NEW: SESSION TRACKERS FOR JSON EXPORT ---
            'SESSION_CORRECT_REPS': 0,
            'SESSION_IMPROPER_REPS': 0,
            'SESSION_ERRORS': set(), # We use a 'set' so it only logs unique errors, not duplicates
            'JSON_SAVED': False,     # Ensures we only write the file once
            'SPOKEN_FEEDBACK': set()
        }
        
        self.FEEDBACK_ID_MAP = {
            0: ('ELBOW LEFT YOUR SIDE', 215, (255, 80, 80)),      # RED
            1: ('KEEP FOREARM LEVEL', 170, (255, 80, 80)),        # RED
            2: ('DON\'T TWIST TORSO', 125, (0, 255, 255))         # YELLOW
        }
        self.FEEDBACK_SOUND_MAP = {
            0: 'elbow_left_side',
            1: 'keep_forearm_level',
            2: 'dont_twist_torso',
        }
        self.FEEDBACK_AR_MAP = {
            0: 'الكوع بعيد عن جانبك',
            1: 'حافظ على ساعدك أفقياً',
            2: 'لا تلوي جذعك',
        }

    def _get_state(self, rotation_ratio):
        state = None        
        if self.thresholds['ROTATION_RATIO']['NORMAL'][0] <= rotation_ratio <= self.thresholds['ROTATION_RATIO']['NORMAL'][1]:
            state = 1
        elif self.thresholds['ROTATION_RATIO']['TRANS'][0] <= rotation_ratio <= self.thresholds['ROTATION_RATIO']['TRANS'][1]:
            state = 2
        elif self.thresholds['ROTATION_RATIO']['PASS'][0] <= rotation_ratio <= self.thresholds['ROTATION_RATIO']['PASS'][1]:
            state = 3
        return f's{state}' if state else None

    def _update_state_sequence(self, state):
        if state == 's2':
            if (('s3' not in self.state_tracker['state_seq']) and (self.state_tracker['state_seq'].count('s2'))==0) or \
               (('s3' in self.state_tracker['state_seq']) and (self.state_tracker['state_seq'].count('s2')==1)):
                self.state_tracker['state_seq'].append(state)
        elif state == 's3':
            if (state not in self.state_tracker['state_seq']) and 's2' in self.state_tracker['state_seq']: 
                self.state_tracker['state_seq'].append(state)

    def _show_feedback(self, frame, c_frame, dict_maps):
        right_x = max(30, frame.shape[1] - 280)
        for idx in np.where(c_frame)[0]:
            y = dict_maps[idx][1]
            color = dict_maps[idx][2]
            if self.language in ('en', 'both'):
                draw_text(frame, dict_maps[idx][0], pos=(30, y),
                          text_color=(255, 255, 230), font_scale=0.6, text_color_bg=color)
            if self.language in ('ar', 'both'):
                x = right_x if self.language == 'both' else 30
                draw_text_arabic(frame, self.FEEDBACK_AR_MAP[idx], pos=(x, y),
                                 font_scale=0.6, text_color=(255, 255, 230), bg_color=color)
        return frame

    def process(self, frame: np.array, pose):
        play_sound = None
        frame_height, frame_width, _ = frame.shape

        # --- 1. THE "KILL SWITCH" FOR COMPLETED TRAINING ---
        if self.state_tracker['SET_COUNT'] >= self.target_sets:
            
            # --- NEW: EXPORT THE JSON LOG ---
            if not self.state_tracker.get('JSON_SAVED', False):
                log_data = {
                    "exercise": "Shoulder Internal Rotation",
                    "total_sets_completed": self.target_sets,
                    "effective_sets": self.state_tracker['EFFECTIVE_SET_COUNT'],
                    "total_correct_reps": self.state_tracker['SESSION_CORRECT_REPS'],
                    "total_incorrect_reps": self.state_tracker['SESSION_IMPROPER_REPS'],
                    "errors_triggered": list(self.state_tracker['SESSION_ERRORS'])
                }
                
                # Save the file (you can change this path to match where your videos save!)
                with open("workout_log.json", "w") as f:
                    json.dump(log_data, f, indent=4)
                    
                self.state_tracker['JSON_SAVED'] = True
                print("Workout JSON successfully exported!")
            # --------------------------------
            
            if self.flip_frame:
                frame = cv2.flip(frame, 1)

            draw_text(frame, f"SET: {self.target_sets} / {self.target_sets}", pos=(int(frame_width*0.70), 30), text_color=(255, 255, 255), font_scale=0.7, text_color_bg=(50, 50, 50))  
            draw_text(frame, f"EFF SETS: {self.state_tracker['EFFECTIVE_SET_COUNT']}", pos=(int(frame_width*0.70), 80), text_color=(255, 255, 255), font_scale=0.7, text_color_bg=(153, 50, 204)) 
            
            message = "TRAINING COMPLETED!"
            text_size = cv2.getTextSize(message, self.font, 1.5, 3)[0]
            text_x = (frame_width - text_size[0]) // 2
            text_y = (frame_height + text_size[1]) // 2
            cv2.rectangle(frame, (text_x - 20, text_y - text_size[1] - 20), (text_x + text_size[0] + 20, text_y + 20), (50, 205, 50), -1)
            cv2.putText(frame, message, (text_x, text_y), self.font, 1.5, (255, 255, 255), 3, self.linetype)
            
            return frame, None # Bypasses AI Tracking

# --- 2. THE REST TIMER & AI PAUSE ---
        if self.state_tracker['WAITING_FOR_RESET']:
            elapsed_time = time.time() - self.state_tracker['REST_START_TIME']

            # --- THE CELEBRATION TIMER (Final Set Only) ---
            if self.state_tracker.get('IS_FINAL_SET', False):
                time_left = 3.5 - elapsed_time
                disp = cv2.flip(frame, 1) if self.flip_frame else frame
                if time_left > 0:
                    message = self.state_tracker['DISPLAY_MESSAGE']
                    text_size = cv2.getTextSize(message, self.font, 1.0, 2)[0]
                    text_x = (frame_width - text_size[0]) // 2
                    text_y = (frame_height // 2) - 50
                    cv2.rectangle(disp, (text_x - 20, text_y - text_size[1] - 20), (text_x + text_size[0] + 20, text_y + 20), (255, 153, 51), -1)
                    cv2.putText(disp, message, (text_x, text_y), self.font, 1.0, (255, 255, 255), 2, self.linetype)
                    return disp, None
                else:
                    self.state_tracker['SET_COUNT'] += 1
                    self.state_tracker['WAITING_FOR_RESET'] = False
                    return disp, None

            # --- STANDARD REST TIMER (Between Sets) ---
            time_left = self.rest_time - elapsed_time

            if time_left > 0:
                disp = cv2.flip(frame, 1) if self.flip_frame else frame
                message = self.state_tracker['DISPLAY_MESSAGE']
                text_size = cv2.getTextSize(message, self.font, 1.0, 2)[0]
                text_x = (frame_width - text_size[0]) // 2
                text_y = (frame_height // 2) - 50
                cv2.rectangle(disp, (text_x - 20, text_y - text_size[1] - 20), (text_x + text_size[0] + 20, text_y + 20), (255, 153, 51), -1)
                cv2.putText(disp, message, (text_x, text_y), self.font, 1.0, (255, 255, 255), 2, self.linetype)
                countdown_msg = f"REST: {int(time_left) + 1}s"
                count_size = cv2.getTextSize(countdown_msg, self.font, 2.0, 4)[0]
                count_x = (frame_width - count_size[0]) // 2
                cv2.putText(disp, countdown_msg, (count_x, text_y + 80), self.font, 2.0, (0, 255, 255), 4, self.linetype)
                return disp, None
            else:
                # Timer done — reset and fall through with unflipped frame
                self.state_tracker['WAITING_FOR_RESET'] = False
                self.state_tracker['REST_START_TIME'] = None
                self.state_tracker['REP_COUNT'] = 0
                self.state_tracker['IMPROPER_REP'] = 0
                self.state_tracker['SET_COUNT'] += 1
                self.state_tracker['ACTIVE_ARM'] = None
                self.state_tracker['state_seq'] = []
                self.state_tracker['ROM_WARNING_TIMER'] = 0
                self.state_tracker['IS_INITIALIZING'] = True
                self.state_tracker['SPOKEN_FEEDBACK'] = set()
                play_sound = 'reset_counters'


        # --- 3. MEDIAPIPE TRACKING ---
        keypoints = pose.process(frame)

        if keypoints.pose_landmarks:
            ps_lm = keypoints.pose_landmarks

            left_shldr, left_elbow, left_wrist, left_hip, _, _, _ = get_landmark_features(ps_lm.landmark, self.dict_features, 'left', frame_width, frame_height)
            right_shldr, right_elbow, right_wrist, right_hip, _, _, _ = get_landmark_features(ps_lm.landmark, self.dict_features, 'right', frame_width, frame_height)

            # Draw skeletons
            cv2.line(frame, tuple(left_shldr), tuple(right_shldr), self.COLORS['light_blue'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(left_shldr), tuple(left_hip), self.COLORS['light_blue'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(right_shldr), tuple(right_hip), self.COLORS['light_blue'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(left_hip), tuple(right_hip), self.COLORS['light_blue'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(left_shldr), tuple(left_elbow), self.COLORS['white'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(left_elbow), tuple(left_wrist), self.COLORS['white'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(right_shldr), tuple(right_elbow), self.COLORS['white'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(right_elbow), tuple(right_wrist), self.COLORS['white'], 4, lineType=self.linetype)
            
            for coord in [left_shldr, right_shldr, left_elbow, right_elbow, left_wrist, right_wrist, left_hip, right_hip]:
                cv2.circle(frame, tuple(coord), 7, self.COLORS['yellow'], -1, lineType=self.linetype)

            # Feature Calculations
            shoulder_width = abs(right_shldr[0] - left_shldr[0])
            if shoulder_width == 0: shoulder_width = 1 
            
            # Calibrate base shoulder width for torso twist detection
            if self.state_tracker['BASE_SHOULDER_WIDTH'] is None or self.state_tracker['curr_state'] == 's1':
                self.state_tracker['BASE_SHOULDER_WIDTH'] = shoulder_width

            left_elbow_angle = find_angle(left_shldr, left_wrist, left_elbow)
            right_elbow_angle = find_angle(right_shldr, right_wrist, right_elbow)
            
            # --- ARM LOCK LOGIC ---
            if self.state_tracker.get('ACTIVE_ARM') is None:
                if abs(90 - left_elbow_angle) < abs(90 - right_elbow_angle):
                    self.state_tracker['ACTIVE_ARM'] = 'left'
                else:
                    self.state_tracker['ACTIVE_ARM'] = 'right'

            if self.state_tracker['ACTIVE_ARM'] == 'left':
                active_wrist = left_wrist
                active_elbow = left_elbow
                active_shldr = left_shldr 
                elbow_flare_ratio = (active_elbow[0] - active_shldr[0]) / shoulder_width 
                rotation_ratio = (active_wrist[0] - active_elbow[0]) / shoulder_width 
            else:
                active_wrist = right_wrist
                active_elbow = right_elbow
                active_shldr = right_shldr 
                elbow_flare_ratio = (active_shldr[0] - active_elbow[0]) / shoulder_width
                rotation_ratio = (active_elbow[0] - active_wrist[0]) / shoulder_width

            current_state = self._get_state(rotation_ratio)
            self.state_tracker['curr_state'] = current_state
            self._update_state_sequence(current_state)

            # --- Feedback Checks ---
            # 1. Elbow Flare
            if elbow_flare_ratio > self.thresholds['ELBOW_FLARE_THRESH']:
                self.state_tracker['DISPLAY_TEXT'][0] = True
                self.state_tracker['SESSION_ERRORS'].add(self.FEEDBACK_ID_MAP[0][0])
                if current_state != 's1':  # don't fail a rep based on s1 rest posture
                    self.state_tracker['INCORRECT_POSTURE'] = True

            # 2. Wrist Alignment (90 Degree bend)
            wrist_y_diff = abs(active_elbow[1] - active_wrist[1]) / frame_height
            if wrist_y_diff > self.thresholds['WRIST_ALIGNMENT_THRESH']:
                self.state_tracker['DISPLAY_TEXT'][1] = True
                self.state_tracker['SESSION_ERRORS'].add(self.FEEDBACK_ID_MAP[1][0])
                if current_state != 's1':  # don't fail a rep based on s1 rest posture
                    self.state_tracker['INCORRECT_POSTURE'] = True
                
            # 3. Torso Twist
            width_ratio = shoulder_width / self.state_tracker['BASE_SHOULDER_WIDTH']
            if width_ratio < self.thresholds['TORSO_TWIST_THRESH']:
                self.state_tracker['DISPLAY_TEXT'][2] = True
                self.state_tracker['SESSION_ERRORS'].add(self.FEEDBACK_ID_MAP[2][0])

            if play_sound is None:
                for idx in range(len(self.state_tracker['DISPLAY_TEXT'])):
                    if self.state_tracker['DISPLAY_TEXT'][idx] and idx not in self.state_tracker['SPOKEN_FEEDBACK']:
                        play_sound = self.FEEDBACK_SOUND_MAP[idx]
                        self.state_tracker['SPOKEN_FEEDBACK'].add(idx)
                        break

            # --- NEW: THE GRACE PERIOD SHIELD ---
            # If the user is just getting into position, do not log their movements as a rep!
            if self.state_tracker.get('IS_INITIALIZING', False):
                if current_state == 's1':
                    self.state_tracker['IS_INITIALIZING'] = False
                self.state_tracker['state_seq'] = []
                self.state_tracker['INCORRECT_POSTURE'] = False
                self.state_tracker['SPOKEN_FEEDBACK'] = set()
            # ------------------------------------

# --- Rep Counting Logic ---
            if current_state == 's1':
                if len(self.state_tracker['state_seq']) == 3 and not self.state_tracker['INCORRECT_POSTURE']:
                    self.state_tracker['REP_COUNT'] += 1
                    self.state_tracker['SESSION_CORRECT_REPS'] += 1  # <--- LOG SESSION CORRECT
                    play_sound = str(self.state_tracker['REP_COUNT'])
                    
                    # Moved inside the evaluation blocks!
                    self.state_tracker['state_seq'] = []
                    self.state_tracker['INCORRECT_POSTURE'] = False
                    self.state_tracker['SPOKEN_FEEDBACK'] = set()
                
                elif 's2' in self.state_tracker['state_seq'] and len(self.state_tracker['state_seq']) == 1:
                    self.state_tracker['IMPROPER_REP'] += 1
                    self.state_tracker['SESSION_IMPROPER_REPS'] += 1 # <--- LOG SESSION INCORRECT
                    self.state_tracker['ROM_WARNING_TIMER'] = 45 
                    self.state_tracker['SESSION_ERRORS'].add('INCOMPLETE ROM') # <--- LOG ROM ERROR
                    play_sound = 'incorrect'
                    
                    # Moved inside the evaluation blocks!
                    self.state_tracker['state_seq'] = []
                    self.state_tracker['INCORRECT_POSTURE'] = False
                    self.state_tracker['SPOKEN_FEEDBACK'] = set()
                    
                elif self.state_tracker['INCORRECT_POSTURE'] and len(self.state_tracker['state_seq']) > 0:
                    self.state_tracker['IMPROPER_REP'] += 1
                    self.state_tracker['SESSION_IMPROPER_REPS'] += 1 # <--- LOG SESSION INCORRECT
                    play_sound = 'incorrect'
                    
                    # Moved inside the evaluation blocks!
                    self.state_tracker['state_seq'] = []
                    self.state_tracker['INCORRECT_POSTURE'] = False
                    self.state_tracker['SPOKEN_FEEDBACK'] = set()
                
                total_reps = self.state_tracker['REP_COUNT'] + self.state_tracker['IMPROPER_REP']
                if total_reps >= self.reps_per_set:
                    self.state_tracker['WAITING_FOR_RESET'] = True
                    self.state_tracker['REST_START_TIME'] = time.time() # Start the rest timer
                    
                    # Effective Set Logic
                    accuracy = 0
                    if total_reps > 0:
                        accuracy = self.state_tracker['REP_COUNT'] / total_reps

                    if accuracy >= 0.70:
                        self.state_tracker['EFFECTIVE_SET_COUNT'] += 1
                        feedback_prefix = "Excellent form!"
                    elif accuracy >= 0.40:
                        feedback_prefix = "Good effort, focus on your form."
                    else:
                        feedback_prefix = "Tough set! Keep your elbow tucked."

                    if (self.state_tracker['SET_COUNT'] + 1) >= self.target_sets:
                        self.state_tracker['DISPLAY_MESSAGE'] = f"{feedback_prefix} Training Complete!"
                        
                        # --- NEW: Flag it as the final set, but DO NOT instantly end it! ---
                        self.state_tracker['IS_FINAL_SET'] = True 
                        # -------------------------------------------------------------------
                        
                    else:
                        self.state_tracker['DISPLAY_MESSAGE'] = f"{feedback_prefix} Set {self.state_tracker['SET_COUNT'] + 1} Done"
                        self.state_tracker['IS_FINAL_SET'] = False

            # Inactivity check
            display_inactivity = False
            if self.state_tracker['curr_state'] == self.state_tracker['prev_state']:
                end_time = time.perf_counter()
                self.state_tracker['INACTIVE_TIME'] += end_time - self.state_tracker['start_inactive_time']
                self.state_tracker['start_inactive_time'] = end_time 

                if self.state_tracker['INACTIVE_TIME'] >= self.thresholds['INACTIVE_THRESH']:
                    self.state_tracker['REP_COUNT'] = 0
                    self.state_tracker['IMPROPER_REP'] = 0
                    self.state_tracker['ACTIVE_ARM'] = None 
                    display_inactivity = True
            else:
                self.state_tracker['start_inactive_time'] = time.perf_counter()
                self.state_tracker['INACTIVE_TIME'] = 0.0

            if self.flip_frame:
                frame = cv2.flip(frame, 1)

            self.state_tracker['COUNT_FRAMES'][self.state_tracker['DISPLAY_TEXT']] += 1
            frame = self._show_feedback(frame, self.state_tracker['COUNT_FRAMES'], self.FEEDBACK_ID_MAP)
            
            # --- NEW: Draw the Range of Motion Warning ---
            if self.state_tracker.get('ROM_WARNING_TIMER', 0) > 0:
                draw_text(frame, "INCOMPLETE RANGE OF MOTION", pos=(30, 260), text_color=(255, 255, 230), font_scale=0.6, text_color_bg=(255, 80, 80))
                self.state_tracker['ROM_WARNING_TIMER'] -= 1

            if display_inactivity:
                play_sound = 'reset_counters'
                self.state_tracker['start_inactive_time'] = time.perf_counter()
                self.state_tracker['INACTIVE_TIME'] = 0.0

            # UI text
            draw_text(frame, f"SET: {self.state_tracker['SET_COUNT']} / {self.target_sets}", pos=(int(frame_width*0.70), 30), text_color=(255, 255, 255), font_scale=0.7, text_color_bg=(50, 50, 50))  
            draw_text(frame, f"EFF SETS: {self.state_tracker['EFFECTIVE_SET_COUNT']}", pos=(int(frame_width*0.70), 80), text_color=(255, 255, 255), font_scale=0.7, text_color_bg=(153, 50, 204)) 
            draw_text(frame, "CORRECT: " + str(self.state_tracker['REP_COUNT']), pos=(int(frame_width*0.70), 130), text_color=(255, 255, 230), font_scale=0.7, text_color_bg=(18, 185, 0))  
            draw_text(frame, "INCORRECT: " + str(self.state_tracker['IMPROPER_REP']), pos=(int(frame_width*0.70), 180), text_color=(255, 255, 230), font_scale=0.7, text_color_bg=(221, 0, 0))  


            self.state_tracker['DISPLAY_TEXT'] = np.full((3,), False)
            self.state_tracker['COUNT_FRAMES'] = np.zeros((3,), dtype=np.int64)

            if self.state_tracker['curr_state']:
                 self.state_tracker['prev_state'] = self.state_tracker['curr_state']

        return frame, play_sound