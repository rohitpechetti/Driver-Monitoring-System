// lib/screens/login.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey      = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool   _loading  = false;
  bool   _obscure  = true;
  String _loadingMsg = 'Connecting to server...';
  late AnimationController _animCtrl;
  late Animation<Offset>   _slideAnim;
  Timer? _msgTimer;

  final List<String> _loadingMessages = [
    'Connecting to server...',
    'Server is waking up...',
    'This may take up to 60 seconds on first login...',
    'Almost there...',
    'Still connecting, please wait...',
  ];
  int _msgIndex = 0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _msgTimer?.cancel();
    super.dispose();
  }

  void _startLoadingMessages() {
    _msgIndex   = 0;
    _loadingMsg = _loadingMessages[0];
    _msgTimer = Timer.periodic(const Duration(seconds: 8), (t) {
      if (!mounted) { t.cancel(); return; }
      _msgIndex = (_msgIndex + 1) % _loadingMessages.length;
      setState(() => _loadingMsg = _loadingMessages[_msgIndex]);
    });
  }

  void _stopLoadingMessages() {
    _msgTimer?.cancel();
    _msgTimer = null;
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading    = true;
      _loadingMsg = _loadingMessages[0];
    });
    _startLoadingMessages();

    final result = await ApiService.login(
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    _stopLoadingMessages();
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      final user = result['user'] as Map<String, dynamic>;
      await ApiService.saveSession(user);
      final role = user['role'] as String;
      switch (role) {
        case 'superadmin':
          Navigator.pushReplacementNamed(context, '/superadmin', arguments: user);
          break;
        case 'admin':
          Navigator.pushReplacementNamed(context, '/admin', arguments: user);
          break;
        default:
          Navigator.pushReplacementNamed(context, '/detection', arguments: user);
      }
    } else {
      _showError(result['message'] ?? 'Login failed');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Theme.of(context).colorScheme.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Forgot Password Flow ───────────────────────────────────────────────────

  void _openForgotPassword() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ForgotPasswordSheet(),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A1628),
                  Color(0xFF0F2040),
                  Color(0xFF0A1628),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    children: [
                      // ── Logo ─────────────────────────────────────────────
                      Container(
                        width: 90, height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00D4FF), Color(0xFF0066CC)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00D4FF).withOpacity(0.3),
                              blurRadius: 25, spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.shield_outlined,
                            size: 44, color: Colors.white),
                      ),
                      const SizedBox(height: 20),
                      const Text('DRIVER MONITOR',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 3)),
                      const Text('Sign in to continue',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 14)),
                      const SizedBox(height: 40),

                      // ── Form card ─────────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1E35),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF00D4FF).withOpacity(0.15),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _usernameCtrl,
                                enabled: !_loading,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                textInputAction: TextInputAction.next,
                                validator: (v) => v == null || v.isEmpty
                                    ? 'Enter username'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordCtrl,
                                obscureText: _obscure,
                                enabled: !_loading,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon:
                                      const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure
                                        ? Icons.visibility_off
                                        : Icons.visibility),
                                    color: Colors.white54,
                                    onPressed: () => setState(
                                        () => _obscure = !_obscure),
                                  ),
                                ),
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) =>
                                    _loading ? null : _login(),
                                validator: (v) => v == null || v.isEmpty
                                    ? 'Enter password'
                                    : null,
                              ),

                              // ── Forgot password link ─────────────────────
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed:
                                      _loading ? null : _openForgotPassword,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4, horizontal: 0),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(
                                      color: Color(0xFF00D4FF),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _login,
                                  child: _loading
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.black))
                                      : const Text('LOGIN'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Loading status message ────────────────────────────
                      if (_loading) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1E35),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  const Color(0xFF00D4FF).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF00D4FF),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  _loadingMsg,
                                  style: const TextStyle(
                                    color: Color(0xFF00D4FF),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () =>
                                Navigator.pushNamed(context, '/register'),
                        child: const Text(
                          "Don't have an account? Register",
                          style: TextStyle(color: Color(0xFF00D4FF)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Forgot Password — 3-step bottom sheet
//  Step 1: Enter email → request OTP
//  Step 2: Enter OTP
//  Step 3: Enter new password → reset
// ══════════════════════════════════════════════════════════════════════════════

class _ForgotPasswordSheet extends StatefulWidget {
  const _ForgotPasswordSheet();

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  // 1 = email entry, 2 = otp entry, 3 = new password
  int _step = 1;

  final _emailCtrl    = TextEditingController();
  final _otpCtrl      = TextEditingController();
  final _newPassCtrl  = TextEditingController();
  final _confPassCtrl = TextEditingController();

  bool   _loading    = false;
  bool   _obscureNew = true;
  String _userEmail  = '';   // saved after step 1 for later steps

  // OTP resend cooldown
  int    _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    _confPassCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendCooldown = 60;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Step 1: Request OTP ──────────────────────────────────────────────────

  Future<void> _requestOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showSnack('Enter a valid email address', error: true);
      return;
    }
    setState(() => _loading = true);
    final result = await ApiService.forgotPassword(email: email);
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      _userEmail = email;
      _startCooldown();
      setState(() => _step = 2);
      _showSnack('OTP sent to $email');
    } else {
      _showSnack(result['message'] ?? 'Failed to send OTP', error: true);
    }
  }

  // ── Step 2: Verify OTP ───────────────────────────────────────────────────

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      _showSnack('Enter the 6-digit OTP', error: true);
      return;
    }
    setState(() => _loading = true);
    final result =
        await ApiService.verifyOtp(email: _userEmail, otp: otp);
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      setState(() => _step = 3);
    } else {
      _showSnack(result['message'] ?? 'Invalid OTP', error: true);
    }
  }

  // ── Step 3: Reset Password ───────────────────────────────────────────────

  Future<void> _resetPassword() async {
    final newPass  = _newPassCtrl.text;
    final confPass = _confPassCtrl.text;
    if (newPass.length < 6) {
      _showSnack('Password must be at least 6 characters', error: true);
      return;
    }
    if (newPass != confPass) {
      _showSnack('Passwords do not match', error: true);
      return;
    }
    setState(() => _loading = true);
    final result = await ApiService.resetPassword(
      email:       _userEmail,
      otp:         _otpCtrl.text.trim(),
      newPassword: newPass,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      _showSnack('Password reset successfully!');
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);
    } else {
      _showSnack(result['message'] ?? 'Reset failed', error: true);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1E35),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Step indicator
            _StepIndicator(currentStep: _step),
            const SizedBox(height: 24),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _step == 1
                  ? _buildStep1()
                  : _step == 2
                      ? _buildStep2()
                      : _buildStep3(),
            ),
          ],
        ),
      ),
    );
  }

  // Step 1 — email entry
  Widget _buildStep1() {
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Forgot Password',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
            'Enter the email linked to your account.\nWe will send a 6-digit OTP.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 20),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Email Address',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _requestOtp,
            child: _loading
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Text('SEND OTP'),
          ),
        ),
      ],
    );
  }

  // Step 2 — OTP entry
  Widget _buildStep2() {
    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Enter OTP',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('A 6-digit code was sent to $_userEmail',
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 20),
        TextField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              letterSpacing: 8,
              fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: '------',
            hintStyle: TextStyle(color: Colors.white24, letterSpacing: 8),
            counterText: '',
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _verifyOtp,
            child: _loading
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Text('VERIFY OTP'),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: _resendCooldown > 0
              ? Text(
                  'Resend OTP in $_resendCooldown s',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                )
              : TextButton(
                  onPressed: _loading ? null : _requestOtp,
                  child: const Text('Resend OTP',
                      style: TextStyle(color: Color(0xFF00D4FF))),
                ),
        ),
        TextButton(
          onPressed: () => setState(() { _step = 1; _otpCtrl.clear(); }),
          child: const Text('← Back',
              style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }

  // Step 3 — new password
  Widget _buildStep3() {
    return Column(
      key: const ValueKey(3),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('New Password',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Choose a strong new password.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 20),
        TextField(
          controller: _newPassCtrl,
          obscureText: _obscureNew,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'New Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureNew ? Icons.visibility_off : Icons.visibility),
              color: Colors.white54,
              onPressed: () =>
                  setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confPassCtrl,
          obscureText: _obscureNew,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: Icon(Icons.lock_clock_outlined),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _resetPassword,
            child: _loading
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Text('RESET PASSWORD'),
          ),
        ),
      ],
    );
  }
}

// ── Simple 3-step progress indicator ──────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final step   = i + 1;
        final active = step == currentStep;
        final done   = step < currentStep;
        return Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width:  active ? 32 : 28,
              height: active ? 32 : 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? Colors.green
                    : active
                        ? const Color(0xFF00D4FF)
                        : const Color(0xFF1A2E48),
                border: Border.all(
                  color: active
                      ? const Color(0xFF00D4FF)
                      : done
                          ? Colors.green
                          : Colors.white24,
                  width: 2,
                ),
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check,
                        size: 14, color: Colors.white)
                    : Text(
                        '$step',
                        style: TextStyle(
                          color:
                              active ? Colors.black : Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
              ),
            ),
            if (i < 2)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 40, height: 2,
                color: done ? Colors.green : Colors.white12,
              ),
          ],
        );
      }),
    );
  }
}
