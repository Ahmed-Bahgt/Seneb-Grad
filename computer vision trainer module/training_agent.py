import time
import json
import google.generativeai as genai

# Configure your API key
# Get one for free at: https://aistudio.google.com/
genai.configure(api_key="YOUR_GEMINI_API_KEY")

def analyze_workout_video(video_path, json_path):
    print(f"Uploading {video_path} to the AI Agent...")
    
    # 1. Upload the video to the Gemini API
    video_file = genai.upload_file(path=video_path)
    
    # Wait for the video to be processed by the API
    while video_file.state.name == "PROCESSING":
        print(".", end="", flush=True)
        time.sleep(2)
        video_file = genai.get_file(video_file.name)
        
    if video_file.state.name == "FAILED":
        raise ValueError("Video processing failed.")
        
    print("\nVideo processed! Loading JSON data...")

    # --- NEW: 2. Load the JSON Data ---
    try:
        with open(json_path, 'r') as f:
            workout_data = json.load(f)
            # Convert the JSON dictionary into a nicely formatted string for the AI to read
            workout_json_string = json.dumps(workout_data, indent=2)
    except FileNotFoundError:
        workout_json_string = "No JSON data provided."
    # ---------------------------------

    print("Starting clinical analysis...")

    # 3. Define the Agent's Persona and Instructions (Updated to use the JSON)
    prompt = f"""
    You are an expert physiotherapist and clinical AI assistant.
    You have been provided with two things: a physical therapy exercise video, and the raw data 
    log (JSON) from the tracking engine.

    RAW WORKOUT DATA (USE THIS FOR ALL NUMBERS):
    {workout_json_string}

    Please provide a structured clinical report containing:
    1. SUMMARY STATISTICS: State the final numbers for Correct Reps, Incorrect Reps, 
       Effective Sets, and Total Sets completed. (Use the provided JSON data for these exact numbers).
    2. ERROR ANALYSIS: List the specific errors the trainee triggered. (Use the 'errors_triggered' list from the JSON).
    3. CLINICAL BREAKDOWN: Watch the video. Summarize the trainee's performance. When did their form start to break down? 
       Did they fatigue at the end of the sets? Describe exactly what their body was doing wrong when the errors triggered.
    4. DOCTOR'S RECOMMENDATION: Provide a short, actionable recommendation for the trainee's 
       next session based on the visual evidence.
    """

    # 4. Call the Multimodal Model
    model = genai.GenerativeModel(model_name="gemini-1.5-pro")
    
    response = model.generate_content([video_file, prompt])
    
    # 5. Clean up the file from the server
    genai.delete_file(video_file.name)
    
    return response.text

if __name__ == "__main__":
    # Now you pass BOTH files into the function!
    report = analyze_workout_video(
        video_path="output_live (14).flv", 
        json_path="workout_log.json"
    )
    
    print("\n" + "="*50)
    print("📋 CLINICAL WORKOUT REPORT")
    print("="*50)
    print(report)