# ══════════════════════════════════════════════════════════════
# Tamren Tech — Production Dockerfile for Hugging Face Spaces
# CPU-only PyTorch | PostgreSQL backend | Optimized build
# ══════════════════════════════════════════════════════════════
FROM python:3.11-slim

# ── System dependencies ────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# ── Set up non-root user (Hugging Face requires UID 1000) ──────
RUN useradd -m -u 1000 user

# ── Working directory ──────────────────────────────────────────
WORKDIR /app

# ── Install CPU-only PyTorch FIRST (separate layer for caching) ─
# This is much smaller than the default CUDA build
RUN pip install --no-cache-dir \
    torch==2.2.2+cpu \
    torchvision==0.17.2+cpu \
    --index-url https://download.pytorch.org/whl/cpu

# ── Install mediapipe (needs separate install on linux) ─────────
RUN pip install --no-cache-dir mediapipe==0.10.14

# ── Copy & install the rest of dependencies ────────────────────
COPY custom_backend/requirements.server.txt .
RUN pip install --no-cache-dir -r requirements.server.txt --default-timeout=120

# ── Copy application code with proper ownership ───────────────
COPY --chown=user:user custom_backend/ ./custom_backend/
COPY --chown=user:user ["radilogy repoprt generation/", "./radilogy repoprt generation/"]

# ── Set up writable directories for temp files ─────────────────
RUN mkdir -p /app/custom_backend/temp /app/custom_backend/temp_charts && \
    chown -R user:user /app && \
    chmod -R 777 /app/custom_backend/temp /app/custom_backend/temp_charts

# ── Switch to Hugging Face user ────────────────────────────────
USER user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH

WORKDIR /app/custom_backend

# ── Expose port 7860 (Hugging Face Spaces default port) ────────
EXPOSE 7860

# ── Start uvicorn server on port 7860 ──────────────────────────
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "7860", "--workers", "2"]
