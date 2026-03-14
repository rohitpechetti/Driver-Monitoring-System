#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Driver Monitoring System – Backend Setup Script
# Run from driver_ai_backend/ directory
# ─────────────────────────────────────────────────────────────

set -e
echo ""
echo "  ██████╗ ██████╗ ██╗██╗   ██╗███████╗██████╗ "
echo "  ██╔══██╗██╔══██╗██║██║   ██║██╔════╝██╔══██╗"
echo "  ██║  ██║██████╔╝██║██║   ██║█████╗  ██████╔╝"
echo "  ██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝  ██╔══██╗"
echo "  ██████╔╝██║  ██║██║ ╚████╔╝ ███████╗██║  ██║"
echo "  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝"
echo ""
echo "  AI Driver Monitoring System - Backend Setup"
echo "═══════════════════════════════════════════════"

# Python version check
python3 --version || { echo "[ERROR] Python 3 not found"; exit 1; }

# Virtual environment
echo ""
echo "[1/5] Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Dependencies
echo ""
echo "[2/5] Installing Python dependencies..."
pip install --upgrade pip -q
pip install -r requirements.txt

# YOLOv8 model
echo ""
echo "[3/5] Downloading YOLOv8n model..."
mkdir -p models
if [ ! -f "models/yolov8n.pt" ]; then
    python3 -c "from ultralytics import YOLO; YOLO('yolov8n.pt')" 2>/dev/null && \
        mv yolov8n.pt models/ 2>/dev/null || \
        echo "  [WARN] Could not auto-download. Place yolov8n.pt in models/ manually."
else
    echo "  models/yolov8n.pt already exists."
fi

# Screenshots directory
echo ""
echo "[4/5] Creating screenshots directory..."
mkdir -p screenshots

# Environment file
echo ""
echo "[5/5] Creating .env template..."
if [ ! -f ".env" ]; then
cat > .env << 'ENV'
# Flask Mail configuration
MAIL_SERVER=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=your_email@gmail.com
MAIL_PASSWORD=your_app_password
ENV
    echo "  .env created – edit it with your email credentials"
else
    echo "  .env already exists"
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "  Setup complete!"
echo ""
echo "  To start the server:"
echo "    source venv/bin/activate"
echo "    python app.py"
echo ""
echo "  Default Super Admin credentials:"
echo "    Username: superadmin"
echo "    Password: superadmin123"
echo "═══════════════════════════════════════════════"
