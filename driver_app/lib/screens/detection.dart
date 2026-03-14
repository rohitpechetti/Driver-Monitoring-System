// lib/screens/detection.dart
// Real-time driver monitoring screen with camera, alerts, sound & vibration.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
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

// ── Screen ─────────────────────────────────────────────────────────────────────

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _user;
  CameraController? _camera;
  List<CameraDescription>? _cameras;
  bool _cameraReady = false;
  bool _detecting = false;
  String? _currentAlert;
  DateTime? _lastAlertTime;
  Timer? _detectionTimer;
  Timer? _alertClearTimer;
  final AudioPlayer _audio = AudioPlayer();
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _alertCtrl;
  late Animation<double> _alertAnim;
  int _frameCount = 0;
  int _totalAlerts = 0;

  // Simulated detection state (replace with real ML inference on device
  // or send frames to backend for analysis)
  final List<String> _simulatedAlerts = [
    'Drowsiness Detected',
    'Driver Distracted',
    'Phone Usage While Driving',
    'Head Drop Detected',
    'No Driver Detected',
  ];
  int _simIndex = 0;
  int _framesSinceAlert = 0;
  static const int _alertIntervalFrames = 60; // ~every 6 seconds at 10fps

  @override
  void initState() {
    super.initState();

    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _alertCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _alertAnim = CurvedAnimation(parent: _alertCtrl, curve: Curves.elasticOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        setState(() => _user = args);
      }
      _initCamera();
    });
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _alertClearTimer?.cancel();
    _camera?.dispose();
    _audio.dispose();
    _pulseCtrl.dispose();
    _alertCtrl.dispose();
    super.dispose();
  }

  // ── Camera ─────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) return;

      // Prefer front camera for driver monitoring
      final frontCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _camera = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _camera!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  // ── Detection Loop ─────────────────────────────────────────────────────────

  void _startDetection() {
    setState(() => _detecting = true);
    // Poll every 100ms (~10 fps processing)
    _detectionTimer =
        Timer.periodic(const Duration(milliseconds: 100), _processFrame);
  }

  void _stopDetection() {
    _detectionTimer?.cancel();
    _alertClearTimer?.cancel();
    setState(() {
      _detecting = false;
      _currentAlert = null;
    });
  }

  Future<void> _processFrame(Timer _) async {
    if (!_cameraReady || _camera == null || !_detecting) return;
    _frameCount++;
    _framesSinceAlert++;

    // ── Simulated detection logic ──────────────────────────────────────────
    // In production: capture frame and either run on-device model
    // or send to /api/analyze endpoint on the backend.
    // The backend returns alert_type which is then processed here.
    // ────────────────────────────────────────────────────────────────────────

    if (_framesSinceAlert >= _alertIntervalFrames && _currentAlert == null) {
      // Simulate a random alert for demonstration
      // Replace this block with actual backend call or on-device inference
      _framesSinceAlert = 0;
      // Only trigger alert ~30% of the time for demo realism
      if (_frameCount % 3 == 0) {
        final alertType = _simulatedAlerts[_simIndex % _simulatedAlerts.length];
        _simIndex++;
        await _triggerAlert(alertType);
      }
    }
  }

  Future<void> _triggerAlert(String alertType) async {
    if (_currentAlert != null) return; // debounce
    if (!mounted) return;

    setState(() {
      _currentAlert = alertType;
      _totalAlerts++;
    });
    _alertCtrl.forward(from: 0);

    // Sound + vibration
    await _playAlarm();
    await _vibrate();

    // Log to backend
    final username = _user?['username'] ?? 'unknown';
    final timestamp = DateTime.now().toIso8601String();

    // Capture screenshot if camera available
    String? screenshot;
    try {
      final xFile = await _camera?.takePicture();
      if (xFile != null) {
        final bytes = await xFile.readAsBytes();
        screenshot = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }
    } catch (_) {}

    ApiService.logAlert(
      username: username,
      alertType: alertType,
      timestamp: timestamp,
      screenshotBase64: screenshot,
    );

    // Auto-clear alert after 4 seconds
    _alertClearTimer?.cancel();
    _alertClearTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _currentAlert = null);
    });
  }

  Future<void> _playAlarm() async {
    try {
      await _audio.stop();
      // Uses a built-in beep; replace with asset path for custom sound
      await _audio.play(AssetSource('alarm.mp3'));
    } catch (_) {}
  }

  Future<void> _vibrate() async {
    final hasVibrator = await Vibration.hasVibrator() ?? false;
    if (hasVibrator) {
      Vibration.vibrate(pattern: [0, 300, 100, 300, 100, 500]);
    }
  }

  Future<void> _logout() async {
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
            Positioned.fill(
              child: CameraPreview(_camera!),
            )
          else
            const Positioned.fill(
              child: _CameraPlaceholder(),
            ),

          // Dark overlay when alert
          if (_currentAlert != null)
            Positioned.fill(
              child: FadeTransition(
                opacity: _alertAnim,
                child: Container(
                  color: (alertInfo?.color ?? Colors.red).withOpacity(0.25),
                ),
              ),
            ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(),
          ),

          // Status & stats band
          Positioned(
            bottom: 140,
            left: 0,
            right: 0,
            child: _buildStatusBand(),
          ),

          // Alert banner
          if (_currentAlert != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 16,
              right: 16,
              child: ScaleTransition(
                scale: _alertAnim,
                child: _buildAlertBanner(alertInfo),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomControls(),
          ),
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
      child: Row(
        children: [
          const Icon(Icons.remove_red_eye, color: Color(0xFF00D4FF), size: 22),
          const SizedBox(width: 8),
          const Text(
            'DRIVER MONITOR',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            _user?['username'] ?? '',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _logout,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.withOpacity(0.5)),
              ),
              child: const Text('LOGOUT',
                  style: TextStyle(
                      color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
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
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(info?.icon ?? Icons.warning, color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠ ALERT DETECTED',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentAlert ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBand() {
    final isActive = _detecting;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? const Color(0xFF00D4FF).withOpacity(0.4)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('STATUS',
              isActive ? 'ACTIVE' : 'IDLE',
              isActive ? const Color(0xFF00D4FF) : Colors.white54),
          _divider(),
          _statItem('FRAMES', '$_frameCount', Colors.white70),
          _divider(),
          _statItem('ALERTS', '$_totalAlerts', Colors.orange),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white38, fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: valueColor, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _divider() => Container(width: 1, height: 30, color: Colors.white12);

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
      child: Row(
        children: [
          // Test alert button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _detecting
                  ? () => _triggerAlert('Drowsiness Detected')
                  : null,
              icon: const Icon(Icons.bug_report, size: 18),
              label: const Text('TEST ALERT'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Start / Stop button
          Expanded(
            flex: 2,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) => Transform.scale(
                scale: _detecting ? _pulseAnim.value : 1.0,
                child: child,
              ),
              child: ElevatedButton.icon(
                onPressed: _cameraReady
                    ? (_detecting ? _stopDetection : _startDetection)
                    : null,
                icon: Icon(_detecting ? Icons.stop : Icons.play_arrow),
                label: Text(_detecting ? 'STOP' : 'START DETECTION'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _detecting ? Colors.red.shade700 : const Color(0xFF00D4FF),
                  foregroundColor: _detecting ? Colors.white : Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: _detecting ? 8 : 2,
                  shadowColor:
                      (_detecting ? Colors.red : const Color(0xFF00D4FF))
                          .withOpacity(0.4),
                ),
              ),
            ),
          ),
        ],
      ),
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
          Text(
            'Camera initializing...',
            style: TextStyle(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
