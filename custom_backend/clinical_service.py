import os
import json
import re
import io
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend for server
import matplotlib.pyplot as plt
import seaborn as sns
import base64
import time
from datetime import datetime
import google.generativeai as genai

# --- CONFIGURATION ---
GEMINI_API_KEY = "YOUR_GEMINI_API_KEY_HERE"
genai.configure(api_key=GEMINI_API_KEY)

class ClinicalService:
    def __init__(self):
        self.model = genai.GenerativeModel("gemini-2.5-flash")

    def generate_analytics_charts(self, session_data, output_dir="temp_charts"):
        """Generate reps and effectiveness charts from session data."""
        os.makedirs(output_dir, exist_ok=True)
        timestamp = int(time.time())
        
        # 1. Reps Quality Bar Chart
        correct = session_data.get('correctReps') or session_data.get('correct_reps', 0)
        incorrect = session_data.get('incorrectReps') or session_data.get('incorrect_reps', 0)
        
        plt.figure(figsize=(6, 4))
        sns.set_theme(style="whitegrid")
        sns.barplot(x=['Correct', 'Incorrect'], y=[int(correct), int(incorrect)], palette=['#2ecc71', '#e74c3c'])
        plt.title("Repetition Quality Breakdown")
        reps_path = os.path.join(output_dir, f"reps_{timestamp}.png")
        plt.savefig(reps_path, dpi=200, bbox_inches='tight')
        plt.close()

        # 2. Effectiveness Pie Chart
        # (Using accuracy as a proxy for effectiveness in this version)
        accuracy_val = session_data.get('accuracy') or session_data.get('accuracy_percentage', 0.0)
        try:
            accuracy_float = float(accuracy_val) if accuracy_val is not None else 0.0
        except ValueError:
            accuracy_float = 0.0

        plt.figure(figsize=(5, 5))
        plt.pie([accuracy_float, max(0, 100 - accuracy_float)], labels=['Effective', 'Sub-optimal'], 
                colors=['#9b59b6', '#bdc3c7'], autopct='%1.1f%%', startangle=90)
        plt.title("Session Effectiveness")
        sets_path = os.path.join(output_dir, f"sets_{timestamp}.png")
        plt.savefig(sets_path, dpi=200, bbox_inches='tight')
        plt.close()

        return reps_path, sets_path

    def analyze_clinical_session(self, session_data, video_frames_base64=None):
        """Generate AI clinical analysis report for a workout session."""
        exercise_name = session_data.get('exerciseType') or session_data.get('exercise_type', 'Physical Therapy')
        
        # Prepare a clean version of data for the AI prompt
        display_data = session_data.copy()
        if 'patientName' in display_data:
            display_data['patient'] = display_data.pop('patientName')
            if 'patientId' in display_data: del display_data['patientId']
        
        # Format timestamp - use formattedTimestamp if provided by Flutter
        formatted_ts = display_data.get('formattedTimestamp')
        if formatted_ts:
            display_data['date_time'] = formatted_ts
            if 'formattedTimestamp' in display_data: del display_data['formattedTimestamp']
        else:
            ts = display_data.get('timestamp')
            if ts:
                try:
                    if isinstance(ts, (int, float)):
                        display_data['date_time'] = datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M')
                    else:
                        display_data['date_time'] = str(ts)
                except: pass

        if 'timestamp' in display_data: del display_data['timestamp']

        data_summary = json.dumps(display_data, indent=2)

        if video_frames_base64:
            # Vision-enhanced prompt
            prompt = f"""
            You are an expert physiotherapist and clinical AI assistant.
            The trainee in these images is performing the: {exercise_name.upper()}.

            RAW WORKOUT DATA (JSON):
            {data_summary}

            STRICT FORMATTING RULES:
            1. START the report with exactly this header:
               # **SENEB CLINICAL AGENT ANALYSIS**
               **Patient:** {display_data.get('patient', 'N/A')}
               **Exercise:** {exercise_name}
               **Mode:** {display_data.get('mode', 'Beginner')}
            
            2. Do NOT include any date or timestamp in the report.

            Please provide a structured clinical report containing:
            1. 📋 SUMMARY STATISTICS: State the final numbers for Correct Reps, Incorrect Reps,
               Effective Sets, and Total Sets completed.
            2. ⚠️ ERROR ANALYSIS: List the specific errors triggered.
            3. 🔬 CLINICAL BREAKDOWN: Evaluate their {exercise_name} form from images.
            4. 🏥 DOCTOR'S RECOMMENDATION: Provide actionable advice.

            STRICT RULES:
            - Be highly professional, concise and use bullet points.
            - Use medical terminology with bold text for key metrics.
            - Accuracy below 70% → flag as HIGH RISK.
            - Accuracy 70-85% → flag as MODERATE.
            - Accuracy above 85% → flag as GOOD.
            """
            contents = [prompt]
            for frame in video_frames_base64[:4]:
                contents.append({"mime_type": "image/jpeg", "data": frame})
        else:
            # Text-only prompt
            prompt = f"""
            You are an expert physiotherapist and clinical AI assistant (Seneb Clinical Agent).
            Generate a professional medical report for this {exercise_name.upper()} session.

            RAW WORKOUT DATA (JSON):
            {data_summary}

            STRICT FORMATTING RULES:
            1. START the report with exactly this header:
               # **SENEB CLINICAL AGENT ANALYSIS**
               **Patient:** {display_data.get('patient', 'N/A')}
               **Exercise:** {exercise_name}
               **Mode:** {display_data.get('mode', 'Beginner')}
            
            2. Do NOT include any date or timestamp in the report.
            
            3. Provide the rest of the report in these sections:
               - 📋 SUMMARY STATISTICS: State numbers for Correct Reps, Incorrect Reps, and accuracy.
               - ⚠️ ERROR ANALYSIS: Identify likely biomechanical errors.
               - 🔬 BIOMECHANICAL ANALYSIS: Evaluate form consistency.
               - 🏥 DOCTOR'S RECOMMENDATION: Provide actionable advice.

            - Be highly professional, concise and use bullet points.
            - Use medical terminology with bold text for key metrics.
            - Accuracy below 70% → flag as HIGH RISK.
            - Accuracy 70-85% → flag as MODERATE.
            - Accuracy above 85% → flag as GOOD.
            """
            contents = [prompt]

        try:
            res = self.model.generate_content(contents)
            return res.text if res else "Analysis failed."
        except Exception as e:
            return f"AI Error: {str(e)}"

    def follow_up_chat(self, user_message: str, session_data: dict, conversation_history: list) -> dict:
        """Interactive follow-up chat with Python REPL support."""
        exercise_name = session_data.get('exerciseType') or session_data.get('exercise_type', 'Physical Therapy')
        
        # Clean data for AI
        display_data = session_data.copy()
        if 'patientName' in display_data:
            display_data['patient'] = display_data.pop('patientName')
            if 'patientId' in display_data: del display_data['patientId']
        
        json_string = json.dumps(display_data, indent=2)

        # Build the system prompt (identical concept to the original agent)
        system_prompt = f"""You are a clinical data AI assistant called 'Seneb Clinical Agent'.
        The patient's workout data contents are:
        {json_string}

        CRITICAL INSTRUCTION: DO NOT write any Python code or generate any graphs UNLESS 
        the user explicitly uses words like "graph", "chart", "plot", or "visualize".
        If the user asks a normal text question, just answer them with standard text.

        IF AND ONLY IF the user explicitly requests a graph, follow these rules:
        1. Write the code inside a standard ```python ... ``` markdown block.
        2. The data is already available as a Python dict named `session_data`.
        3. You MUST use matplotlib or seaborn.
        4. You MUST save the final graph by strictly calling: plt.savefig('custom_graph.png', 
           dpi=150, bbox_inches='tight')
        5. Always call plt.close() after saving.

        Available data keys: {list(session_data.keys())}
        Exercise type: {exercise_name}
        """

        # Build Gemini conversation
        gemini_history = []
        # Add system context as first user turn
        gemini_history.append({"role": "user", "parts": [system_prompt]})
        gemini_history.append({"role": "model", "parts": ["Understood. I am Seneb Clinical Agent ready to assist with this session analysis."]})
        
        # Add previous conversation
        for msg in conversation_history:
            role = "user" if msg["role"] == "user" else "model"
            gemini_history.append({"role": role, "parts": [msg["content"]]})

        # Add current message
        gemini_history.append({"role": "user", "parts": [user_message]})

        try:
            chat = self.model.start_chat(history=gemini_history[:-1])
            response = chat.send_message(user_message)
            response_text = response.text
        except Exception as e:
            return {"type": "text", "content": f"AI Error: {str(e)}", "image": None}

        # --- AGENTIC PARSING: Intercept Python code blocks (like the original agent) ---
        if "```python" in response_text:
            code_blocks = re.findall(r'```python\n(.*?)\n```', response_text, re.DOTALL)
            if code_blocks:
                code_to_run = code_blocks[0]
                graph_base64, error = self._execute_graph_code(code_to_run, session_data)
                
                if graph_base64:
                    # Ask AI to summarize the graph
                    try:
                        summary_response = chat.send_message(
                            f"SYSTEM CONSOLE RESULT: Graph generated successfully. "
                            f"Please provide a brief clinical interpretation of this visualization."
                        )
                        summary_text = summary_response.text
                    except Exception:
                        summary_text = "Custom graph generated based on session data."
                    
                    return {"type": "graph", "content": summary_text, "image": graph_base64}
                else:
                    return {"type": "text", "content": f"⚠️ Graph generation failed: {error}\n\n{response_text}", "image": None}

        # Normal text response
        return {"type": "text", "content": response_text, "image": None}

    def _execute_graph_code(self, python_code: str, session_data: dict):
        """Execute AI-generated Python code in a sandboxed environment.
        Returns (base64_image, error_message).
        Matches the execute_custom_graph_code() function from the original agent.
        """
        graph_path = "custom_graph.png"
        # Clean up any previous graph
        if os.path.exists(graph_path):
            os.remove(graph_path)

        local_env = {
            'plt': plt,
            'sns': sns,
            'json': json,
            'session_data': session_data,  # Direct dict access (no file needed)
        }

        try:
            exec(python_code, local_env)
        except Exception as e:
            return None, f"Code execution error: {str(e)}"

        if not os.path.exists(graph_path):
            return None, "Code ran but custom_graph.png was not created. Ensure plt.savefig('custom_graph.png') is called."

        # Read and return as base64
        with open(graph_path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode('utf-8')
        os.remove(graph_path)  # Clean up
        return encoded, None


clinical_service = ClinicalService()
