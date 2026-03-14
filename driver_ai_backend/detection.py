"""
AI Detection Engine — compatible with MediaPipe 0.10+ (Tasks API)
and falls back gracefully if MediaPipe or YOLOv8 are not installed.
"""

import cv2
import numpy as np
import time
import base64
import os
from typing import Optional, Dict, Any

# ── MediaPipe 0.10+ Tasks API ──────────────────────────────────────────────────
try:
    import mediapipe as mp
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision as mp_vision
    from mediapipe.tasks.python.vision import FaceLandmarkerOptions, FaceLandmarker, RunningMode
    MEDIAPIPE_AVAILABLE = True
    print("[Detection] MediaPipe Tasks API available")
except Exception as e:
    MEDIAPIPE_AVAILABLE = False
    print(f"[Detection] MediaPipe not available: {e}")

# ── YOLOv8 ────────────────────────────────────────────────────────────────────
try:
    from ultralytics import YOLO
    YOLO_AVAILABLE = True
    print("[Detection] YOLOv8 available")
except ImportError:
    YOLO_AVAILABLE = False
    print("[Detection] YOLOv8 not available")

LEFT_EYE  = [362, 385, 387, 263, 373, 380]
RIGHT_EYE = [33,  160, 158, 133, 153, 144]
NOSE_TIP      = 1
LEFT_EAR_IDX  = 234
RIGHT_EAR_IDX = 454
CHIN          = 152
FOREHEAD      = 10

_HERE = os.path.dirname(os.path.abspath(__file__))
FACE_LANDMARKER_MODEL = os.path.join(_HERE, "models", "face_landmarker.task")


def _euclidean(p1, p2) -> float:
    return np.sqrt((p1[0] - p2[0]) ** 2 + (p1[1] - p2[1]) ** 2)


def compute_ear(landmarks, eye_indices: list, w: int, h: int) -> float:
    pts = [(landmarks[i].x * w, landmarks[i].y * h) for i in eye_indices]
    A = _euclidean(pts[1], pts[5])
    B = _euclidean(pts[2], pts[4])
    C = _euclidean(pts[0], pts[3])
    return (A + B) / (2.0 * C) if C != 0 else 0.0


def _download_face_landmarker():
    os.makedirs(os.path.join(_HERE, "models"), exist_ok=True)
    if os.path.exists(FACE_LANDMARKER_MODEL):
        return True
    try:
        import urllib.request
        url = (
            "https://storage.googleapis.com/mediapipe-models/"
            "face_landmarker/face_landmarker/float16/1/face_landmarker.task"
        )
        print("[Detection] Downloading face_landmarker.task ...")
        urllib.request.urlretrieve(url, FACE_LANDMARKER_MODEL)
        print(f"[Detection] Saved to {FACE_LANDMARKER_MODEL}")
        return True
    except Exception as e:
        print(f"[Detection] Could not download face_landmarker.task: {e}")
        return False


class DetectionEngine:
    EAR_THRESHOLD      = 0.22
    EAR_CONSEC_FRAMES  = 20
    HEAD_YAW_THRESHOLD = 30
    ABSENT_FACE_FRAMES = 15
    COOLDOWN_SECONDS   = 5.0

    def __init__(self, yolo_model_path: str = None):
        if yolo_model_path is None:
            yolo_model_path = os.path.join(_HERE, "models", "yolov8n.pt")
        self.yolo_model_path  = yolo_model_path
        self.face_landmarker  = None
        self._init_mediapipe()
        self._init_yolo()
        self.ear_counter    = 0
        self.absent_counter = 0
        self.alert_cooldown: Dict[str, float] = {}

    def _init_mediapipe(self):
        if not MEDIAPIPE_AVAILABLE:
            return
        try:
            if not _download_face_landmarker():
                print("[Detection] Face landmarker model unavailable")
                return
            base_options = mp_python.BaseOptions(model_asset_path=FACE_LANDMARKER_MODEL)
            options = FaceLandmarkerOptions(
                base_options=base_options,
                running_mode=RunningMode.IMAGE,
                num_faces=1,
                min_face_detection_confidence=0.5,
                min_face_presence_confidence=0.5,
                min_tracking_confidence=0.5,
            )
            self.face_landmarker = FaceLandmarker.create_from_options(options)
            print("[Detection] MediaPipe FaceLandmarker ready")
        except Exception as e:
            print(f"[Detection] FaceLandmarker init failed: {e}")
            self.face_landmarker = None

    def _init_yolo(self):
        if not YOLO_AVAILABLE:
            self.yolo = None
            return
        try:
            self.yolo = YOLO(self.yolo_model_path)
            print(f"[Detection] YOLOv8 loaded")
        except Exception as e:
            print(f"[Detection] YOLOv8 load failed: {e}")
            self.yolo = None

    def _cooldown_ok(self, alert_type: str) -> bool:
        now  = time.time()
        last = self.alert_cooldown.get(alert_type, 0)
        if now - last >= self.COOLDOWN_SECONDS:
            self.alert_cooldown[alert_type] = now
            return True
        return False

    def analyze_frame(self, frame: np.ndarray) -> Dict[str, Any]:
        result = {"alert": False, "alert_type": None,
                  "annotated_frame": frame.copy(), "metrics": {}}
        h, w      = frame.shape[:2]
        annotated = frame.copy()
        face_detected = False

        if self.face_landmarker is not None:
            try:
                rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                mp_image  = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
                det       = self.face_landmarker.detect(mp_image)

                if det.face_landmarks:
                    face_detected       = True
                    self.absent_counter = 0
                    lms = det.face_landmarks[0]

                    left_ear  = compute_ear(lms, LEFT_EYE,  w, h)
                    right_ear = compute_ear(lms, RIGHT_EYE, w, h)
                    avg_ear   = (left_ear + right_ear) / 2.0
                    result["metrics"]["ear"] = round(avg_ear, 3)

                    if avg_ear < self.EAR_THRESHOLD:
                        self.ear_counter += 1
                    else:
                        self.ear_counter = 0

                    if self.ear_counter >= self.EAR_CONSEC_FRAMES and self._cooldown_ok("drowsiness"):
                        result["alert"]      = True
                        result["alert_type"] = "Drowsiness Detected"

                    nose     = lms[NOSE_TIP]
                    l_ear_lm = lms[LEFT_EAR_IDX]
                    r_ear_lm = lms[RIGHT_EAR_IDX]
                    chin_lm  = lms[CHIN]
                    fore_lm  = lms[FOREHEAD]

                    ear_mid_x  = (l_ear_lm.x + r_ear_lm.x) / 2.0
                    yaw_offset = abs(nose.x - ear_mid_x) * 100
                    result["metrics"]["yaw"] = round(yaw_offset, 1)

                    face_height  = abs(chin_lm.y - fore_lm.y)
                    nose_to_chin = abs(nose.y - chin_lm.y)
                    pitch_ratio  = nose_to_chin / face_height if face_height > 0 else 0
                    result["metrics"]["pitch_ratio"] = round(pitch_ratio, 3)

                    if (not result["alert"] and yaw_offset > self.HEAD_YAW_THRESHOLD
                            and self._cooldown_ok("distraction")):
                        result["alert"]      = True
                        result["alert_type"] = "Driver Distracted"

                    if (not result["alert"] and pitch_ratio < 0.3
                            and self._cooldown_ok("head_drop")):
                        result["alert"]      = True
                        result["alert_type"] = "Head Drop Detected"

                    cv2.putText(annotated, f"EAR: {avg_ear:.2f}", (10, 30),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
                    cv2.putText(annotated, f"Yaw: {yaw_offset:.1f}", (10, 55),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
            except Exception as e:
                print(f"[Detection] Face landmark error: {e}")

        if not face_detected and self.face_landmarker is not None:
            self.absent_counter += 1
            if self.absent_counter >= self.ABSENT_FACE_FRAMES and self._cooldown_ok("no_face"):
                result["alert"]      = True
                result["alert_type"] = "No Driver Detected"

        if self.yolo and not result["alert"]:
            try:
                yolo_results = self.yolo(frame, verbose=False, conf=0.4)
                for r in yolo_results:
                    for box in r.boxes:
                        if int(box.cls[0]) == 67 and self._cooldown_ok("phone"):
                            result["alert"]      = True
                            result["alert_type"] = "Phone Usage While Driving"
                            x1, y1, x2, y2 = [int(v) for v in box.xyxy[0]]
                            cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 0, 255), 3)
                            cv2.putText(annotated, "PHONE", (x1, y1 - 10),
                                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2)
                            break
            except Exception as e:
                print(f"[Detection] YOLO error: {e}")

        if result["alert"]:
            overlay = annotated.copy()
            cv2.rectangle(overlay, (0, 0), (w, 60), (0, 0, 200), -1)
            cv2.addWeighted(overlay, 0.6, annotated, 0.4, 0, annotated)
            cv2.putText(annotated, f"ALERT: {result['alert_type']}", (10, 40),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 2)

        status_color = (0, 0, 255) if result["alert"] else (0, 255, 0)
        cv2.circle(annotated, (w - 20, 20), 10, status_color, -1)
        result["annotated_frame"] = annotated
        return result

    def frame_to_jpeg(self, frame: np.ndarray) -> bytes:
        _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
        return buf.tobytes()

    def frame_to_b64(self, frame: np.ndarray) -> str:
        return base64.b64encode(self.frame_to_jpeg(frame)).decode()

    def run_webcam(self, camera_index: int = 0):
        cap = cv2.VideoCapture(camera_index)
        print("[Detection] Press 'q' to quit")
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break
            res = self.analyze_frame(frame)
            if res["alert"]:
                print(f"[ALERT] {res['alert_type']}")
            cv2.imshow("Driver Monitor", res["annotated_frame"])
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
        cap.release()
        cv2.destroyAllWindows()
