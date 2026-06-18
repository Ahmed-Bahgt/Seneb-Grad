#!/bin/bash
# ══════════════════════════════════════════════════════════════
# Tamren Tech — Hetzner Server Setup & Deploy Script
# Run this ONCE on a fresh Ubuntu 22.04 Hetzner server
# Usage: bash deploy.sh
# ══════════════════════════════════════════════════════════════

set -e  # Exit on any error

echo "╔══════════════════════════════════════════════════╗"
echo "║   Tamren Tech — Server Deployment Script         ║"
echo "╚══════════════════════════════════════════════════╝"

# ── Step 1: System update ─────────────────────────────────────
echo ""
echo "[1/7] Updating system packages..."
apt-get update -y && apt-get upgrade -y

# ── Step 2: Install Docker ────────────────────────────────────
echo ""
echo "[2/7] Installing Docker..."
if ! command -v docker &> /dev/null; then
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo "✅ Docker installed."
else
    echo "✅ Docker already installed."
fi

# ── Step 3: Install Git ────────────────────────────────────────
echo ""
echo "[3/7] Installing Git..."
apt-get install -y git
echo "✅ Git installed."

# ── Step 4: Configure firewall ───────────────────────────────
echo ""
echo "[4/7] Configuring firewall..."
# Allow SSH (keep existing connection alive)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
# Allow HTTP
iptables -A INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
# Allow HTTPS (for future SSL)
iptables -A INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
echo "✅ Firewall configured."

# ── Step 5: Clone / pull the project ─────────────────────────
echo ""
echo "[5/7] Setting up project..."
PROJECT_DIR="/opt/tamren_tech"

if [ -d "$PROJECT_DIR" ]; then
    echo "Project directory exists, pulling latest changes..."
    cd "$PROJECT_DIR"
    git pull
else
    echo "Cloning project..."
    # ⚠️  REPLACE THIS WITH YOUR GITHUB REPO URL
    # git clone https://github.com/YOUR_USERNAME/tamren_tech.git "$PROJECT_DIR"
    # OR copy files manually via SCP — see instructions below
    mkdir -p "$PROJECT_DIR"
    echo "⚠️  Project directory created at $PROJECT_DIR"
    echo "    Please copy your project files using SCP (see instructions)"
fi

cd "$PROJECT_DIR"

# ── Step 6: Create .env file ──────────────────────────────────
echo ""
echo "[6/7] Setting up environment variables..."
if [ ! -f ".env" ]; then
    if [ -f ".env.production.example" ]; then
        cp .env.production.example .env
        echo ""
        echo "⚠️  IMPORTANT: Edit the .env file with your real values!"
        echo "    Run: nano /opt/tamren_tech/.env"
        echo ""
        echo "    Required values to fill:"
        echo "    - POSTGRES_PASSWORD (choose a strong password)"
        echo "    - SECRET_KEY (random string)"
        echo "    - GEMINI_API_KEY"
        echo "    - OPENROUTER_API_KEY"
        echo ""
        read -p "Press ENTER after editing .env to continue..." 
    else
        echo "❌ .env.production.example not found!"
        echo "   Please create .env manually."
        exit 1
    fi
else
    echo "✅ .env file already exists."
fi

# ── Step 7: Build and start containers ───────────────────────
echo ""
echo "[7/7] Building Docker image and starting services..."
echo "      (This may take 10-20 minutes on first run due to PyTorch download)"
echo ""
docker compose up -d --build

# ── Wait for health check ─────────────────────────────────────
echo ""
echo "Waiting for backend to start..."
sleep 10

MAX_TRIES=20
COUNT=0
while [ $COUNT -lt $MAX_TRIES ]; do
    if curl -s http://localhost/  > /dev/null 2>&1; then
        echo ""
        echo "╔══════════════════════════════════════════════════╗"
        echo "║   ✅  DEPLOYMENT SUCCESSFUL!                     ║"
        echo "╠══════════════════════════════════════════════════╣"
        echo "║                                                  ║"
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
        echo "║   🌐  Public URL: http://$SERVER_IP"
        echo "║   📊  API Docs:   http://$SERVER_IP/docs"
        echo "║                                                  ║"
        echo "║   Update api_config.dart baseUrl to:            ║"
        echo "║   http://$SERVER_IP                             ║"
        echo "║                                                  ║"
        echo "╚══════════════════════════════════════════════════╝"
        break
    fi
    COUNT=$((COUNT + 1))
    echo "  Waiting... ($COUNT/$MAX_TRIES)"
    sleep 10
done

if [ $COUNT -eq $MAX_TRIES ]; then
    echo ""
    echo "⚠️  Server is taking longer than expected."
    echo "    Check logs with: docker compose logs backend"
fi

echo ""
echo "Useful commands:"
echo "  View logs:      docker compose logs -f backend"
echo "  Restart:        docker compose restart"
echo "  Stop:           docker compose down"
echo "  Rebuild:        docker compose up -d --build"
