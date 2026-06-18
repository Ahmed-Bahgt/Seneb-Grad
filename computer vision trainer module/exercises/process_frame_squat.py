import time
import cv2
import numpy as np
from helpers.utils import find_angle, get_landmark_features, draw_text, draw_text_arabic


class ProcessFrameSquat:
    def __init__(self, thresholds, flip_frame=False, reps_per_set=10, target_sets=3, rest_time=30, language='en'):

        self.flip_frame = flip_frame
        self.thresholds = thresholds
        self.reps_per_set = reps_per_set
        self.target_sets = target_sets
        self.rest_time = rest_time
        self.language = language

        self.font = cv2.FONT_HERSHEY_SIMPLEX
        self.linetype = cv2.LINE_AA
        self.radius = 20

        self.COLORS = {
                        'blue'       : (0, 127, 255),
                        'red'        : (255, 50, 50),
                        'green'      : (0, 255, 127),
                        'light_green': (100, 233, 127),
                        'yellow'     : (255, 255, 0),
                        'magenta'    : (255, 0, 255),
                        'white'      : (255,255,255),
                        'cyan'       : (0, 255, 255),
                        'light_blue' : (102, 204, 255)
                      }

        self.dict_features = {}
        self.left_features = {
                                'shoulder': 11,
                                'elbow'   : 13,
                                'wrist'   : 15,                    
                                'hip'     : 23,
                                'knee'    : 25,
                                'ankle'   : 27,
                                'foot'    : 31
                             }

        self.right_features = {
                                'shoulder': 12,
                                'elbow'   : 14,
                                'wrist'   : 16,
                                'hip'     : 24,
                                'knee'    : 26,
                                'ankle'   : 28,
                                'foot'    : 32
                              }

        self.dict_features['left'] = self.left_features
        self.dict_features['right'] = self.right_features
        self.dict_features['nose'] = 0

        self.state_tracker = {
            'state_seq': [],

            'start_inactive_time': time.perf_counter(),
            'start_inactive_time_front': time.perf_counter(),
            'INACTIVE_TIME': 0.0,
            'INACTIVE_TIME_FRONT': 0.0,

            # Flags to hold the display state. Size 5 covers indices 0-4 safely.
            'DISPLAY_TEXT' : np.full((5,), False),
            'COUNT_FRAMES' : np.zeros((5,), dtype=np.int64),

            'LOWER_HIPS': False,
            'INCORRECT_POSTURE': False,

            'prev_state': None,
            'curr_state':None,

            'SQUAT_COUNT': 0,
            'IMPROPER_SQUAT':0,
            
            'SET_COUNT': 0,
            'DISPLAY_MESSAGE': None,
            'REST_START_TIME': None,
            'WAITING_FOR_RESET': False,
            'ROM_WARNING_TIMER': 0,  # <--- Added for Range of Motion warnings
            'SPOKEN_FEEDBACK': set()
        }
        
        self.FEEDBACK_ID_MAP = {
                                0: ('BEND BACKWARDS', 215, (0, 153, 255)),
                                1: ('BEND FORWARD', 215, (0, 153, 255)),
                                2: ('KNEE FALLING OVER TOE', 170, (255, 80, 80)),
                                3: ('SQUAT TOO DEEP', 125, (255, 80, 80))
                               }
        self.FEEDBACK_SOUND_MAP = {
            0: 'bend_backwards',
            1: 'bend_forward',
            2: 'knee_over_toe',
            3: 'squat_too_deep',
        }
        self.FEEDBACK_AR_MAP = {
            0: 'انحنِ للخلف',
            1: 'انحنِ للأمام',
            2: 'الركبة تتجاوز إصبع القدم',
            3: 'الجلسة عميقة جداً',
        }


    def _get_state(self, knee_angle):
        knee = None        
        if self.thresholds['HIP_KNEE_VERT']['NORMAL'][0] <= knee_angle <= self.thresholds['HIP_KNEE_VERT']['NORMAL'][1]:
            knee = 1
        elif self.thresholds['HIP_KNEE_VERT']['TRANS'][0] <= knee_angle <= self.thresholds['HIP_KNEE_VERT']['TRANS'][1]:
            knee = 2
        elif self.thresholds['HIP_KNEE_VERT']['PASS'][0] <= knee_angle <= self.thresholds['HIP_KNEE_VERT']['PASS'][1]:
            knee = 3
        return f's{knee}' if knee else None


    def _update_state_sequence(self, state):
        if state == 's2':
            if (('s3' not in self.state_tracker['state_seq']) and (self.state_tracker['state_seq'].count('s2'))==0) or \
                    (('s3' in self.state_tracker['state_seq']) and (self.state_tracker['state_seq'].count('s2')==1)):
                        self.state_tracker['state_seq'].append(state)
        elif state == 's3':
            if (state not in self.state_tracker['state_seq']) and 's2' in self.state_tracker['state_seq']: 
                self.state_tracker['state_seq'].append(state)


    def _show_feedback(self, frame, c_frame, dict_maps, lower_hips_disp):
        right_x = max(30, frame.shape[1] - 280)
        if lower_hips_disp:
            if self.language in ('en', 'both'):
                draw_text(frame, 'LOWER YOUR HIPS', pos=(30, 80),
                          text_color=(0, 0, 0), font_scale=0.6, text_color_bg=(255, 255, 0))
            if self.language in ('ar', 'both'):
                x = right_x if self.language == 'both' else 30
                draw_text_arabic(frame, 'خفّض وركيك', pos=(x, 80),
                                 font_scale=0.6, text_color=(0, 0, 0), bg_color=(255, 255, 0))
        for idx in np.where(c_frame)[0]:
            if idx not in dict_maps:
                continue
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
        
        # --- NEW: THE "KILL SWITCH" FOR COMPLETED TRAINING ---
        if self.state_tracker['SET_COUNT'] >= self.target_sets:
            # 1. Flip the frame (so you aren't backward)
            if self.flip_frame:
                frame = cv2.flip(frame, 1)

            # 2. Draw your final score at the top right
            draw_text(frame, f"SET: {self.target_sets} / {self.target_sets}", pos=(int(frame_width*0.70), 30), text_color=(255, 255, 255), font_scale=0.7, text_color_bg=(50, 50, 50))  
            draw_text(frame, f"EFF SETS: {self.state_tracker['EFFECTIVE_SET_COUNT']}", pos=(int(frame_width*0.70), 80), text_color=(255, 255, 255), font_scale=0.7, text_color_bg=(153, 50, 204)) 
            
            # 3. Plaster a big "TRAINING COMPLETED!" message in the center of the screen
            message = "TRAINING COMPLETED!"
            text_size = cv2.getTextSize(message, self.font, 1.5, 3)[0]
            text_x = (frame_width - text_size[0]) // 2
            text_y = (frame_height + text_size[1]) // 2
            cv2.rectangle(frame, (text_x - 20, text_y - text_size[1] - 20), (text_x + text_size[0] + 20, text_y + 20), (50, 205, 50), -1)
            cv2.putText(frame, message, (text_x, text_y), self.font, 1.5, (255, 255, 255), 3, self.linetype)
            
            # 4. Return immediately! (Bypasses all the skeleton drawing and rep counting)
            return frame, None

        # ----------------------------------------------------------------------------------------------------
        # 5. HANDLE RESET FREEZE LOGIC (Global Timer)
        # ----------------------------------------------------------------------------------------------------
        if self.state_tracker['WAITING_FOR_RESET']:
            elapsed_time = time.perf_counter() - self.state_tracker['REST_START_TIME']
            time_left = self.rest_time - elapsed_time

            if time_left > 0:
                # Flip only for display — frame stays unflipped for pose below
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
                # Timer done — reset state and fall through to normal processing
                self.state_tracker['WAITING_FOR_RESET'] = False
                self.state_tracker['REST_START_TIME'] = None
                self.state_tracker['SQUAT_COUNT'] = 0
                self.state_tracker['IMPROPER_SQUAT'] = 0
                self.state_tracker['SET_COUNT'] += 1
                self.state_tracker['state_seq'] = []
                self.state_tracker['ROM_WARNING_TIMER'] = 0
                self.state_tracker['SPOKEN_FEEDBACK'] = set()
                play_sound = 'reset_counters'
        # ----------------------------------------------------------------------------------------------------

        keypoints = pose.process(frame)

        if keypoints.pose_landmarks:
            ps_lm = keypoints.pose_landmarks

            nose_coord = get_landmark_features(ps_lm.landmark, self.dict_features, 'nose', frame_width, frame_height)
            left_shldr_coord, left_elbow_coord, left_wrist_coord, left_hip_coord, left_knee_coord, left_ankle_coord, left_foot_coord = \
                                            get_landmark_features(ps_lm.landmark, self.dict_features, 'left', frame_width, frame_height)
            right_shldr_coord, right_elbow_coord, right_wrist_coord, right_hip_coord, right_knee_coord, right_ankle_coord, right_foot_coord = \
                                            get_landmark_features(ps_lm.landmark, self.dict_features, 'right', frame_width, frame_height)

            offset_angle = find_angle(left_shldr_coord, right_shldr_coord, nose_coord)

            # ----------------------------------------------------------------------------------------------------
            # BRANCH A: CAMERA NOT ALIGNED (User turning away or inactive)
            # ----------------------------------------------------------------------------------------------------
            if offset_angle > self.thresholds['OFFSET_THRESH']:
                
                # Inactivity Logic (Front View)
                display_inactivity = False
                end_time = time.perf_counter()
                self.state_tracker['INACTIVE_TIME_FRONT'] += end_time - self.state_tracker['start_inactive_time_front']
                self.state_tracker['start_inactive_time_front'] = end_time

                if self.state_tracker['INACTIVE_TIME_FRONT'] >= self.thresholds['INACTIVE_THRESH']:
                    self.state_tracker['SQUAT_COUNT'] = 0
                    self.state_tracker['IMPROPER_SQUAT'] = 0
                    display_inactivity = True
                
                # Visuals
                cv2.circle(frame, nose_coord, 7, self.COLORS['white'], -1)
                cv2.circle(frame, left_shldr_coord, 7, self.COLORS['yellow'], -1)
                cv2.circle(frame, right_shldr_coord, 7, self.COLORS['magenta'], -1)

                if self.flip_frame:
                    frame = cv2.flip(frame, 1)

                if display_inactivity:
                    play_sound = 'reset_counters'
                    self.state_tracker['INACTIVE_TIME_FRONT'] = 0.0
                    self.state_tracker['start_inactive_time_front'] = time.perf_counter()

                draw_text(frame, f"SET: {self.state_tracker['SET_COUNT']} / {self.target_sets}", pos=(int(frame_width*0.70), 30), text_color=(255, 255, 255), font_scale=0.7, text_color_bg=(50, 50, 50))  
                draw_text(frame, "CORRECT: " + str(self.state_tracker['SQUAT_COUNT']), pos=(int(frame_width*0.70), 80), text_color=(255, 255, 230), font_scale=0.7, text_color_bg=(18, 185, 0))  
                draw_text(frame, "INCORRECT: " + str(self.state_tracker['IMPROPER_SQUAT']), pos=(int(frame_width*0.70), 130), text_color=(255, 255, 230), font_scale=0.7, text_color_bg=(221, 0, 0))  
                
                draw_text(frame, 'POSTURE NOT ALIGNED PROPERLY!!! (TURN LEFT or RIGHT)', pos=(30, frame_height-60), text_color=(255, 255, 230), font_scale=0.65, text_color_bg=(255, 153, 0)) 
                
                # --- RESET LOGIC ---
                self.state_tracker['prev_state'] = None
                self.state_tracker['curr_state'] = None
                self.state_tracker['INCORRECT_POSTURE'] = False
                self.state_tracker['state_seq'] = []
                self.state_tracker['DISPLAY_TEXT'] = np.full((5,), False)
                self.state_tracker['COUNT_FRAMES'] = np.zeros((5,), dtype=np.int64)
                self.state_tracker['SPOKEN_FEEDBACK'] = set()
                self.state_tracker['start_inactive_time'] = time.perf_counter()

            # ----------------------------------------------------------------------------------------------------
            # BRANCH B: CAMERA ALIGNED (Active Training)
            # ----------------------------------------------------------------------------------------------------
            else:
                self.state_tracker['INACTIVE_TIME_FRONT'] = 0.0
                self.state_tracker['start_inactive_time_front'] = time.perf_counter()

                # --- 1. CALCULATE ANGLES AND DRAW SKELETON ---
                dist_l_sh_hip = abs(left_foot_coord[1]- left_shldr_coord[1])
                dist_r_sh_hip = abs(right_foot_coord[1] - right_shldr_coord)[1]

                if dist_l_sh_hip > dist_r_sh_hip:
                    shldr_coord, elbow_coord, wrist_coord, hip_coord, knee_coord, ankle_coord, foot_coord = \
                        left_shldr_coord, left_elbow_coord, left_wrist_coord, left_hip_coord, left_knee_coord, left_ankle_coord, left_foot_coord
                    multiplier = -1
                else:
                    shldr_coord, elbow_coord, wrist_coord, hip_coord, knee_coord, ankle_coord, foot_coord = \
                        right_shldr_coord, right_elbow_coord, right_wrist_coord, right_hip_coord, right_knee_coord, right_ankle_coord, right_foot_coord
                    multiplier = 1
                    
                hip_vertical_angle = find_angle(shldr_coord, np.array([hip_coord[0], 0]), hip_coord)
                cv2.ellipse(frame, hip_coord, (30, 30), angle = 0, startAngle = -90, endAngle = -90+multiplier*hip_vertical_angle, color = self.COLORS['white'], thickness = 3, lineType = self.linetype)
                cv2.line(frame, (hip_coord[0], hip_coord[1] + 20), (hip_coord[0], hip_coord[1] - 80), self.COLORS['blue'], 4, lineType=self.linetype)

                knee_vertical_angle = find_angle(hip_coord, np.array([knee_coord[0], 0]), knee_coord)
                cv2.ellipse(frame, knee_coord, (20, 20), angle = 0, startAngle = -90, endAngle = -90-multiplier*knee_vertical_angle, color = self.COLORS['white'], thickness = 3,  lineType = self.linetype)
                cv2.line(frame, (knee_coord[0], knee_coord[1] + 20), (knee_coord[0], knee_coord[1] - 50), self.COLORS['blue'], 4, lineType=self.linetype)

                ankle_vertical_angle = find_angle(knee_coord, np.array([ankle_coord[0], 0]), ankle_coord)
                cv2.ellipse(frame, ankle_coord, (30, 30), angle = 0, startAngle = -90, endAngle = -90 + multiplier*ankle_vertical_angle, color = self.COLORS['white'], thickness = 3,  lineType = self.linetype)
                cv2.line(frame, (ankle_coord[0], ankle_coord[1] + 20), (ankle_coord[0], ankle_coord[1] - 50), self.COLORS['blue'], 4, lineType=self.linetype)

                cv2.line(frame, shldr_coord, elbow_coord, self.COLORS['light_blue'], 4, lineType=self.linetype)
                cv2.line(frame, wrist_coord, elbow_coord, self.COLORS['light_blue'], 4, lineType=self.linetype)
                cv2.line(frame, shldr_coord, hip_coord, self.COLORS['light_blue'], 4, lineType=self.linetype)
                cv2.line(frame, knee_coord, hip_coord, self.COLORS['light_blue'], 4,  lineType=self.linetype)
                cv2.line(frame, ankle_coord, knee_coord,self.COLORS['light_blue'], 4,  lineType=self.linetype)
                cv2.line(frame, ankle_coord, foot_coord, self.COLORS['light_blue'], 4,  lineType=self.linetype)
                
                cv2.circle(frame, shldr_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                cv2.circle(frame, elbow_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                cv2.circle(frame, wrist_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                cv2.circle(frame, hip_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                cv2.circle(frame, knee_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                cv2.circle(frame, ankle_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)
                cv2.circle(frame, foot_coord, 7, self.COLORS['yellow'], -1,  lineType=self.linetype)

                # --- 2. UPDATE STATE ---
                current_state = self._get_state(int(knee_vertical_angle))
                self.state_tracker['curr_state'] = current_state
                self._update_state_sequence(current_state)

                # --- 3. CHECK FEEDBACK & POSTURE (Runs EVERY frame) ---
                if hip_vertical_angle > self.thresholds['HIP_THRESH'][1]:
                    self.state_tracker['DISPLAY_TEXT'][0] = True
                elif hip_vertical_angle < self.thresholds['HIP_THRESH'][0] and self.state_tracker['state_seq'].count('s2')==1:
                    self.state_tracker['DISPLAY_TEXT'][1] = True
                    
                if self.thresholds['KNEE_THRESH'][0] < knee_vertical_angle < self.thresholds['KNEE_THRESH'][1] and self.state_tracker['state_seq'].count('s2')==1:
                    self.state_tracker['LOWER_HIPS'] = True
                
                elif knee_vertical_angle > self.thresholds['KNEE_THRESH'][2]:
                    self.state_tracker['DISPLAY_TEXT'][3] = True
                    self.state_tracker['INCORRECT_POSTURE'] = True 
                    
                if (ankle_vertical_angle > self.thresholds['ANKLE_THRESH']):
                    self.state_tracker['DISPLAY_TEXT'][2] = True
                    self.state_tracker['INCORRECT_POSTURE'] = True

                if play_sound is None:
                    for idx in range(4):
                        if self.state_tracker['DISPLAY_TEXT'][idx] and idx not in self.state_tracker['SPOKEN_FEEDBACK']:
                            play_sound = self.FEEDBACK_SOUND_MAP[idx]
                            self.state_tracker['SPOKEN_FEEDBACK'].add(idx)
                            break

                # --- 4. COUNTING LOGIC (Only runs if active) ---
                if not self.state_tracker['WAITING_FOR_RESET']:
                    if current_state == 's1':
                        # Valid Rep?
                        if len(self.state_tracker['state_seq']) == 3 and not self.state_tracker['INCORRECT_POSTURE']:
                            self.state_tracker['SQUAT_COUNT']+=1
                            play_sound = str(self.state_tracker['SQUAT_COUNT'])
                            
                        # Invalid Rep cases
                        elif 's2' in self.state_tracker['state_seq'] and len(self.state_tracker['state_seq'])==1:
                            self.state_tracker['IMPROPER_SQUAT']+=1
                            self.state_tracker['ROM_WARNING_TIMER'] = 45
                            play_sound = 'incorrect'
                        elif self.state_tracker['INCORRECT_POSTURE']:
                            self.state_tracker['IMPROPER_SQUAT']+=1
                            play_sound = 'incorrect'
                        
                        # --- RESET ALL FLAGS for the NEXT REP ---
                        self.state_tracker['state_seq'] = []
                        self.state_tracker['INCORRECT_POSTURE'] = False
                        self.state_tracker['LOWER_HIPS'] = False
                        self.state_tracker['DISPLAY_TEXT'] = np.full((5,), False)
                        self.state_tracker['COUNT_FRAMES'] = np.zeros((5,), dtype=np.int64)
                        self.state_tracker['SPOKEN_FEEDBACK'] = set()
                        
                        # --- CHECK LIMIT / SETS ---
                        total_reps = self.state_tracker['SQUAT_COUNT'] + self.state_tracker['IMPROPER_SQUAT']
                        if total_reps >= self.reps_per_set:
                            self.state_tracker['WAITING_FOR_RESET'] = True
                            self.state_tracker['REST_START_TIME'] = time.perf_counter()

                            if (self.state_tracker['SET_COUNT'] + 1) >= self.target_sets:
                                self.state_tracker['DISPLAY_MESSAGE'] = "Whole Training is Done!"
                            else:
                                self.state_tracker['DISPLAY_MESSAGE'] = f"Well Done! Set {self.state_tracker['SET_COUNT'] + 1} Finished"

                # --- 5. INACTIVITY CHECK ---
                display_inactivity = False
                if self.state_tracker['curr_state'] == self.state_tracker['prev_state']:
                    end_time = time.perf_counter()
                    self.state_tracker['INACTIVE_TIME'] += end_time - self.state_tracker['start_inactive_time']
                    self.state_tracker['start_inactive_time'] = end_time

                    if self.state_tracker['INACTIVE_TIME'] >= self.thresholds['INACTIVE_THRESH']:
                        self.state_tracker['SQUAT_COUNT'] = 0
                        self.state_tracker['IMPROPER_SQUAT'] = 0
                        display_inactivity = True
                else:
                    self.state_tracker['start_inactive_time'] = time.perf_counter()
                    self.state_tracker['INACTIVE_TIME'] = 0.0

                # --- 6. DRAWING UI ---
                hip_text_coord_x = hip_coord[0] + 10
                knee_text_coord_x = knee_coord[0] + 15
                ankle_text_coord_x = ankle_coord[0] + 10
                if self.flip_frame:
                    frame = cv2.flip(frame, 1)
                    hip_text_coord_x = frame_width - hip_coord[0] + 10
                    knee_text_coord_x = frame_width - knee_coord[0] + 15
                    ankle_text_coord_x = frame_width - ankle_coord[0] + 10

                if 's3' in self.state_tracker['state_seq']:
                    self.state_tracker['LOWER_HIPS'] = False

                self.state_tracker['COUNT_FRAMES'][self.state_tracker['DISPLAY_TEXT']]+=1
                frame = self._show_feedback(frame, self.state_tracker['COUNT_FRAMES'], self.FEEDBACK_ID_MAP, self.state_tracker['LOWER_HIPS'])
                
                # --- Draw the Sequence Warning if the timer is active ---
                if self.state_tracker.get('ROM_WARNING_TIMER', 0) > 0:
                    draw_text(frame, "INCOMPLETE ROM", pos=(30, 260), text_color=(255, 255, 230), font_scale=0.6, text_color_bg=(255, 80, 80))
                    self.state_tracker['ROM_WARNING_TIMER'] -= 1

                if display_inactivity:
                    play_sound = 'reset_counters'
                    self.state_tracker['start_inactive_time'] = time.perf_counter()
                    self.state_tracker['INACTIVE_TIME'] = 0.0

                cv2.putText(frame, str(int(hip_vertical_angle)), (hip_text_coord_x, hip_coord[1]), self.font, 0.6, self.COLORS['light_green'], 2, lineType=self.linetype)
                cv2.putText(frame, str(int(knee_vertical_angle)), (knee_text_coord_x, knee_coord[1]+10), self.font, 0.6, self.COLORS['light_green'], 2, lineType=self.linetype)
                cv2.putText(frame, str(int(ankle_vertical_angle)), (ankle_text_coord_x, ankle_coord[1]), self.font, 0.6, self.COLORS['light_green'], 2, lineType=self.linetype)

                draw_text(frame, f"SET: {self.state_tracker['SET_COUNT']} / {self.target_sets}", pos=(int(frame_width*0.70), 30), text_color=(255, 255, 255), font_scale=0.7, text_color_bg=(50, 50, 50))
                draw_text(frame, "CORRECT: " + str(self.state_tracker['SQUAT_COUNT']), pos=(int(frame_width*0.70), 80), text_color=(255, 255, 230), font_scale=0.7, text_color_bg=(18, 185, 0))
                draw_text(frame, "INCORRECT: " + str(self.state_tracker['IMPROPER_SQUAT']), pos=(int(frame_width*0.70), 130), text_color=(255, 255, 230), font_scale=0.7, text_color_bg=(221, 0, 0))

                # Central Message (Freeze Phase)
                if self.state_tracker['WAITING_FOR_RESET']:
                    message = self.state_tracker['DISPLAY_MESSAGE']
                    text_size = cv2.getTextSize(message, self.font, 1.0, 2)[0]
                    text_x = (frame_width - text_size[0]) // 2
                    text_y = (frame_height + text_size[1]) // 2
                    cv2.rectangle(frame, (text_x - 20, text_y - text_size[1] - 20), (text_x + text_size[0] + 20, text_y + 20), (255, 153, 51), -1)
                    cv2.putText(frame, message, (text_x, text_y), self.font, 1.0, (255, 255, 255), 2, self.linetype)
            
            # --- UPDATE PREVIOUS STATE ---
            if self.state_tracker['curr_state']:
                 self.state_tracker['prev_state'] = self.state_tracker['curr_state']

        return frame, play_sound