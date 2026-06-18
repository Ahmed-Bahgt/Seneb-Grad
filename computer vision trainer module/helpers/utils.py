import os
import threading
import urllib.request
import cv2
import mediapipe as mp
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import arabic_reshaper
from bidi.algorithm import get_display

_ARABIC_FONT_CACHE: dict = {}

def _get_arabic_font(size: int) -> ImageFont.FreeTypeFont:
    if size in _ARABIC_FONT_CACHE:
        return _ARABIC_FONT_CACHE[size]
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    candidates = [
        os.path.join(project_root, 'static', 'fonts', 'tahoma.ttf'),
        'C:/Windows/Fonts/tahoma.ttf',
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        '/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf',
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                font = ImageFont.truetype(path, size)
                _ARABIC_FONT_CACHE[size] = font
                return font
            except Exception:
                continue
    font = ImageFont.load_default()
    _ARABIC_FONT_CACHE[size] = font
    return font


def draw_text_arabic(frame: np.ndarray, text: str, pos: tuple,
                     font_scale: float = 0.6,
                     text_color: tuple = (255, 255, 230),
                     bg_color: tuple = (0, 0, 0)) -> None:
    """Draw Arabic text on a BGR frame using PIL (modifies frame in-place)."""
    reshaped = arabic_reshaper.reshape(text)
    bidi_text = get_display(reshaped)

    font_size = max(14, int(font_scale * 34))
    font = _get_arabic_font(font_size)

    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(frame_rgb)
    draw = ImageDraw.Draw(pil_img)

    bbox = draw.textbbox(pos, bidi_text, font=font)
    pad = 6
    draw.rectangle(
        [bbox[0] - pad, bbox[1] - pad, bbox[2] + pad, bbox[3] + pad],
        fill=bg_color,
    )
    draw.text(pos, bidi_text, font=font, fill=text_color)

    frame[:] = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)

_pose_thread_local = threading.local()

correct = cv2.imread('right.png')
correct = cv2.cvtColor(correct, cv2.COLOR_BGR2RGB)
incorrect = cv2.imread('wrong.png')
incorrect = cv2.cvtColor(incorrect, cv2.COLOR_BGR2RGB)

def draw_rounded_rect(img, rect_start, rect_end, corner_width, box_color):

    x1, y1 = rect_start
    x2, y2 = rect_end
    w = corner_width

    # draw filled rectangles
    cv2.rectangle(img, (x1 + w, y1), (x2 - w, y1 + w), box_color, -1)
    cv2.rectangle(img, (x1 + w, y2 - w), (x2 - w, y2), box_color, -1)
    cv2.rectangle(img, (x1, y1 + w), (x1 + w, y2 - w), box_color, -1)
    cv2.rectangle(img, (x2 - w, y1 + w), (x2, y2 - w), box_color, -1)
    cv2.rectangle(img, (x1 + w, y1 + w), (x2 - w, y2 - w), box_color, -1)


    # draw filled ellipses
    cv2.ellipse(img, (x1 + w, y1 + w), (w, w),
                angle = 0, startAngle = -90, endAngle = -180, color = box_color, thickness = -1)

    cv2.ellipse(img, (x2 - w, y1 + w), (w, w),
                angle = 0, startAngle = 0, endAngle = -90, color = box_color, thickness = -1)

    cv2.ellipse(img, (x1 + w, y2 - w), (w, w),
                angle = 0, startAngle = 90, endAngle = 180, color = box_color, thickness = -1)

    cv2.ellipse(img, (x2 - w, y2 - w), (w, w),
                angle = 0, startAngle = 0, endAngle = 90, color = box_color, thickness = -1)

    return img




def draw_dotted_line(frame, lm_coord, start, end, line_color):
    pix_step = 0

    for i in range(start, end+1, 8):
        cv2.circle(frame, (lm_coord[0], i+pix_step), 2, line_color, -1, lineType=cv2.LINE_AA)

    return frame

def draw_text(
    img,
    msg,
    width = 7,
    font=cv2.FONT_HERSHEY_SIMPLEX,
    pos=(0, 0),
    font_scale=1,
    font_thickness=2,
    text_color=(0, 255, 0),
    text_color_bg=(0, 0, 0),
    box_offset=(20, 10),
    overlay_image = False,
    overlay_type = None
):

    offset = box_offset
    x, y = pos
    text_size, _ = cv2.getTextSize(msg, font, font_scale, font_thickness)
    text_w, text_h = text_size

    rec_start = tuple(p - o for p, o in zip(pos, offset))
    rec_end = tuple(m + n - o for m, n, o in zip((x + text_w, y + text_h), offset, (25, 0)))

    resize_height = 0

    if overlay_image:
        resize_height = rec_end[1] - rec_start[1]
        # print("Height: ", resize_height)
        # print("Width: ", rec_end[0] - rec_start[0])
        img = draw_rounded_rect(img, rec_start, (rec_end[0]+resize_height, rec_end[1]), width, text_color_bg)
        if overlay_type == "correct":
            overlay_res = cv2.resize(correct, (resize_height, resize_height), interpolation = cv2.INTER_AREA)		
        elif overlay_type == "incorrect":
            overlay_res = cv2.resize(incorrect, (resize_height, resize_height), interpolation = cv2.INTER_AREA)

        img[rec_start[1]:rec_start[1]+resize_height, rec_start[0]+width:rec_start[0]+width+resize_height] = overlay_res

    else:
        img = draw_rounded_rect(img, rec_start, rec_end, width, text_color_bg)


    cv2.putText(
        img,
        msg,
        (int(rec_start[0]+resize_height + 8), int(y + text_h + font_scale - 1)), 
        font,
        font_scale,
        text_color,
        font_thickness,
        cv2.LINE_AA,
    )

    
    
    return text_size



def find_angle(p1, p2, p3):
    p1 = np.array(p1)
    p2 = np.array(p2)
    p3 = np.array(p3)
    
    p1_ref = p1 - p2
    p2_ref = p3 - p2
    
    norm1 = np.linalg.norm(p1_ref)
    norm2 = np.linalg.norm(p2_ref)
    
    # --- BUG FIX: Prevent division by zero if landmarks overlap ---
    if norm1 == 0 or norm2 == 0:
        return 0.0 
        
    cos_theta = (np.dot(p1_ref, p2_ref)) / (norm1 * norm2)
    
    # Ensure cos_theta is clamped between -1 and 1 to avoid math crashes
    cos_theta = max(min(cos_theta, 1.0), -1.0) 
    
    theta = np.arccos(cos_theta)
    degree = int((180 / np.pi) * theta)
    return degree




def get_landmark_array(pose_landmark, key, frame_width, frame_height):

    denorm_x = int(pose_landmark[key].x * frame_width)
    denorm_y = int(pose_landmark[key].y * frame_height)

    return np.array([denorm_x, denorm_y])




def get_landmark_features(kp_results, dict_features, feature, frame_width, frame_height):

    if feature == 'nose':
        return get_landmark_array(kp_results, dict_features[feature], frame_width, frame_height)

    elif feature == 'left' or 'right':
        shldr_coord = get_landmark_array(kp_results, dict_features[feature]['shoulder'], frame_width, frame_height)
        elbow_coord   = get_landmark_array(kp_results, dict_features[feature]['elbow'], frame_width, frame_height)
        wrist_coord   = get_landmark_array(kp_results, dict_features[feature]['wrist'], frame_width, frame_height)
        hip_coord   = get_landmark_array(kp_results, dict_features[feature]['hip'], frame_width, frame_height)
        knee_coord   = get_landmark_array(kp_results, dict_features[feature]['knee'], frame_width, frame_height)
        ankle_coord   = get_landmark_array(kp_results, dict_features[feature]['ankle'], frame_width, frame_height)
        foot_coord   = get_landmark_array(kp_results, dict_features[feature]['foot'], frame_width, frame_height)

        return shldr_coord, elbow_coord, wrist_coord, hip_coord, knee_coord, ankle_coord, foot_coord
    
    else:
       raise ValueError("feature needs to be either 'nose', 'left' or 'right")


_MODEL_URLS = {
    0: 'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task',
    1: 'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task',
    2: 'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task',
}
_MODEL_FILES = {
    0: 'pose_landmarker_lite.task',
    1: 'pose_landmarker_full.task',
    2: 'pose_landmarker_heavy.task',
}

class _Landmark:
    __slots__ = ('x', 'y', 'z', 'visibility')
    def __init__(self, x, y, z, visibility=1.0):
        self.x = x
        self.y = y
        self.z = z
        self.visibility = visibility

class _LandmarkList:
    def __init__(self, landmarks):
        self.landmark = landmarks

class _PoseResult:
    def __init__(self, pose_landmarks):
        self.pose_landmarks = pose_landmarks

_SMOOTH_ALPHA = 0.5  # blend factor: 50% new detection, 50% previous smoothed value


class _PoseWrapper:
    """
    Wraps the MediaPipe Tasks PoseLandmarker so callers can use the old
    pose.process(bgr_frame) → result.pose_landmarks.landmark[i].x/y API.

    The PoseLandmarker is created lazily inside whichever thread first calls
    process(), using thread-local storage.  This avoids the crash that occurs
    when a TFLite model created in the Streamlit main thread is called from
    the WebRTC callback thread.

    Exponential moving average smoothing is applied to raw landmark positions
    to replicate the stabilisation that mp.solutions.pose provided via
    smooth_landmarks=True, which the new Tasks API dropped in IMAGE mode.
    """
    def __init__(self, model_file, min_det, min_trk):
        self._model_file = model_file
        self._min_det = min_det
        self._min_trk = min_trk
        self._key = f"{model_file}|{min_det}|{min_trk}"

    def _get_landmarker(self):
        if getattr(_pose_thread_local, 'key', None) != self._key:
            opts = mp.tasks.vision.PoseLandmarkerOptions(
                base_options=mp.tasks.BaseOptions(model_asset_path=self._model_file),
                running_mode=mp.tasks.vision.RunningMode.IMAGE,
                min_pose_detection_confidence=self._min_det,
                min_tracking_confidence=self._min_trk,
            )
            _pose_thread_local.lm  = mp.tasks.vision.PoseLandmarker.create_from_options(opts)
            _pose_thread_local.key = self._key
            _pose_thread_local.prev_lms = None  # reset smoothing buffer
        return _pose_thread_local.lm

    def process(self, frame):
        # frame is expected in BGR (OpenCV convention)
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = self._get_landmarker().detect(mp_img)

        if not result.pose_landmarks:
            _pose_thread_local.prev_lms = None  # reset on lost detection
            return _PoseResult(None)

        raw = [
            _Landmark(lm.x, lm.y, lm.z, getattr(lm, 'visibility', 1.0))
            for lm in result.pose_landmarks[0]
        ]

        # EMA smoothing: replaces the old smooth_landmarks=True behaviour
        prev = getattr(_pose_thread_local, 'prev_lms', None)
        if prev is not None and len(prev) == len(raw):
            a = _SMOOTH_ALPHA
            b = 1.0 - a
            lms = [
                _Landmark(a * r.x + b * p.x,
                          a * r.y + b * p.y,
                          a * r.z + b * p.z,
                          r.visibility)
                for r, p in zip(raw, prev)
            ]
        else:
            lms = raw

        _pose_thread_local.prev_lms = lms
        return _PoseResult(_LandmarkList(lms))


def get_mediapipe_pose(
    static_image_mode=False,
    model_complexity=1,
    smooth_landmarks=True,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5,
):
    model_file = _MODEL_FILES.get(model_complexity, _MODEL_FILES[1])
    if not os.path.exists(model_file):
        url = _MODEL_URLS.get(model_complexity, _MODEL_URLS[1])
        print(f"Downloading MediaPipe model: {model_file} …")
        urllib.request.urlretrieve(url, model_file)
        print("Download complete.")
    # Return a lightweight wrapper; the actual TFLite model is created lazily
    # inside process() on the calling thread (thread-safe).
    return _PoseWrapper(model_file, min_detection_confidence, min_tracking_confidence)