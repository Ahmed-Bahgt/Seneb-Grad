import cv2
import glob
import numpy as np
import mediapipe as mp
from utils import get_mediapipe_pose, get_landmark_features, find_angle

def calibrate_abduction(video_folder):
    print(f"Starting unsupervised calibration for Abduction in '{video_folder}'...")
    
    pose = get_mediapipe_pose()
    video_files = glob.glob(f"{video_folder}/*.mp4") 
    
    if not video_files:
        print("No videos found! Please add MP4 files to the calibration folder.")
        return

    all_shoulder_angles = []

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
                
                # 1. Define the full dictionary containing both left and right sides
                dict_features = {
                    'left': {'shoulder': 11, 'elbow': 13, 'wrist': 15, 'hip': 23, 'knee': 25, 'ankle': 27, 'foot': 31},
                    'right': {'shoulder': 12, 'elbow': 14, 'wrist': 16, 'hip': 24, 'knee': 26, 'ankle': 28, 'foot': 32},
                    'nose': 0
                }
                
                # 2. Extract coordinates using the full dictionary
                left_shldr_coord, left_elbow_coord, _, left_hip_coord, _, _, _ = \
                    get_landmark_features(ps_lm.landmark, dict_features, 'left', frame_width, frame_height)
                
                right_shldr_coord, right_elbow_coord, _, right_hip_coord, _, _, _ = \
                    get_landmark_features(ps_lm.landmark, dict_features, 'right', frame_width, frame_height)

                # Calculate Angles
                left_shoulder_angle = find_angle(left_hip_coord, left_elbow_coord, left_shldr_coord)
                right_shoulder_angle = find_angle(right_hip_coord, right_elbow_coord, right_shldr_coord)
                
                # We use the average of both arms to find the general state of the rep
                avg_shoulder_angle = (left_shoulder_angle + right_shoulder_angle) / 2
                all_shoulder_angles.append(avg_shoulder_angle)
                
        cap.release()

    all_shoulder_angles = np.array(all_shoulder_angles)

    # --- 2. UNSUPERVISED CLUSTERING ---
    # Arms resting at sides are usually < 45 degrees
    # Arms at peak abduction are usually > 65 degrees
    resting_mask = all_shoulder_angles < 45
    peak_mask = all_shoulder_angles > 65

    mu_rest = np.mean(all_shoulder_angles[resting_mask])
    sigma_rest = np.std(all_shoulder_angles[resting_mask])
    
    mu_peak = np.mean(all_shoulder_angles[peak_mask])
    sigma_peak = np.std(all_shoulder_angles[peak_mask])

    print("\n--- STATISTICAL RESULTS ---")
    print(f"Resting Arms: Mean = {mu_rest:.1f}, StdDev = {sigma_rest:.1f}")
    print(f"Peak Abduction: Mean = {mu_peak:.1f}, StdDev = {sigma_peak:.1f}")

    # --- 3. GENERATE DICTIONARIES ---
    def create_dict(std_multiplier):
        return {
            'SHOULDER_ABDUCTION': {
                'NORMAL': (0, int(mu_rest + std_multiplier*sigma_rest)), 
                'TRANS': (int(mu_rest + std_multiplier*sigma_rest), int(mu_peak - std_multiplier*sigma_peak)), 
                'PASS': (int(mu_peak - std_multiplier*sigma_peak), int(mu_peak + std_multiplier*sigma_peak)) 
            },
            # This is the ONLY dynamic failure threshold based on the data
            'ARMS_TOO_HIGH': int(mu_peak + (std_multiplier * sigma_peak)), 
            
            # These are static because they are just visual cautions now
            'ELBOW_BENT_THRESH': 140,  
            'ASYMMETRY_THRESH': 20,    
            'OFFSET_THRESH': 35.0,     
            'INACTIVE_THRESH': 15.0,
            'BACK_THRESH': 10          
        }

    print("\n--- PASTE THIS INTO thresholds.py ---")
    print("def get_thresholds_abduction():")
    print("    return", create_dict(2.0)) # z = 2.0 gives a good natural leeway

if __name__ == "__main__":
    calibrate_abduction("calibration_abduction_videos")