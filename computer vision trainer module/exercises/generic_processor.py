import re
import time
import json

import cv2
import numpy as np
import yaml

from helpers.utils import find_angle, get_landmark_features, draw_text, draw_text_arabic

# MediaPipe landmark name → index
_MP_IDX = {
    'nose': 0,
    'left_shoulder': 11,  'right_shoulder': 12,
    'left_elbow':    13,  'right_elbow':    14,
    'left_wrist':    15,  'right_wrist':    16,
    'left_hip':      23,  'right_hip':      24,
    'left_knee':     25,  'right_knee':     26,
    'left_ankle':    27,  'right_ankle':    28,
    'left_foot':     31,  'right_foot':     32,
}

_DICT_FEATURES = {
    'left':  {'shoulder': 11, 'elbow': 13, 'wrist': 15, 'hip': 23, 'knee': 25, 'ankle': 27, 'foot': 31},
    'right': {'shoulder': 12, 'elbow': 14, 'wrist': 16, 'hip': 24, 'knee': 26, 'ankle': 28, 'foot': 32},
    'nose': 0,
}


def _lm(landmarks, mp_name, fw, fh):
    idx = _MP_IDX[mp_name]
    lm = landmarks[idx]
    return np.array([int(lm.x * fw), int(lm.y * fh)])


def _eval_cond(value, condition):
    """Evaluate 'value > N', 'value < N', or 'N < value < M'."""
    condition = condition.strip()
    m = re.match(r'^(-?\d+\.?\d*)\s*<\s*value\s*<\s*(-?\d+\.?\d*)$', condition)
    if m:
        return float(m.group(1)) < value < float(m.group(2))
    m = re.match(r'^value\s*(>=|<=|>|<)\s*(-?\d+\.?\d*)$', condition)
    if m:
        op, num = m.group(1), float(m.group(2))
        return {'>': value > num, '<': value < num,
                '>=': value >= num, '<=': value <= num}[op]
    return False


class GenericProcessor:
    def __init__(self, yaml_path, flip_frame=False, reps_per_set=10,
                 target_sets=3, rest_time=30, language='en'):
        with open(yaml_path, encoding='utf-8') as f:
            self.cfg = yaml.safe_load(f)

        self.flip_frame   = flip_frame
        self.reps_per_set = reps_per_set
        self.target_sets  = target_sets
        self.rest_time    = rest_time
        self.language     = language

        self.font     = cv2.FONT_HERSHEY_SIMPLEX
        self.linetype = cv2.LINE_AA

        self.COLORS = {
            'blue':        (0, 127, 255),
            'red':         (255, 50, 50),
            'green':       (0, 255, 127),
            'light_green': (100, 233, 127),
            'yellow':      (255, 255, 0),
            'magenta':     (255, 0, 255),
            'white':       (255, 255, 255),
            'cyan':        (0, 255, 255),
            'light_blue':  (102, 204, 255),
        }

        self._n    = len(self.cfg.get('form_checks', []))
        self._view = self.cfg.get('view', 'front')
        self._arm_lock  = self.cfg.get('arm_lock', False)
        self._persist   = self.cfg.get('feedback_persistence', 'frame')

        self._st = {
            'state_seq':             [],
            'start_inactive_time':   time.perf_counter(),
            'INACTIVE_TIME':         0.0,
            'start_inactive_time_front': time.perf_counter(),
            'INACTIVE_TIME_FRONT':   0.0,
            'DISPLAY_TEXT':          np.full((self._n,), False),
            'INCORRECT_POSTURE':     False,
            'LOWER_HIPS':            False,
            'prev_state':            None,
            'curr_state':            None,
            'REP_COUNT':             0,
            'IMPROPER_REP':          0,
            'SET_COUNT':             0,
            'EFFECTIVE_SET_COUNT':   0,
            'DISPLAY_MESSAGE':       None,
            'WAITING_FOR_RESET':     False,
            'REST_START_TIME':       None,
            'IS_FINAL_SET':          False,
            'IS_INITIALIZING':       True,
            'ROM_WARNING_TIMER':     0,
            'SESSION_CORRECT_REPS':  0,
            'SESSION_IMPROPER_REPS': 0,
            'SESSION_ERRORS':        set(),
            'JSON_SAVED':            False,
            'SPOKEN_FEEDBACK':       set(),
            'ACTIVE_ARM':            None,
            'ACTIVE_SIDE':           'right',
            'BASE_SHOULDER_WIDTH':   None,
            'HOLD_START_TIME':       None,
            'HOLD_PROGRESS':         0.0,
        }

    # ── State machine ──────────────────────────────────────────────────────────

    def _get_state(self, value):
        s = self.cfg['states']
        if s['s1'][0] <= value <= s['s1'][1]: return 's1'
        if s['s2'][0] <= value <= s['s2'][1]: return 's2'
        if s['s3'][0] <= value <= s['s3'][1]: return 's3'
        return None

    def _update_state_seq(self, state):
        seq = self._st['state_seq']
        if state == 's2':
            if (('s3' not in seq) and seq.count('s2') == 0) or \
               (('s3' in seq) and seq.count('s2') == 1):
                seq.append(state)
        elif state == 's3':
            if state not in seq and 's2' in seq:
                seq.append(state)

    # ── Landmark resolution ────────────────────────────────────────────────────

    def _coord(self, name, lms, fw, fh, side=None):
        """Resolve landmark name → pixel coords.
        Names with '_' (e.g. 'left_shoulder') are used directly.
        Short names (e.g. 'shoulder') are prefixed with the active side."""
        if '_' in name:
            return _lm(lms, name, fw, fh)
        s = side or self._st.get('ACTIVE_SIDE', 'right')
        return _lm(lms, f'{s}_{name}', fw, fh)

    # ── Measurement computation ────────────────────────────────────────────────

    def _angle_triple(self, meas, lms, fw, fh, side=None):
        p1 = self._coord(meas['p1'],     lms, fw, fh, side)
        v  = self._coord(meas['vertex'], lms, fw, fh, side)
        p3 = self._coord(meas['p3'],     lms, fw, fh, side)
        return find_angle(p1, v, p3)

    def _vert_angle(self, meas, lms, fw, fh, side=None):
        """find_angle(p1, [vertex_x, 0], vertex) — angle from vertical."""
        p1 = self._coord(meas['p1'],     lms, fw, fh, side)
        v  = self._coord(meas['vertex'], lms, fw, fh, side)
        return find_angle(p1, np.array([v[0], 0]), v)

    def _compute(self, meas, lms, fw, fh, ctx):
        mtype = meas['type']
        side  = ctx.get('side')

        if mtype == 'angle':
            return self._angle_triple(meas, lms, fw, fh, side)

        if mtype == 'vertical_angle':
            return self._vert_angle(meas, lms, fw, fh, side)

        if mtype == 'rotation_ratio':
            arm = ctx.get('active_arm')
            if arm is None:
                return None
            aw = ctx['active_wrist']
            ae = ctx['active_elbow']
            sw = ctx['shoulder_width']
            return (aw[0] - ae[0]) / sw if arm == 'left' else (ae[0] - aw[0]) / sw

        if mtype in ('bilateral_avg_angle', 'bilateral_max_angle',
                     'bilateral_min_angle', 'bilateral_diff_angle'):
            la = self._angle_triple(meas['left'],  lms, fw, fh)
            ra = self._angle_triple(meas['right'], lms, fw, fh)
            if mtype == 'bilateral_avg_angle':  return (la + ra) / 2
            if mtype == 'bilateral_max_angle':  return max(la, ra)
            if mtype == 'bilateral_min_angle':  return min(la, ra)
            if mtype == 'bilateral_diff_angle': return abs(la - ra)

        if mtype == 'torso_angle':
            ls = ctx['left_shoulder']
            rs = ctx['right_shoulder']
            lh = ctx['left_hip']
            rh = ctx['right_hip']
            mid_s = np.array([(ls[0]+rs[0])//2, (ls[1]+rs[1])//2])
            mid_h = np.array([(lh[0]+rh[0])//2, (lh[1]+rh[1])//2])
            return find_angle(mid_s, np.array([mid_h[0], 0]), mid_h)

        if mtype == 'wrist_y_diff':
            return abs(ctx['active_elbow'][1] - ctx['active_wrist'][1]) / fh

        if mtype == 'elbow_flare_ratio':
            ae  = ctx['active_elbow']
            as_ = ctx['active_shoulder']
            sw  = ctx['shoulder_width']
            arm = ctx['active_arm']
            return (ae[0] - as_[0]) / sw if arm == 'left' else (as_[0] - ae[0]) / sw

        if mtype == 'ratio_vs_baseline':
            sw  = ctx['shoulder_width']
            bsw = ctx.get('base_shoulder_width') or sw
            return sw / bsw

        # ── New generalisable measurement types ────────────────────────────────

        if mtype == 'distance_ratio':
            # Euclidean distance between two landmarks, normalised by shoulder width.
            # Works for: heel-to-buttock (prone knee flex), chin-to-chest, reach tests.
            p1 = self._coord(meas['p1'], lms, fw, fh, side)
            p2 = self._coord(meas['p2'], lms, fw, fh, side)
            sw = ctx.get('shoulder_width', 1)
            return float(np.linalg.norm(p1.astype(float) - p2.astype(float))) / max(sw, 1)

        if mtype == 'lateral_trunk_angle':
            # Sideways lean of the spine from vertical (FRONT VIEW).
            # Different from torso_angle which measures forward lean (SIDE VIEW).
            ls = ctx.get('left_shoulder')  or _lm(lms, 'left_shoulder',  fw, fh)
            rs = ctx.get('right_shoulder') or _lm(lms, 'right_shoulder', fw, fh)
            lh = ctx.get('left_hip')       or _lm(lms, 'left_hip',       fw, fh)
            rh = ctx.get('right_hip')      or _lm(lms, 'right_hip',      fw, fh)
            mid_s = np.array([(ls[0]+rs[0])//2, (ls[1]+rs[1])//2], dtype=float)
            mid_h = np.array([(lh[0]+rh[0])//2, (lh[1]+rh[1])//2], dtype=float)
            dx = float(mid_s[0] - mid_h[0])
            dy = float(mid_h[1] - mid_s[1])      # positive when hip below shoulder
            return float(np.degrees(np.arctan2(abs(dx), max(dy, 1.0))))

        if mtype == 'knee_valgus_ratio':
            # How far the knee collapses inward relative to the hip-ankle line.
            # Positive = valgus (knee inside the hip-ankle plumb line).
            sw       = max(ctx.get('shoulder_width', 1), 1)
            side_cfg = meas.get('side', 'bilateral_max')

            def _valgus_one(sn):
                k  = _lm(lms, f'{sn}_knee',  fw, fh)
                a  = _lm(lms, f'{sn}_ankle', fw, fh)
                h  = _lm(lms, f'{sn}_hip',   fw, fh)
                # Interpolate the hip-ankle line at knee height to find the plumb x
                t     = float(k[1] - h[1]) / max(float(a[1] - h[1]), 1.0)
                mid_x = h[0] + t * (a[0] - h[0])
                sign  = 1 if sn == 'left' else -1   # left knee valgus = rightward, right = leftward
                return sign * float(k[0] - mid_x) / sw

            if side_cfg == 'bilateral_max':
                return max(_valgus_one('left'), _valgus_one('right'))
            return _valgus_one(side_cfg)

        return None

    # ── Form checks ────────────────────────────────────────────────────────────

    def _run_checks(self, lms, current_state, fw, fh, ctx):
        for i, chk in enumerate(self.cfg.get('form_checks', [])):
            if current_state in chk.get('skip_in_states', []):
                continue
            if chk.get('require_s2_seen') and self._st['state_seq'].count('s2') == 0:
                continue

            val = self._compute(chk['measurement'], lms, fw, fh, ctx)
            if val is None:
                continue

            fires = _eval_cond(val, chk['condition'])

            # Compound AND condition: optional second measurement that must also fire
            if fires:
                meas_b = chk.get('measurement_b')
                cond_b = chk.get('condition_b')
                if meas_b and cond_b:
                    val_b = self._compute(meas_b, lms, fw, fh, ctx)
                    fires = val_b is not None and _eval_cond(val_b, cond_b)

            if fires:
                self._st['DISPLAY_TEXT'][i] = True
                self._st['SESSION_ERRORS'].add(chk['id'])
                if chk.get('affects_rep') and current_state != 's1':
                    self._st['INCORRECT_POSTURE'] = True

        # Lower-hips hint (squat only)
        hint = self.cfg.get('lower_hips_hint')
        if hint:
            if not (hint.get('require_s2_seen') and self._st['state_seq'].count('s2') == 0):
                val = self._compute(hint['measurement'], lms, fw, fh, ctx)
                if val is not None and _eval_cond(val, hint['condition']):
                    self._st['LOWER_HIPS'] = True

    # ── Sound ──────────────────────────────────────────────────────────────────

    def _pick_sound(self, play_sound):
        if play_sound is not None:
            return play_sound
        for i, chk in enumerate(self.cfg.get('form_checks', [])):
            if self._st['DISPLAY_TEXT'][i] and i not in self._st['SPOKEN_FEEDBACK']:
                self._st['SPOKEN_FEEDBACK'].add(i)
                return chk.get('sound')
        return None

    # ── Feedback display ───────────────────────────────────────────────────────

    def _show_feedback(self, frame):
        right_x = max(30, frame.shape[1] - 280)

        if self._st['LOWER_HIPS']:
            if self.language in ('en', 'both'):
                draw_text(frame, 'LOWER YOUR HIPS', pos=(30, 80),
                          text_color=(0, 0, 0), font_scale=0.6, text_color_bg=(255, 255, 0))
            if self.language in ('ar', 'both'):
                x = right_x if self.language == 'both' else 30
                draw_text_arabic(frame, 'خفّض وركيك', pos=(x, 80),
                                 font_scale=0.6, text_color=(0, 0, 0), bg_color=(255, 255, 0))

        for i, chk in enumerate(self.cfg.get('form_checks', [])):
            if not self._st['DISPLAY_TEXT'][i]:
                continue
            y     = chk.get('display_y', 80 + i * 45)
            color = tuple(chk.get('color', [0, 153, 255]))
            if self.language in ('en', 'both'):
                draw_text(frame, chk['label_en'], pos=(30, y),
                          text_color=(255, 255, 230), font_scale=0.6, text_color_bg=color)
            if self.language in ('ar', 'both'):
                x = right_x if self.language == 'both' else 30
                draw_text_arabic(frame, chk['label_ar'], pos=(x, y),
                                 font_scale=0.6, text_color=(255, 255, 230), bg_color=color)
        return frame

    # ── Skeleton drawing ───────────────────────────────────────────────────────

    def _draw_skeleton(self, frame, ctx):
        if self._view == 'side':
            s, e, w = ctx['shoulder'], ctx['elbow'], ctx['wrist']
            h, k, a, f = ctx['hip'], ctx['knee'], ctx['ankle'], ctx['foot']
            m = ctx['multiplier']

            ha = find_angle(s, np.array([h[0], 0]), h)
            ka = find_angle(h, np.array([k[0], 0]), k)
            aa = find_angle(k, np.array([a[0], 0]), a)

            cv2.ellipse(frame, h, (30,30), 0, -90, -90+m*ha,  self.COLORS['white'], 3, self.linetype)
            cv2.line(frame, (h[0],h[1]+20), (h[0],h[1]-80), self.COLORS['blue'], 4, self.linetype)
            cv2.ellipse(frame, k, (20,20), 0, -90, -90-m*ka,  self.COLORS['white'], 3, self.linetype)
            cv2.line(frame, (k[0],k[1]+20), (k[0],k[1]-50), self.COLORS['blue'], 4, self.linetype)
            cv2.ellipse(frame, a, (30,30), 0, -90, -90+m*aa,  self.COLORS['white'], 3, self.linetype)
            cv2.line(frame, (a[0],a[1]+20), (a[0],a[1]-50), self.COLORS['blue'], 4, self.linetype)

            for (p, q) in [(s,e),(e,w),(s,h),(h,k),(k,a),(a,f)]:
                cv2.line(frame, tuple(p), tuple(q), self.COLORS['light_blue'], 4, self.linetype)
            for pt in [s, e, w, h, k, a, f]:
                cv2.circle(frame, tuple(pt), 7, self.COLORS['yellow'], -1, self.linetype)

        elif self._view == 'front':
            ls = ctx['left_shoulder'];  rs = ctx['right_shoulder']
            le = ctx['left_elbow'];     re = ctx['right_elbow']
            lw = ctx['left_wrist'];     rw = ctx['right_wrist']
            lh = ctx['left_hip'];       rh = ctx['right_hip']
            mid_s = np.array([(ls[0]+rs[0])//2, (ls[1]+rs[1])//2])
            mid_h = np.array([(lh[0]+rh[0])//2, (lh[1]+rh[1])//2])

            for (p, q) in [(ls,rs),(ls,lh),(rs,rh),(lh,rh),(ls,le),(le,lw),(rs,re),(re,rw)]:
                cv2.line(frame, tuple(p), tuple(q), self.COLORS['light_blue'], 4, self.linetype)
            cv2.line(frame, tuple(mid_s), tuple(mid_h), self.COLORS['magenta'], 4, self.linetype)
            for pt in [ls,rs,le,re,lw,rw,lh,rh,mid_s,mid_h]:
                cv2.circle(frame, tuple(pt), 7, self.COLORS['yellow'], -1, self.linetype)

    # ── UI overlays ────────────────────────────────────────────────────────────

    def _draw_counters(self, frame, fw):
        st = self._st
        draw_text(frame, f"SET: {st['SET_COUNT']} / {self.target_sets}",
                  pos=(int(fw*0.70), 30),  text_color=(255,255,255), font_scale=0.7, text_color_bg=(50,50,50))
        draw_text(frame, f"EFF SETS: {st['EFFECTIVE_SET_COUNT']}",
                  pos=(int(fw*0.70), 80),  text_color=(255,255,255), font_scale=0.7, text_color_bg=(153,50,204))
        draw_text(frame, "CORRECT: "   + str(st['REP_COUNT']),
                  pos=(int(fw*0.70), 130), text_color=(255,255,230), font_scale=0.7, text_color_bg=(18,185,0))
        draw_text(frame, "INCORRECT: " + str(st['IMPROPER_REP']),
                  pos=(int(fw*0.70), 180), text_color=(255,255,230), font_scale=0.7, text_color_bg=(221,0,0))

    def _draw_center_msg(self, frame, fw, fh, msg):
        ts = cv2.getTextSize(msg, self.font, 1.0, 2)[0]
        tx = (fw - ts[0]) // 2
        ty = fh // 2 - 50
        cv2.rectangle(frame, (tx-20, ty-ts[1]-20), (tx+ts[0]+20, ty+20), (255,153,51), -1)
        cv2.putText(frame, msg, (tx, ty), self.font, 1.0, (255,255,255), 2, self.linetype)

    def _draw_side_angles(self, frame, ctx, fw, primary_val):
        h, k, a = ctx['hip'], ctx['knee'], ctx['ankle']
        s = ctx['shoulder']
        ha = int(find_angle(s, np.array([h[0], 0]), h))
        ka = int(primary_val)
        aa = int(find_angle(k, np.array([a[0], 0]), a))
        if self.flip_frame:
            hx = fw - h[0] + 10
            kx = fw - k[0] + 15
            ax = fw - a[0] + 10
        else:
            hx = h[0] + 10
            kx = k[0] + 15
            ax = a[0] + 10
        cv2.putText(frame, str(ha), (hx, h[1]),    self.font, 0.6, self.COLORS['light_green'], 2, self.linetype)
        cv2.putText(frame, str(ka), (kx, k[1]+10), self.font, 0.6, self.COLORS['light_green'], 2, self.linetype)
        cv2.putText(frame, str(aa), (ax, a[1]),    self.font, 0.6, self.COLORS['light_green'], 2, self.linetype)

    def _draw_front_angles(self, frame, ctx, lms, fw, fh):
        ls = ctx['left_shoulder'];  rs = ctx['right_shoulder']
        la = int(find_angle(_lm(lms,'left_hip',fw,fh),  ls, _lm(lms,'left_elbow',fw,fh)))
        ra = int(find_angle(_lm(lms,'right_hip',fw,fh), rs, _lm(lms,'right_elbow',fw,fh)))
        if self.flip_frame:
            ltx = fw - ls[0] - 50
            rtx = fw - rs[0] + 10
        else:
            ltx = ls[0] + 10
            rtx = rs[0] - 50
        cv2.putText(frame, f"L: {la}", (ltx, ls[1]-20), self.font, 0.6, self.COLORS['light_green'], 2, self.linetype)
        cv2.putText(frame, f"R: {ra}", (rtx, rs[1]-20), self.font, 0.6, self.COLORS['light_green'], 2, self.linetype)

    # ── Rep / set counting ─────────────────────────────────────────────────────

    def _on_s1(self, play_sound):
        seq = self._st['state_seq']

        if len(seq) == 3 and not self._st['INCORRECT_POSTURE']:
            self._st['REP_COUNT']            += 1
            self._st['SESSION_CORRECT_REPS'] += 1
            play_sound = str(self._st['REP_COUNT'])
        elif 's2' in seq and len(seq) == 1:
            self._st['IMPROPER_REP']          += 1
            self._st['SESSION_IMPROPER_REPS'] += 1
            self._st['ROM_WARNING_TIMER']  = 45
            self._st['SESSION_ERRORS'].add('INCOMPLETE ROM')
            play_sound = 'incorrect'
        elif self._st['INCORRECT_POSTURE'] and len(seq) > 0:
            self._st['IMPROPER_REP']          += 1
            self._st['SESSION_IMPROPER_REPS'] += 1
            play_sound = 'incorrect'

        # Reset per-rep state.
        # state_seq and SPOKEN_FEEDBACK always clear on s1 return.
        # INCORRECT_POSTURE only clears when a rep branch matched (seq > 0),
        # matching old-processor behaviour: a form error during an aborted
        # movement carries forward to the next attempt rather than being wiped.
        self._st['state_seq']      = []
        self._st['LOWER_HIPS']     = False
        self._st['SPOKEN_FEEDBACK'] = set()
        if len(seq) > 0:
            self._st['INCORRECT_POSTURE'] = False
        if self._persist == 'rep':
            self._st['DISPLAY_TEXT'] = np.full((self._n,), False)

        # Check set completion
        total = self._st['REP_COUNT'] + self._st['IMPROPER_REP']
        if total >= self.reps_per_set:
            self._st['WAITING_FOR_RESET'] = True
            self._st['REST_START_TIME']   = time.time()

            accuracy = self._st['REP_COUNT'] / total if total > 0 else 0
            if accuracy >= 0.70:
                self._st['EFFECTIVE_SET_COUNT'] += 1
                prefix = "Excellent form!"
            elif accuracy >= 0.40:
                prefix = "Good effort, focus on your form."
            else:
                prefix = "Tough set! Keep working on it."

            is_final = (self._st['SET_COUNT'] + 1) >= self.target_sets
            self._st['IS_FINAL_SET']     = is_final
            self._st['DISPLAY_MESSAGE']  = (
                f"{prefix} Training Complete!" if is_final
                else f"{prefix} Set {self._st['SET_COUNT'] + 1} Done"
            )

        return play_sound

    # ── Hold / isometric mode ──────────────────────────────────────────────────

    def _on_hold(self, current_state, play_sound, frame, fw, fh):
        """Handle rep counting for hold/isometric exercises.
        A 'rep' is defined as sustaining s3 for hold_duration seconds.
        Leaving s3 after < 50 % of duration counts as an improper rep."""
        hold_duration = float(self.cfg.get('hold_duration', 30.0))

        if current_state == 's3' and not self._st['WAITING_FOR_RESET']:
            if self._st['HOLD_START_TIME'] is None:
                self._st['HOLD_START_TIME'] = time.perf_counter()

            elapsed  = time.perf_counter() - self._st['HOLD_START_TIME']
            progress = min(elapsed / hold_duration, 1.0)
            self._st['HOLD_PROGRESS'] = progress

            # Progress bar at bottom of frame
            bar_x, bar_w, bar_h = fw // 2 - 160, 320, 16
            bar_y = fh - 14
            cv2.rectangle(frame, (bar_x, bar_y - bar_h), (bar_x + bar_w, bar_y),
                          (60, 60, 60), -1, self.linetype)
            cv2.rectangle(frame, (bar_x, bar_y - bar_h),
                          (bar_x + int(bar_w * progress), bar_y),
                          (0, 220, 100), -1, self.linetype)

            lbl = f"HOLD  {int(elapsed)}s / {int(hold_duration)}s"
            ts  = cv2.getTextSize(lbl, self.font, 0.85, 2)[0]
            cv2.putText(frame, lbl, (fw // 2 - ts[0] // 2, bar_y - bar_h - 8),
                        self.font, 0.85, (0, 255, 150), 2, self.linetype)

            if elapsed >= hold_duration:
                self._st['REP_COUNT']            += 1
                self._st['SESSION_CORRECT_REPS'] += 1
                play_sound = str(self._st['REP_COUNT'])
                self._st['HOLD_START_TIME'] = None
                self._st['HOLD_PROGRESS']   = 0.0
                self._st['SPOKEN_FEEDBACK'] = set()
                self._st['INCORRECT_POSTURE'] = False

                total = self._st['REP_COUNT'] + self._st['IMPROPER_REP']
                if total >= self.reps_per_set:
                    self._st['WAITING_FOR_RESET'] = True
                    self._st['REST_START_TIME']   = time.time()
                    accuracy = self._st['REP_COUNT'] / total
                    if accuracy >= 0.70:
                        self._st['EFFECTIVE_SET_COUNT'] += 1
                        prefix = "Excellent form!"
                    elif accuracy >= 0.40:
                        prefix = "Good effort!"
                    else:
                        prefix = "Keep working!"
                    is_final = (self._st['SET_COUNT'] + 1) >= self.target_sets
                    self._st['IS_FINAL_SET']    = is_final
                    self._st['DISPLAY_MESSAGE'] = (
                        f"{prefix} Training Complete!" if is_final
                        else f"{prefix} Set {self._st['SET_COUNT'] + 1} Done"
                    )

        elif self._st['HOLD_START_TIME'] is not None:
            # Person left s3 before completing the hold
            elapsed = time.perf_counter() - self._st['HOLD_START_TIME']
            if elapsed < hold_duration * 0.5:
                self._st['IMPROPER_REP']          += 1
                self._st['SESSION_IMPROPER_REPS'] += 1
                play_sound = 'incorrect'
                total = self._st['REP_COUNT'] + self._st['IMPROPER_REP']
                if total >= self.reps_per_set:
                    self._st['WAITING_FOR_RESET'] = True
                    self._st['REST_START_TIME']   = time.time()
                    is_final = (self._st['SET_COUNT'] + 1) >= self.target_sets
                    self._st['IS_FINAL_SET']    = is_final
                    self._st['DISPLAY_MESSAGE'] = (
                        "Training Complete!" if is_final
                        else f"Set {self._st['SET_COUNT'] + 1} Done"
                    )
            self._st['HOLD_START_TIME']   = None
            self._st['HOLD_PROGRESS']     = 0.0
            self._st['INCORRECT_POSTURE'] = False
            self._st['state_seq']         = []
            self._st['SPOKEN_FEEDBACK']   = set()

        return play_sound

    # ── JSON export ────────────────────────────────────────────────────────────

    def _export_json(self):
        log = {
            "exercise":              self.cfg['name'],
            "total_sets_completed":  self.target_sets,
            "effective_sets":        self._st['EFFECTIVE_SET_COUNT'],
            "total_correct_reps":    self._st['SESSION_CORRECT_REPS'],
            "total_incorrect_reps":  self._st['SESSION_IMPROPER_REPS'],
            "errors_triggered":      list(self._st['SESSION_ERRORS']),
        }
        with open("workout_log.json", "w") as f:
            json.dump(log, f, indent=4)
        self._st['JSON_SAVED'] = True

    # ── Main process ──────────────────────────────────────────────────────────

    def process(self, frame: np.ndarray, pose):
        play_sound = None
        fh, fw, _ = frame.shape

        # ── Kill switch (training complete) ───────────────────────────────────
        if self._st['SET_COUNT'] >= self.target_sets:
            if not self._st['JSON_SAVED']:
                self._export_json()
            if self.flip_frame:
                frame = cv2.flip(frame, 1)
            self._draw_counters(frame, fw)
            msg = "TRAINING COMPLETED!"
            ts  = cv2.getTextSize(msg, self.font, 1.5, 3)[0]
            tx  = (fw - ts[0]) // 2
            ty  = (fh + ts[1]) // 2
            cv2.rectangle(frame, (tx-20, ty-ts[1]-20), (tx+ts[0]+20, ty+20), (50,205,50), -1)
            cv2.putText(frame, msg, (tx, ty), self.font, 1.5, (255,255,255), 3, self.linetype)
            return frame, None

        # ── Rest / celebration timer ───────────────────────────────────────────
        if self._st['WAITING_FOR_RESET']:
            elapsed = time.time() - self._st['REST_START_TIME']

            if self._st['IS_FINAL_SET']:
                time_left = 3.5 - elapsed
                disp = cv2.flip(frame, 1) if self.flip_frame else frame
                if time_left > 0:
                    self._draw_center_msg(disp, fw, fh, self._st['DISPLAY_MESSAGE'])
                    return disp, None
                else:
                    self._st['SET_COUNT']        += 1
                    self._st['WAITING_FOR_RESET']  = False
                    return disp, None

            time_left = self.rest_time - elapsed
            if time_left > 0:
                disp = cv2.flip(frame, 1) if self.flip_frame else frame
                self._draw_center_msg(disp, fw, fh, self._st['DISPLAY_MESSAGE'])
                cd   = f"REST: {int(time_left)+1}s"
                cs   = cv2.getTextSize(cd, self.font, 2.0, 4)[0]
                cx   = (fw - cs[0]) // 2
                cv2.putText(disp, cd, (cx, fh//2+30), self.font, 2.0, (0,255,255), 4, self.linetype)
                return disp, None
            else:
                # Timer expired — reset and fall through
                self._st['WAITING_FOR_RESET']   = False
                self._st['REST_START_TIME']      = None
                self._st['REP_COUNT']            = 0
                self._st['IMPROPER_REP']         = 0
                self._st['SET_COUNT']           += 1
                self._st['ACTIVE_ARM']           = None
                self._st['state_seq']            = []
                self._st['ROM_WARNING_TIMER']    = 0
                self._st['IS_INITIALIZING']      = True
                self._st['SPOKEN_FEEDBACK']      = set()
                play_sound = 'reset_counters'

        # ── Pose processing ────────────────────────────────────────────────────
        kp = pose.process(frame)
        if not kp.pose_landmarks:
            return frame, play_sound

        lms = kp.pose_landmarks.landmark

        # ── Build context ──────────────────────────────────────────────────────
        ctx = {}

        if self._view == 'front':
            ctx['left_shoulder']  = _lm(lms, 'left_shoulder',  fw, fh)
            ctx['right_shoulder'] = _lm(lms, 'right_shoulder', fw, fh)
            ctx['left_elbow']     = _lm(lms, 'left_elbow',     fw, fh)
            ctx['right_elbow']    = _lm(lms, 'right_elbow',    fw, fh)
            ctx['left_wrist']     = _lm(lms, 'left_wrist',     fw, fh)
            ctx['right_wrist']    = _lm(lms, 'right_wrist',    fw, fh)
            ctx['left_hip']       = _lm(lms, 'left_hip',       fw, fh)
            ctx['right_hip']      = _lm(lms, 'right_hip',      fw, fh)

            sw = abs(ctx['right_shoulder'][0] - ctx['left_shoulder'][0])
            ctx['shoulder_width'] = sw if sw > 0 else 1

            if self._arm_lock:
                if self._st['ACTIVE_ARM'] is None:
                    le = find_angle(ctx['left_shoulder'],  ctx['left_wrist'],  ctx['left_elbow'])
                    re = find_angle(ctx['right_shoulder'], ctx['right_wrist'], ctx['right_elbow'])
                    self._st['ACTIVE_ARM'] = 'left' if abs(90-le) < abs(90-re) else 'right'
                arm = self._st['ACTIVE_ARM']
                ctx['active_arm']      = arm
                ctx['active_shoulder'] = ctx[f'{arm}_shoulder']
                ctx['active_elbow']    = ctx[f'{arm}_elbow']
                ctx['active_wrist']    = ctx[f'{arm}_wrist']

            # Torso twist baseline: calibrate at s1
            if self._st['BASE_SHOULDER_WIDTH'] is None or self._st['curr_state'] == 's1':
                self._st['BASE_SHOULDER_WIDTH'] = ctx['shoulder_width']
            ctx['base_shoulder_width'] = self._st['BASE_SHOULDER_WIDTH']

        elif self._view == 'side':
            nose    = _lm(lms, 'nose', fw, fh)
            ls, le, lw, lh, lk, la, lf = get_landmark_features(lms, _DICT_FEATURES, 'left',  fw, fh)
            rs, re_, rw, rh, rk, ra, rf = get_landmark_features(lms, _DICT_FEATURES, 'right', fw, fh)

            offset_angle = find_angle(ls, rs, nose)
            ctx['offset_angle']    = offset_angle
            ctx['nose']            = nose
            ctx['left_shoulder']   = ls
            ctx['right_shoulder']  = rs

            # Auto-detect which side faces the camera (larger foot-shoulder Y span)
            if abs(lf[1] - ls[1]) > abs(rf[1] - rs[1]):
                side = 'left'
                ctx.update({'shoulder':ls,'elbow':le,'wrist':lw,'hip':lh,
                             'knee':lk,'ankle':la,'foot':lf,'multiplier':-1})
            else:
                side = 'right'
                ctx.update({'shoulder':rs,'elbow':re_,'wrist':rw,'hip':rh,
                             'knee':rk,'ankle':ra,'foot':rf,'multiplier':1})
            ctx['side'] = side
            self._st['ACTIVE_SIDE'] = side

        # ── Side-view camera alignment check (Branch A) ────────────────────────
        if self._view == 'side':
            offset_thresh   = self.cfg.get('offset_thresh',  50.0)
            inactive_thresh = self.cfg.get('inactive_thresh', 15.0)

            if ctx['offset_angle'] > offset_thresh:
                end_t = time.perf_counter()
                self._st['INACTIVE_TIME_FRONT'] += end_t - self._st['start_inactive_time_front']
                self._st['start_inactive_time_front'] = end_t

                if self._st['INACTIVE_TIME_FRONT'] >= inactive_thresh:
                    self._st['REP_COUNT']   = 0
                    self._st['IMPROPER_REP'] = 0
                    play_sound = 'reset_counters'
                    self._st['INACTIVE_TIME_FRONT']         = 0.0
                    self._st['start_inactive_time_front']   = time.perf_counter()

                if self.flip_frame:
                    frame = cv2.flip(frame, 1)

                draw_text(frame, 'POSTURE NOT ALIGNED PROPERLY!!! (TURN LEFT or RIGHT)',
                          pos=(30, fh-60), text_color=(255,255,230),
                          font_scale=0.65, text_color_bg=(255,153,0))
                self._draw_counters(frame, fw)

                self._st['prev_state']       = None
                self._st['curr_state']       = None
                self._st['INCORRECT_POSTURE'] = False
                self._st['state_seq']         = []
                self._st['SPOKEN_FEEDBACK']   = set()
                self._st['start_inactive_time'] = time.perf_counter()
                return frame, play_sound

            self._st['INACTIVE_TIME_FRONT']       = 0.0
            self._st['start_inactive_time_front']  = time.perf_counter()

        # ── Primary measurement + state ────────────────────────────────────────
        primary_val   = self._compute(self.cfg['primary_measurement'], lms, fw, fh, ctx)
        if primary_val is None:
            return frame, play_sound

        current_state = self._get_state(primary_val)
        self._st['curr_state'] = current_state
        if current_state:
            self._update_state_seq(current_state)

        # ── Form checks (run even in None state so ARMS_TOO_HIGH etc. fire) ───
        self._run_checks(lms, current_state, fw, fh, ctx)

        # ── Sound from form checks ─────────────────────────────────────────────
        play_sound = self._pick_sound(play_sound)

        # ── Grace period ───────────────────────────────────────────────────────
        if self._st['IS_INITIALIZING']:
            if current_state == 's1':
                self._st['IS_INITIALIZING'] = False
            self._st['state_seq']         = []
            self._st['INCORRECT_POSTURE']  = False
            self._st['SPOKEN_FEEDBACK']    = set()

        # ── Rep / hold counting ────────────────────────────────────────────────
        _mode = self.cfg.get('mode', 'rep')
        if _mode == 'hold':
            play_sound = self._on_hold(current_state, play_sound, frame, fw, fh)
        elif not self._st['WAITING_FOR_RESET'] and current_state == 's1':
            play_sound = self._on_s1(play_sound)

        # ── Inactivity check ───────────────────────────────────────────────────
        # In hold mode, being stationary in s3 is intentional — skip the timer.
        display_inactivity = False
        _in_hold = (_mode == 'hold' and current_state == 's3')
        if not _in_hold:
            if self._st['curr_state'] == self._st['prev_state']:
                end_t = time.perf_counter()
                self._st['INACTIVE_TIME'] += end_t - self._st['start_inactive_time']
                self._st['start_inactive_time'] = end_t
                if self._st['INACTIVE_TIME'] >= self.cfg.get('inactive_thresh', 15.0):
                    self._st['REP_COUNT']   = 0
                    self._st['IMPROPER_REP'] = 0
                    self._st['ACTIVE_ARM']   = None
                    display_inactivity = True
            else:
                self._st['start_inactive_time'] = time.perf_counter()
                self._st['INACTIVE_TIME']        = 0.0

        # ── Draw skeleton ──────────────────────────────────────────────────────
        self._draw_skeleton(frame, ctx)

        # ── Flip ───────────────────────────────────────────────────────────────
        if self.flip_frame:
            frame = cv2.flip(frame, 1)

        # ── Clear LOWER_HIPS once s3 is reached ───────────────────────────────
        if 's3' in self._st['state_seq']:
            self._st['LOWER_HIPS'] = False

        # ── Draw feedback text ─────────────────────────────────────────────────
        frame = self._show_feedback(frame)

        # ── ROM warning ────────────────────────────────────────────────────────
        if self._st['ROM_WARNING_TIMER'] > 0:
            draw_text(frame, "INCOMPLETE ROM", pos=(30, 260),
                      text_color=(255,255,230), font_scale=0.6, text_color_bg=(255,80,80))
            self._st['ROM_WARNING_TIMER'] -= 1

        # ── Counter boxes ──────────────────────────────────────────────────────
        self._draw_counters(frame, fw)

        # ── Per-exercise angle annotations ─────────────────────────────────────
        if self._view == 'side':
            self._draw_side_angles(frame, ctx, fw, primary_val)
        elif self._view == 'front' and not self._arm_lock:
            self._draw_front_angles(frame, ctx, lms, fw, fh)

        # ── Inactivity sound ───────────────────────────────────────────────────
        if display_inactivity:
            play_sound = 'reset_counters'
            self._st['start_inactive_time'] = time.perf_counter()
            self._st['INACTIVE_TIME']        = 0.0

        # ── Reset per-frame DISPLAY_TEXT ───────────────────────────────────────
        if self._persist == 'frame':
            self._st['DISPLAY_TEXT'] = np.full((self._n,), False)

        if self._st['curr_state']:
            self._st['prev_state'] = self._st['curr_state']

        return frame, play_sound
