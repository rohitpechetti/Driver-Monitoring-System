<<<<<<< HEAD
# Driver Monitoring System - Complete Documentation

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   MOBILE APP (Flutter)                   │
│  Login │ Register │ Detection │ Admin │ Super Admin      │
└───────────────────────┬─────────────────────────────────┘
                        │ REST API (HTTP/JSON)
┌───────────────────────▼─────────────────────────────────┐
│                  FLASK BACKEND (Python)                   │
│  Auth │ Logs │ Reports │ User Mgmt │ Email Alerts        │
└───────┬─────────────────────────────┬────────────────────┘
        │                             │
┌───────▼────────┐           ┌────────▼──────────┐
│ SQLite Database│           │  AI Detection     │
│  users table   │           │  OpenCV + MP      │
│  logs table    │           │  YOLOv8 Phone     │
└────────────────┘           └───────────────────┘
```

---

## Quick Start

### Backend
```bash
cd driver_ai_backend
chmod +x setup.sh && ./setup.sh
source venv/bin/activate
python app.py
# Server starts at http://localhost:5000
```

### Flutter App
```bash
cd driver_app
flutter pub get
flutter run
# For Android emulator: baseUrl = http://10.0.2.2:5000/api (already configured)
# For physical device: change baseUrl in lib/services/api_service.dart
```

---

## Default Credentials

| Role | Username | Password |
|------|----------|----------|
| Super Admin | `superadmin` | `superadmin123` |

Register additional users/admins through the app.

---

## Project Structure

```
driver_ai_backend/
├── app.py              # Flask app, all API endpoints
├── database.py         # SQLite with user & log management
├── detection.py        # OpenCV, MediaPipe, YOLOv8 engine
├── email_service.py    # Flask-Mail alert emails
├── requirements.txt    # Python dependencies
├── setup.sh            # Automated setup script
├── models/
│   └── yolov8n.pt      # YOLOv8 nano model (downloaded by setup)
└── screenshots/        # Captured incident screenshots

driver_app/
├── pubspec.yaml        # Flutter dependencies
├── android/
│   └── AndroidManifest.xml  # Required permissions
└── lib/
    ├── main.dart                     # App entry, routing, splash
    ├── screens/
    │   ├── login.dart                # Login screen
    │   ├── register.dart             # Registration with role selection
    │   ├── detection.dart            # Camera + AI alerts + logging
    │   ├── admin_dashboard.dart      # Dashboard, logs, reports
    │   └── superadmin_panel.dart     # User management, approvals
    └── services/
        └── api_service.dart          # All REST API calls
```

---

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/register` | Register new user |
| POST | `/api/login` | Authenticate user |
| POST | `/api/log-alert` | Log detection incident |
| GET | `/api/logs` | Get all logs (optional ?username=) |
| GET | `/api/stats` | Dashboard statistics |
| GET | `/api/reports/csv` | Download CSV report |
| GET | `/api/reports/pdf` | Download PDF report |
| GET | `/api/superadmin/pending-admins` | Pending admin approvals |
| POST | `/api/superadmin/approve/<id>` | Approve admin |
| DELETE | `/api/superadmin/reject/<id>` | Reject admin |
| GET | `/api/superadmin/users` | All users list |
| DELETE | `/api/superadmin/delete/<id>` | Delete user |
| GET | `/api/health` | Health check |

---

## Database Schema

### users
| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | Auto-increment |
| username | TEXT UNIQUE | |
| email | TEXT UNIQUE | |
| password | TEXT | SHA-256 hashed |
| role | TEXT | user / admin / superadmin |
| is_approved | INTEGER | 0=pending, 1=approved |
| created_at | TEXT | ISO timestamp |

### logs
| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | Auto-increment |
| username | TEXT | Driver's username |
| status | TEXT | Alert type |
| timestamp | TEXT | ISO timestamp |
| screenshot_path | TEXT | Local file path |

---

## AI Detection Algorithms

### Drowsiness (Eye Aspect Ratio)
```
EAR = (|P2-P6| + |P3-P5|) / (2 × |P1-P4|)
Alert when: EAR < 0.22 for 20 consecutive frames (~0.7s at 30fps)
```

### Distraction (Head Yaw)
```
Yaw = |nose.x - ear_midpoint.x| × 100
Alert when: yaw > 30 (degrees offset)
```

### Head Drop (Pitch)
```
Pitch Ratio = nose_to_chin / face_height
Alert when: pitch_ratio < 0.3 (head bowed forward)
```

### Phone Detection (YOLOv8)
```
YOLOv8n inference on each frame
Alert when: COCO class 67 (cell phone) detected with confidence > 0.4
```

### Face Absence
```
Alert when: no face detected for 15 consecutive frames
```

---

## Alert Types

| Alert | Trigger | Icon |
|-------|---------|------|
| Drowsiness Detected | EAR < threshold × time | 💤 |
| Driver Distracted | Head turned sideways | 👁️ |
| Phone Usage While Driving | YOLOv8 phone detection | 📱 |
| Head Drop Detected | Chin toward chest | ⬇️ |
| No Driver Detected | No face in frame | 🚫 |

---

## Role Access Matrix

| Feature | User | Admin | Super Admin |
|---------|------|-------|-------------|
| Register/Login | ✓ | ✓ | ✓ |
| Detection Screen | ✓ | ✓ | ✓ |
| Sound/Vibration Alerts | ✓ | ✓ | ✓ |
| View All Logs | | ✓ | ✓ |
| Download CSV/PDF | | ✓ | ✓ |
| Email Notifications | | ✓ | ✓ |
| Approve/Reject Admins | | | ✓ |
| Delete Users | | | ✓ |
| View All Users | | | ✓ |

---

## Email Configuration

Edit `.env` or set environment variables:
```
MAIL_SERVER=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=your_email@gmail.com
MAIL_PASSWORD=your_app_password  # Use Gmail App Password
```

For Gmail: Enable 2FA → Google Account → Security → App Passwords → Generate.

---

## Flutter Dependencies

| Package | Purpose |
|---------|---------|
| camera | Camera preview and capture |
| audioplayers | Alarm sound playback |
| vibration | Phone vibration patterns |
| shared_preferences | Session persistence |
| http | REST API communication |
| fl_chart | Dashboard statistics charts |
| intl | Date/time formatting |

---

## Production Deployment Notes

1. **Change secret key**: Set `SECRET_KEY` env variable in Flask
2. **HTTPS**: Use nginx + certbot for SSL in production
3. **Database**: Consider PostgreSQL for production scale
4. **Model**: Replace `yolov8n.pt` with `yolov8s.pt` for better accuracy
5. **API URL**: Update `baseUrl` in `api_service.dart` to production server
6. **Clear text traffic**: Remove `android:usesCleartextTraffic="true"` for HTTPS
7. **Password hashing**: Consider bcrypt instead of SHA-256 for stronger security

---

## Troubleshooting

| Issue | Solution |
|-------|---------|
| Camera not working | Add camera permission to AndroidManifest.xml |
| API connection refused | Check baseUrl, ensure Flask is running |
| Email not sending | Verify Gmail App Password, check MAIL_* env vars |
| YOLOv8 model missing | Run `python -c "from ultralytics import YOLO; YOLO('yolov8n.pt')"` |
| MediaPipe not found | `pip install mediapipe` |
| Android emulator URL | Use `10.0.2.2:5000` not `localhost:5000` |
=======
# Driver-Monitoring-System
>>>>>>> de5896b6454a161abfcf0cb017957b44f7267a89
