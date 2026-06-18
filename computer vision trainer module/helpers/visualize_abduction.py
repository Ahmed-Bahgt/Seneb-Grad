import numpy as np
import plotly.graph_objects as go
from scipy.stats import norm

def plot_interactive_calibration():
    # 1. Your Custom Data
    mu_rest, sigma_rest = 28.6, 8.6
    mu_peak, sigma_peak = 89.1, 12.4

    # 2. Generate the X-axis (Angles from 0 to 150 degrees)
    x = np.linspace(0, 150, 500)

    # 3. Generate the Y-axis (The Bell Curves)
    y_rest = norm.pdf(x, mu_rest, sigma_rest)
    y_peak = norm.pdf(x, mu_peak, sigma_peak)

    # 4. Create the Interactive Plot
    fig = go.Figure()

    # Add Resting Curve
    fig.add_trace(go.Scatter(x=x, y=y_rest, mode='lines', name='Resting Phase', 
                             line=dict(color='cyan', width=3), fill='tozeroy', opacity=0.5))
    
    # Add Peak Curve
    fig.add_trace(go.Scatter(x=x, y=y_peak, mode='lines', name='Peak Abduction Phase', 
                             line=dict(color='magenta', width=3), fill='tozeroy', opacity=0.5))

    # 5. Add Custom Colored Zones (Your Thresholds)
    fig.add_vrect(x0=0, x1=45, fillcolor="green", opacity=0.1, line_width=0, annotation_text="NORMAL (0-45)")
    fig.add_vrect(x0=45, x1=64, fillcolor="yellow", opacity=0.1, line_width=0, annotation_text="TRANSITION (45-64)")
    fig.add_vrect(x0=64, x1=113, fillcolor="orange", opacity=0.1, line_width=0, annotation_text="PASS/HOLD (64-113)")
    fig.add_vrect(x0=113, x1=150, fillcolor="red", opacity=0.1, line_width=0, annotation_text="TOO HIGH (>113)")

    # 6. Styling
    fig.update_layout(
        title="Unsupervised Biomechanical Calibration: Resisted Abduction",
        xaxis_title="Shoulder Angle (Degrees)",
        yaxis_title="Probability Density",
        template="plotly_dark",
        hovermode="x unified"
    )

    # Opens an interactive HTML file in your browser!
    fig.show()

if __name__ == "__main__":
    plot_interactive_calibration()