// lib/screens/detection.dart
// Real-time driver monitoring using Google ML Kit Face Detection

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/api_service.dart';

// ── Alert data ─────────────────────────────────────────────────────────────────

class AlertInfo {
  final String type;
  final Color color;
  final IconData icon;
  AlertInfo(this.type, this.color, this.icon);
}

final Map<String, AlertInfo> alertMap = {
  'Drowsiness Detected': AlertInfo(
      'Drowsiness Detected', const Color(0xFFFF9500), Icons.bedtime),
  'Phone Usage While Driving': AlertInfo(
      'Phone Usage While Driving', const Color(0xFFFF3B30), Icons.smartphone),
  'Driver Distracted': AlertInfo(
      'Driver Distracted', const Color(0xFFFF6B35), Icons.visibility_off),
  'Head Drop Detected': AlertInfo(
      'Head Drop Detected', const Color(0xFFFF2D55), Icons.arrow_downward),
  'No Driver Detected': AlertInfo(
      'No Driver Detected', const Color(0xFFAF52DE), Icons.no_accounts),
};

// ── Detection thresholds ───────────────────────────────────────────────────────

const double _earThreshold       = 0.22; // below = eyes closed
const int    _earConsecFrames    = 15;   // frames before drowsiness alert
const double _yawThreshold       = 25.0; // degrees head turn = distracted
const double _pitchDownThreshold = -20.0;// degrees chin down = head drop
const int    _noFaceFrames       = 20;   // frames without face = no driver
const int    _cooldownSeconds    = 5;    // seconds between same alert type

// ── Screen ─────────────────────────────────────────────────────────────────────

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _user;
  CameraController?     _camera;
  bool _cameraReady = false;
  bool _detecting   = false;
  bool _processing  = false;
  String? _currentAlert;
  Timer?  _alertClearTimer;
  int _frameCount   = 0;
  int _totalAlerts  = 0;

  // ── ML Kit ─────────────────────────────────────────────────────────────────
  late final FaceDetector _faceDetector;

  // ── Detection counters ─────────────────────────────────────────────────────
  int _earCounter    = 0;
  int _noFaceCounter = 0;
  final Map<String, DateTime> _alertCooldown = {};

  // ── Metrics display ────────────────────────────────────────────────────────
  double? _lastEar;
  double? _lastYaw;
  double? _lastPitch;
  int     _facesDetected = 0;

  // ── Audio ──────────────────────────────────────────────────────────────────
  final AudioPlayer _audio = AudioPlayer();

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;
  late AnimationController _alertCtrl;
  late Animation<double>   _alertAnim;

  @override
  void initState() {
    super.initState();

    // ML Kit face detector — request landmarks + classifications
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks:       true,
        enableClassification:  true, // gives eye open probability
        enableTracking:        true,
        enableContours:        false,
        performanceMode:       FaceDetectorMode.fast,
        minFaceSize:           0.15,
      ),
    );

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _alertCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _alertAnim =
        CurvedAnimation(parent: _alertCtrl, curve: Curves.elasticOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) setState(() => _user = args);
      _initCamera();
    });
  }

  @override
  void dispose() {
    _alertClearTimer?.cancel();
    _camera?.dispose();
    _faceDetector.close();
    _audio.dispose();
    _pulseCtrl.dispose();
    _alertCtrl.dispose();
    super.dispose();
  }

  // ── Camera init ────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _camera = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21, // required for ML Kit on Android
      );

      await _camera!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  // ── Detection loop ─────────────────────────────────────────────────────────

  void _startDetection() {
    setState(() => _detecting = true);
    _camera?.startImageStream(_onCameraImage);
  }

  void _stopDetection() {
    _camera?.stopImageStream();
    _alertClearTimer?.cancel();
    setState(() {
      _detecting      = false;
      _currentAlert   = null;
      _earCounter     = 0;
      _noFaceCounter  = 0;
      _lastEar        = null;
      _lastYaw        = null;
      _lastPitch      = null;
      _facesDetected  = 0;
    });
  }

  // Called for every camera frame
  Future<void> _onCameraImage(CameraImage image) async {
    if (_processing) return; // skip frame if still processing previous
    _processing = true;
    _frameCount++;

    try {
      // Convert CameraImage to ML Kit InputImage
      final inputImage = _buildInputImage(image);
      if (inputImage == null) { _processing = false; return; }

      // Run face detection
      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) { _processing = false; return; }

      setState(() => _facesDetected = faces.length);

      if (faces.isEmpty) {
        // No face in frame
        _earCounter = 0;
        _noFaceCounter++;
        if (_noFaceCounter >= _noFaceFrames) {
          await _triggerAlert('No Driver Detected');
        }
      } else {
        _noFaceCounter = 0;
        final face = faces.first;
        await _analyzeFace(face);
      }
    } catch (e) {
      debugPrint('Detection error: $e');
    }

    _processing = false;
  }

  // Convert CameraImage (YUV/NV21) → InputImage for ML Kit
  InputImage? _buildInputImage(CameraImage image) {
    try {
      final camera = _camera!.description;
      final rotation = InputImageRotationValue.fromRawValue(
          camera.sensorOrientation) ?? InputImageRotation.rotation0deg;

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      // For NV21 (Android) — single plane
      if (image.planes.length == 1) {
        return InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: format,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
      }

      // For multi-plane (YUV420) — concatenate planes
      final List<int> combined = [];
      for (final plane in image.planes) {
        combined.addAll(plane.bytes);
      }
      final allBytes = Uint8List.fromList(combined);
      return InputImage.fromBytes(
        bytes: allBytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  // Analyze detected face for drowsiness, distraction, head drop
  Future<void> _analyzeFace(Face face) async {
    // ── Eye openness (ML Kit gives probability 0.0–1.0) ───────────────────
    final leftEyeOpen  = face.leftEyeOpenProbability  ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;
    final avgEyeOpen   = (leftEyeOpen + rightEyeOpen) / 2.0;

    // Convert to EAR-like value (invert: 0=closed, 1=open)
    // EAR threshold 0.22 mapped: eye open prob < 0.35 ≈ closed
    final eyeClosed = avgEyeOpen < 0.35;

    setState(() => _lastEar = avgEyeOpen);

    if (eyeClosed) {
      _earCounter++;
      if (_earCounter >= _earConsecFrames) {
        await _triggerAlert('Drowsiness Detected');
        return;
      }
    } else {
      _earCounter = 0;
    }

    // ── Head pose (Euler angles in degrees) ───────────────────────────────
    final yaw   = face.headEulerAngleY ?? 0.0; // left/right
    final pitch = face.headEulerAngleX ?? 0.0; // up/down
    // final roll = face.headEulerAngleZ ?? 0.0; // tilt

    setState(() {
      _lastYaw   = yaw;
      _lastPitch = pitch;
    });

    // Distraction: head turned sideways
    if (yaw.abs() > _yawThreshold) {
      await _triggerAlert('Driver Distracted');
      return;
    }

    // Head drop: chin toward chest
    if (pitch < _pitchDownThreshold) {
      await _triggerAlert('Head Drop Detected');
      return;
    }
  }

  // ── Alert handling ─────────────────────────────────────────────────────────

  bool _cooldownOk(String alertType) {
    final last = _alertCooldown[alertType];
    if (last == null) return true;
    return DateTime.now().difference(last).inSeconds >= _cooldownSeconds;
  }

  Future<void> _triggerAlert(String alertType) async {
    if (_currentAlert != null) return;
    if (!_cooldownOk(alertType)) return;
    if (!mounted) return;

    _alertCooldown[alertType] = DateTime.now();

    setState(() {
      _currentAlert = alertType;
      _totalAlerts++;
    });

    _alertCtrl.forward(from: 0);

    // Sound + vibration simultaneously
    _playAlarm();
    _vibrate();

    // Log to backend (fire and forget — don't await to avoid blocking UI)
    final username  = _user?['username'] ?? 'unknown';
    final timestamp = DateTime.now().toIso8601String();

    // Capture screenshot safely without stopping detection stream
    _captureAndLog(username, alertType, timestamp);

    // Auto-clear after 4 seconds
    _alertClearTimer?.cancel();
    _alertClearTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _currentAlert = null);
    });
  }

  // Separate method to safely capture screenshot without crashing
  Future<void> _captureAndLog(
      String username, String alertType, String timestamp) async {
    String? screenshot;
    try {
      if (_camera != null && _camera!.value.isInitialized) {
        // Stop stream safely
        try { await _camera!.stopImageStream(); } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 200));

        // Take picture
        try {
          final xFile = await _camera!.takePicture();
          final bytes = await xFile.readAsBytes();
          screenshot = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        } catch (e) {
          debugPrint('Screenshot error: $e');
        }

        // Restart stream if still detecting
        await Future.delayed(const Duration(milliseconds: 200));
        if (_detecting && mounted) {
          try { await _camera!.startImageStream(_onCameraImage); } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      // Always try to restart stream
      if (_detecting && mounted) {
        try { await _camera?.startImageStream(_onCameraImage); } catch (_) {}
      }
    }

    // Log to backend regardless of screenshot success
    ApiService.logAlert(
      username:         username,
      alertType:        alertType,
      timestamp:        timestamp,
      screenshotBase64: screenshot,
    );
  }

  Future<void> _playAlarm() async {
    bool played = false;
    // Try asset sound first
    try {
      await _audio.stop();
      await _audio.setVolume(1.0);
      await _audio.setReleaseMode(ReleaseMode.stop);
      await _audio.play(AssetSource('alarm.mp3'));
      played = true;
      debugPrint('Audio: playing from asset');
    } catch (e) {
      debugPrint('Audio asset failed: $e');
    }
    // Fallback: stronger vibration if sound fails
    if (!played) {
      try {
        final has = await Vibration.hasVibrator() ?? false;
        if (has) {
          Vibration.vibrate(
            pattern: [0, 800, 200, 800, 200, 1000],
            intensities: [0, 255, 0, 255, 0, 255],
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _vibrate() async {
    try {
      final has = await Vibration.hasVibrator() ?? false;
      if (has) {
        Vibration.vibrate(
          pattern: [0, 300, 100, 300, 100, 500],
          intensities: [0, 128, 0, 200, 0, 255],
        );
      }
    } catch (_) {}
  }

  Future<void> _logout() async {
    if (_detecting) _stopDetection();
    await ApiService.clearSession();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final alertInfo = _currentAlert != null ? alertMap[_currentAlert!] : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          if (_cameraReady && _camera != null)
            Positioned.fill(child: CameraPreview(_camera!))
          else
            const Positioned.fill(child: _CameraPlaceholder()),

          // Alert colour wash
          if (_currentAlert != null)
            Positioned.fill(
              child: FadeTransition(
                opacity: _alertAnim,
                child: Container(
                    color: (alertInfo?.color ?? Colors.red).withOpacity(0.25)),
              ),
            ),

          // Top bar
          Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

          // Metrics band
          Positioned(
              bottom: 140, left: 0, right: 0, child: _buildMetricsBand()),

          // Alert banner
          if (_currentAlert != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 16,
              right: 16,
              child: ScaleTransition(
                  scale: _alertAnim,
                  child: _buildAlertBanner(alertInfo)),
            ),

          // Bottom controls
          Positioned(
              bottom: 0, left: 0, right: 0, child: _buildBottomControls()),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 8, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.85), Colors.transparent],
        ),
      ),
      child: Row(children: [
        const Icon(Icons.remove_red_eye, color: Color(0xFF00D4FF), size: 20),
        const SizedBox(width: 8),
        const Text('DRIVER MONITOR',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontSize: 13)),
        const Spacer(),
        // Face indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (_facesDetected > 0 ? Colors.green : Colors.red)
                .withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(
              _facesDetected > 0 ? Icons.face : Icons.no_accounts,
              color: _facesDetected > 0 ? Colors.green : Colors.red,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              _facesDetected > 0 ? 'Face detected' : 'No face',
              style: TextStyle(
                color: _facesDetected > 0 ? Colors.green : Colors.red,
                fontSize: 11,
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _logout,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.withOpacity(0.5)),
            ),
            child: const Text('LOGOUT',
                style: TextStyle(
                    color: Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }

  Widget _buildAlertBanner(AlertInfo? info) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: (info?.color ?? Colors.red).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (info?.color ?? Colors.red).withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 4,
          )
        ],
      ),
      child: Row(children: [
        Icon(info?.icon ?? Icons.warning, color: Colors.white, size: 32),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⚠ ALERT',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5)),
              const SizedBox(height: 2),
              Text(_currentAlert ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildMetricsBand() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _detecting
              ? const Color(0xFF00D4FF).withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _metricItem('EYE OPEN',
              _lastEar != null ? '${(_lastEar! * 100).toInt()}%' : '--',
              _lastEar != null && _lastEar! < 0.35
                  ? Colors.red
                  : Colors.green),
          _divider(),
          _metricItem('YAW',
              _lastYaw != null ? '${_lastYaw!.toInt()}°' : '--',
              _lastYaw != null && _lastYaw!.abs() > _yawThreshold
                  ? Colors.orange
                  : Colors.white70),
          _divider(),
          _metricItem('PITCH',
              _lastPitch != null ? '${_lastPitch!.toInt()}°' : '--',
              _lastPitch != null && _lastPitch! < _pitchDownThreshold
                  ? Colors.orange
                  : Colors.white70),
          _divider(),
          _metricItem('ALERTS', '$_totalAlerts', Colors.orange),
        ],
      ),
    );
  }

  Widget _metricItem(String label, String value, Color valueColor) {
    return Column(children: [
      Text(label,
          style: const TextStyle(
              color: Colors.white38, fontSize: 9, letterSpacing: 0.8)),
      const SizedBox(height: 2),
      Text(value,
          style: TextStyle(
              color: valueColor,
              fontSize: 15,
              fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _divider() =>
      Container(width: 1, height: 28, color: Colors.white12);

  Widget _buildBottomControls() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.9), Colors.transparent],
        ),
      ),
      child: Row(children: [
        // EAR counter visual
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Eye closed: $_earCounter/$_earConsecFrames',
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _earCounter / _earConsecFrames,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _earCounter > _earConsecFrames * 0.6
                        ? Colors.red
                        : Colors.orange,
                  ),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Start/Stop button
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Transform.scale(
              scale: _detecting ? _pulseAnim.value : 1.0, child: child),
          child: ElevatedButton.icon(
            onPressed: _cameraReady
                ? (_detecting ? _stopDetection : _startDetection)
                : null,
            icon: Icon(_detecting ? Icons.stop : Icons.play_arrow),
            label: Text(_detecting ? 'STOP' : 'START'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _detecting
                  ? Colors.red.shade700
                  : const Color(0xFF00D4FF),
              foregroundColor:
                  _detecting ? Colors.white : Colors.black,
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: _detecting ? 8 : 2,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Camera placeholder ─────────────────────────────────────────────────────────

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A1628),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off, size: 60, color: Colors.white24),
          SizedBox(height: 12),
          Text('Camera initializing...',
              style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}
