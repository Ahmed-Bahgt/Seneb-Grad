import time
import cv2
import numpy as np
import json
from helpers.utils import find_angle, get_landmark_features, draw_text, draw_text_arabic

class ProcessFrameAbduction:
    # --- ADDED rest_time argument ---
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
            'DISPLAY_TEXT': np.full((4,), False),
            'COUNT_FRAMES': np.zeros((4,), dtype=np.int64),
            'INCORRECT_POSTURE': False,
            'prev_state': None,
            'curr_state': None,
            'REP_COUNT': 0,
            'IMPROPER_REP': 0,
            'SET_COUNT': 0,
            'EFFECTIVE_SET_COUNT': 0, 
            'DISPLAY_MESSAGE': None,     
            'WAITING_FOR_RESET': False, 
            'REST_START_TIME': None,      # <--- Rest Timer logic
            'IS_FINAL_SET': False,        # <--- Celebration Timer flag
            'IS_INITIALIZING': True,      # <--- Grace Period Shield
            'ROM_WARNING_TIMER': 0,
            # --- NEW: SESSION TRACKERS FOR JSON EXPORT ---
            'SESSION_CORRECT_REPS': 0,
            'SESSION_IMPROPER_REPS': 0,
            'SESSION_ERRORS': set(), # We use a 'set' so it only logs unique errors, not duplicates
            'JSON_SAVED': False,     # Ensures we only write the file once
            'SPOKEN_FEEDBACK': set()
        }
        
        self.FEEDBACK_ID_MAP = {
            0: ('ARMS TOO HIGH', 215, (255, 80, 80)),           # RED (Fails the rep)
            1: ('KEEP ARMS STRAIGHT', 170, (0, 255, 255)),      # YELLOW CAUTION
            2: ('EVEN YOUR ARMS (LEVEL THEM)', 125, (0, 255, 255)),# YELLOW CAUTION
            3: ('DON\'T SWAY YOUR BACK', 80, (0, 255, 255))     # YELLOW CAUTION
        }
        self.FEEDBACK_SOUND_MAP = {
            0: 'arms_too_high',
            1: 'keep_arms_straight',
            2: 'level_arms',
            3: 'dont_sway_back',
        }
        self.FEEDBACK_AR_MAP = {
            0: 'ذراعاك مرتفعتان جداً',
            1: 'حافظ على استقامة ذراعيك',
            2: 'سوِّ ذراعيك',
            3: 'لا تهتز بظهرك',
        }

    def _get_state(self, shoulder_angle):
        state = None        
        if self.thresholds['SHOULDER_ABDUCTION']['NORMAL'][0] <= shoulder_angle <= self.thresholds['SHOULDER_ABDUCTION']['NORMAL'][1]:
            state = 1
        elif self.thresholds['SHOULDER_ABDUCTION']['TRANS'][0] <= shoulder_angle <= self.thresholds['SHOULDER_ABDUCTION']['TRANS'][1]:
            state = 2
        elif self.thresholds['SHOULDER_ABDUCTION']['PASS'][0] <= shoulder_angle <= self.thresholds['SHOULDER_ABDUCTION']['PASS'][1]:
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
                    "exercise": "Shoulder Abduction",
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
            
            return frame, None

        # --- 2. THE REST TIMER & CELEBRATION PAUSE ---
        if self.state_tracker['WAITING_FOR_RESET']:
            elapsed_time = time.time() - self.state_tracker['REST_START_TIME']

            # --- CELEBRATION TIMER (Final Set Only) ---
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
                self.state_tracker['state_seq'] = []
                self.state_tracker['ROM_WARNING_TIMER'] = 0
                self.state_tracker['IS_INITIALIZING'] = True
                self.state_tracker['SPOKEN_FEEDBACK'] = set()
                play_sound = 'reset_counters'


        # --- 3. MEDIAPIPE TRACKING ---
        keypoints = pose.process(frame)

        if keypoints.pose_landmarks:
            ps_lm = keypoints.pose_landmarks

            left_shldr_coord, left_elbow_coord, left_wrist_coord, left_hip_coord, _, _, _ = get_landmark_features(ps_lm.landmark, self.dict_features, 'left', frame_width, frame_height)
            right_shldr_coord, right_elbow_coord, right_wrist_coord, right_hip_coord, _, _, _ = get_landmark_features(ps_lm.landmark, self.dict_features, 'right', frame_width, frame_height)

            left_shoulder_angle = find_angle(left_hip_coord, left_shldr_coord, left_elbow_coord)
            left_elbow_angle = find_angle(left_shldr_coord, left_wrist_coord, left_elbow_coord)

            right_shoulder_angle = find_angle(right_hip_coord, right_shldr_coord, right_elbow_coord)
            right_elbow_angle = find_angle(right_shldr_coord, right_wrist_coord, right_elbow_coord)

            mid_shoulder = np.array([int((left_shldr_coord[0] + right_shldr_coord[0]) / 2), int((left_shldr_coord[1] + right_shldr_coord[1]) / 2)])
            mid_hip = np.array([int((left_hip_coord[0] + right_hip_coord[0]) / 2), int((left_hip_coord[1] + right_hip_coord[1]) / 2)])
            torso_vertical_angle = find_angle(mid_shoulder, np.array([mid_hip[0], 0]), mid_hip)

            avg_shoulder_angle = (left_shoulder_angle + right_shoulder_angle) / 2

            # Draw skeletons 
            cv2.line(frame, tuple(left_shldr_coord), tuple(right_shldr_coord), self.COLORS['light_blue'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(left_shldr_coord), tuple(left_hip_coord), self.COLORS['light_blue'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(right_shldr_coord), tuple(right_hip_coord), self.COLORS['light_blue'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(left_hip_coord), tuple(right_hip_coord), self.COLORS['light_blue'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(mid_shoulder), tuple(mid_hip), self.COLORS['magenta'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(left_shldr_coord), tuple(left_elbow_coord), self.COLORS['white'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(left_elbow_coord), tuple(left_wrist_coord), self.COLORS['white'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(right_shldr_coord), tuple(right_elbow_coord), self.COLORS['white'], 4, lineType=self.linetype)
            cv2.line(frame, tuple(right_elbow_coord), tuple(right_wrist_coord), self.COLORS['white'], 4, lineType=self.linetype)
            
            for coord in [left_shldr_coord, right_shldr_coord, left_elbow_coord, right_elbow_coord, left_wrist_coord, right_wrist_coord, left_hip_coord, right_hip_coord, mid_shoulder, mid_hip]:
                cv2.circle(frame, tuple(coord), 7, self.COLORS['yellow'], -1, lineType=self.linetype)

            current_state = self._get_state(int(avg_shoulder_angle))
            self.state_tracker['curr_state'] = current_state
            self._update_state_sequence(current_state)

            # Feedback Checks
            if left_shoulder_angle > self.thresholds['ARMS_TOO_HIGH'] or right_shoulder_angle > self.thresholds['ARMS_TOO_HIGH']:
                self.state_tracker['DISPLAY_TEXT'][0] = True
                self.state_tracker['INCORRECT_POSTURE'] = True
                self.state_tracker['SESSION_ERRORS'].add(self.FEEDBACK_ID_MAP[0][0])
            
            if left_elbow_angle < self.thresholds['ELBOW_BENT_THRESH'] or right_elbow_angle < self.thresholds['ELBOW_BENT_THRESH']:
                self.state_tracker['DISPLAY_TEXT'][1] = True
                self.state_tracker['SESSION_ERRORS'].add(self.FEEDBACK_ID_MAP[1][0])
                
            if abs(left_shoulder_angle - right_shoulder_angle) > self.thresholds['ASYMMETRY_THRESH']:
                self.state_tracker['DISPLAY_TEXT'][2] = True
                self.state_tracker['SESSION_ERRORS'].add(self.FEEDBACK_ID_MAP[2][0])

            if torso_vertical_angle > self.thresholds['BACK_THRESH']:
                self.state_tracker['DISPLAY_TEXT'][3] = True
                self.state_tracker['SESSION_ERRORS'].add(self.FEEDBACK_ID_MAP[3][0])

            if play_sound is None:
                for idx in range(len(self.state_tracker['DISPLAY_TEXT'])):
                    if self.state_tracker['DISPLAY_TEXT'][idx] and idx not in self.state_tracker['SPOKEN_FEEDBACK']:
                        play_sound = self.FEEDBACK_SOUND_MAP[idx]
                        self.state_tracker['SPOKEN_FEEDBACK'].add(idx)
                        break

            # --- THE GRACE PERIOD SHIELD ---
            if self.state_tracker.get('IS_INITIALIZING', False):
                if current_state == 's1':
                    self.state_tracker['IS_INITIALIZING'] = False
                self.state_tracker['state_seq'] = []
                self.state_tracker['INCORRECT_POSTURE'] = False
                self.state_tracker['SPOKEN_FEEDBACK'] = set()
            # -------------------------------

            # --- Rep Counting Logic ---
            if not self.state_tracker['WAITING_FOR_RESET']:
                if current_state == 's1':
                    if len(self.state_tracker['state_seq']) == 3 and not self.state_tracker['INCORRECT_POSTURE']:
                        self.state_tracker['REP_COUNT'] += 1
                        self.state_tracker['SESSION_CORRECT_REPS'] += 1  # <--- LOG SESSION CORRECT
                        play_sound = str(self.state_tracker['REP_COUNT'])
                        
                    elif 's2' in self.state_tracker['state_seq'] and len(self.state_tracker['state_seq']) == 1:
                        self.state_tracker['IMPROPER_REP'] += 1
                        self.state_tracker['SESSION_IMPROPER_REPS'] += 1 # <--- LOG SESSION INCORRECT
                        self.state_tracker['ROM_WARNING_TIMER'] = 45
                        self.state_tracker['SESSION_ERRORS'].add('INCOMPLETE ROM') # <--- LOG ROM ERROR
                        play_sound = 'incorrect'
                        
                    elif self.state_tracker['INCORRECT_POSTURE'] and len(self.state_tracker['state_seq']) > 0:
                        self.state_tracker['IMPROPER_REP'] += 1
                        self.state_tracker['SESSION_IMPROPER_REPS'] += 1 # <--- LOG SESSION INCORRECT
                        play_sound = 'incorrect'
                    
                    # Array clears ONLY after grading the rep
                    self.state_tracker['state_seq'] = []
                    self.state_tracker['INCORRECT_POSTURE'] = False
                    self.state_tracker['SPOKEN_FEEDBACK'] = set()
                    
                    total_reps = self.state_tracker['REP_COUNT'] + self.state_tracker['IMPROPER_REP']
                    if total_reps >= self.reps_per_set:
                        self.state_tracker['WAITING_FOR_RESET'] = True
                        self.state_tracker['REST_START_TIME'] = time.time() # Start clock
                        
                        accuracy = 0
                        if total_reps > 0:
                            accuracy = self.state_tracker['REP_COUNT'] / total_reps

                        if accuracy >= 0.70:
                            self.state_tracker['EFFECTIVE_SET_COUNT'] += 1
                            feedback_prefix = "Excellent form!"
                        elif accuracy >= 0.40:
                            feedback_prefix = "Good effort, focus on your form."
                        else:
                            feedback_prefix = "Tough set! Try lowering the resistance."

                        if (self.state_tracker['SET_COUNT'] + 1) >= self.target_sets:
                            self.state_tracker['DISPLAY_MESSAGE'] = f"{feedback_prefix} Training Complete!"
                            self.state_tracker['IS_FINAL_SET'] = True
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
                    display_inactivity = True
            else:
                self.state_tracker['start_inactive_time'] = time.perf_counter()
                self.state_tracker['INACTIVE_TIME'] = 0.0

            if self.flip_frame:
                frame = cv2.flip(frame, 1)
                left_text_x = frame_width - left_shldr_coord[0] - 50
                right_text_x = frame_width - right_shldr_coord[0] + 10
            else:
                left_text_x = left_shldr_coord[0] + 10
                right_text_x = right_shldr_coord[0] - 50

            self.state_tracker['COUNT_FRAMES'][self.state_tracker['DISPLAY_TEXT']] += 1
            frame = self._show_feedback(frame, self.state_tracker['COUNT_FRAMES'], self.FEEDBACK_ID_MAP)
            
            # --- Draw the Sequence Warning if the timer is active ---
            if self.state_tracker.get('ROM_WARNING_TIMER', 0) > 0:
                draw_text(frame, "INCOMPLETE ROM", pos=(30, 260), text_color=(255, 255, 230), font_scale=0.6, text_color_bg=(255, 80, 80))
                self.state_tracker['ROM_WARNING_TIMER'] -= 1
            # --------------------------------------------------------
            
            if display_inactivity:
                play_sound = 'reset_counters'
                self.state_tracker['start_inactive_time'] = time.perf_counter()
                self.state_tracker['INACTIVE_TIME'] = 0.0

            # UI text
            cv2.putText(frame, f"L: {int(left_shoulder_angle)}", (left_text_x, left_shldr_coord[1]-20), self.font, 0.6, self.COLORS['light_green'], 2, lineType=self.linetype)
            cv2.putText(frame, f"R: {int(right_shoulder_angle)}", (right_text_x, right_shldr_coord[1]-20), self.font, 0.6, self.COLORS['light_green'], 2, lineType=self.linetype)


            draw_text(frame, f"SET: {self.state_tracker['SET_COUNT']} / {self.target_sets}", pos=(int(frame_width*0.70), 30), text_color=(255, 255, 255), font_scale=0.7, text_color_bg=(50, 50, 50))  
            draw_text(frame, f"EFF SETS: {self.state_tracker['EFFECTIVE_SET_COUNT']}", pos=(int(frame_width*0.70), 80), text_color=(255, 255, 255), font_scale=0.7, text_color_bg=(153, 50, 204)) 
            draw_text(frame, "CORRECT: " + str(self.state_tracker['REP_COUNT']), pos=(int(frame_width*0.70), 130), text_color=(255, 255, 230), font_scale=0.7, text_color_bg=(18, 185, 0))  
            draw_text(frame, "INCORRECT: " + str(self.state_tracker['IMPROPER_REP']), pos=(int(frame_width*0.70), 180), text_color=(255, 255, 230), font_scale=0.7, text_color_bg=(221, 0, 0))  

            self.state_tracker['DISPLAY_TEXT'] = np.full((4,), False)
            self.state_tracker['COUNT_FRAMES'] = np.zeros((4,), dtype=np.int64)

            if self.state_tracker['curr_state']:
                 self.state_tracker['prev_state'] = self.state_tracker['curr_state']

        return frame, play_sound