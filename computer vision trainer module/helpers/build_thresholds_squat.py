import cv2
import glob
import numpy as np
import mediapipe as mp
from utils import get_mediapipe_pose, get_landmark_features, find_angle

def calibrate_squats(video_folder):
    print(f"Starting unsupervised calibration on videos in '{video_folder}'...")
    
    pose = get_mediapipe_pose()
    video_files = glob.glob(f"{video_folder}/*.mp4") # Add other extensions if needed
    
    if not video_files:
        print("No videos found! Please add MP4 files to the calibration folder.")
        return

    # Arrays to hold all angles across all frames of all videos
    all_hip_angles = []
    all_knee_angles = []
    all_ankle_angles = []

    # --- 1. EXTRACT DATA ---
    for video in video_files:
        cap = cv2.VideoCapture(video)
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break
                
            frame_height, frame_width, _ = frame.shape
            results = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
            
            if results.pose_landmarks:
                ps_lm = results.pose_landmarks
                
                # Extract coordinates (assuming Left side facing camera for simplicity in calibration)
                _, _, _, hip_coord, knee_coord, ankle_coord, foot_coord = \
                    get_landmark_features(ps_lm.landmark, {'left': {'shoulder': 11, 'elbow': 13, 'wrist': 15, 'hip': 23, 'knee': 25, 'ankle': 27, 'foot': 31}, 'nose': 0}, 'left', frame_width, frame_height)
                
                shldr_coord = get_landmark_features(ps_lm.landmark, {'left': {'shoulder': 11, 'elbow': 13, 'wrist': 15, 'hip': 23, 'knee': 25, 'ankle': 27, 'foot': 31}, 'nose': 0}, 'left', frame_width, frame_height)[0]

                # Calculate Vertical Angles (Same math as your ProcessFrameSquat)
                hip_angle = find_angle(shldr_coord, np.array([hip_coord[0], 0]), hip_coord)
                knee_angle = find_angle(hip_coord, np.array([knee_coord[0], 0]), knee_coord)
                ankle_angle = find_angle(knee_coord, np.array([ankle_coord[0], 0]), ankle_coord)

                all_hip_angles.append(hip_angle)
                all_knee_angles.append(knee_angle)
                all_ankle_angles.append(ankle_angle)
                
        cap.release()

    # Convert to numpy arrays for statistical math
    all_hip_angles = np.array(all_hip_angles)
    all_knee_angles = np.array(all_knee_angles)
    all_ankle_angles = np.array(all_ankle_angles)

    # --- 2. UNSUPERVISED CLUSTERING (Histogram Peaks) ---
    # In a perfect squat, the knee angle has two massive statistical peaks:
    # Peak 1: Standing (Legs straight, angle > 150)
    # Peak 2: Deep Squat (Legs bent, angle < 110)
    
    standing_mask = all_knee_angles > 150
    squatting_mask = all_knee_angles < 110

    # Calculate Mean (mu) and Standard Deviation (sigma) for the Deep Squat Phase
    mu_knee_squat = np.mean(all_knee_angles[squatting_mask])
    sigma_knee_squat = np.std(all_knee_angles[squatting_mask])
    
    mu_hip_squat = np.mean(all_hip_angles[squatting_mask])
    sigma_hip_squat = np.std(all_hip_angles[squatting_mask])
    
    # Calculate Mean and Std for Standing Phase
    mu_knee_stand = np.mean(all_knee_angles[standing_mask])
    sigma_knee_stand = np.std(all_knee_angles[standing_mask])

    print("\n--- STATISTICAL RESULTS ---")
    print(f"Deep Squat Knee: Mean = {mu_knee_squat:.1f}, StdDev = {sigma_knee_squat:.1f}")
    print(f"Deep Squat Hip: Mean = {mu_hip_squat:.1f}, StdDev = {sigma_hip_squat:.1f}")
    print(f"Standing Knee: Mean = {mu_knee_stand:.1f}, StdDev = {sigma_knee_stand:.1f}")

    # --- 3. GENERATE DICTIONARIES ---
    # We use: Threshold = Mean +/- (Multiplier * StdDev)
    # Pro = Strict (1 Standard Deviation)
    # Beginner = Forgiving (2.5 Standard Deviations)
    
    def create_dict(std_multiplier):
        return {
            'HIP_KNEE_VERT': {
                'NORMAL': (int(mu_knee_stand - std_multiplier*sigma_knee_stand), 180), 
                'TRANS': (int(mu_knee_squat + std_multiplier*sigma_knee_squat), int(mu_knee_stand - std_multiplier*sigma_knee_stand)), 
                'PASS': (int(mu_knee_squat - std_multiplier*sigma_knee_squat), int(mu_knee_squat + std_multiplier*sigma_knee_squat)) 
            },
            'HIP_THRESH': [int(mu_hip_squat - std_multiplier*sigma_hip_squat), int(mu_hip_squat + std_multiplier*sigma_hip_squat)],
            # Knee threshold array maps to: [Normal max, Pass max, Failing deep max]
            'KNEE_THRESH': [int(mu_knee_stand - std_multiplier*sigma_knee_stand), int(mu_knee_squat + std_multiplier*sigma_knee_squat), int(mu_knee_squat - (std_multiplier+1)*sigma_knee_squat)],
            'ANKLE_THRESH': 45, # Usually static based on physics, but can be clustered too
            'OFFSET_THRESH': 35.0,
            'INACTIVE_THRESH': 15.0
        }

    print("\n--- PASTE THIS INTO thresholds.py ---")
    print("def get_thresholds_squats_pro():")
    print("    return", create_dict(1.0))
    print("\ndef get_thresholds_squats_beginner():")
    print("    return", create_dict(2.5))

if __name__ == "__main__":
    # Ensure you have a folder named 'calibration_videos' with some perfect squat mp4s inside
    calibrate_squats("calibration_videos")