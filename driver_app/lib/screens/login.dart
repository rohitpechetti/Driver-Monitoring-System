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
  final _formKey   = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading  = false;
  bool _obscure  = true;
  String _loadingMsg = 'Connecting to server...';
  late AnimationController _animCtrl;
  late Animation<Offset>   _slideAnim;
  Timer? _msgTimer;

  // Cycling messages shown while waiting for server to wake up
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
    _msgIndex = 0;
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
      _loading = true;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0A1628), Color(0xFF0F2040), Color(0xFF0A1628)],
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    children: [
                      // Logo
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
                            )
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
                          style: TextStyle(color: Colors.white54, fontSize: 14)),
                      const SizedBox(height: 40),

                      // Form card
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
                              blurRadius: 20, offset: const Offset(0, 8),
                            )
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
                                validator: (v) =>
                                    v == null || v.isEmpty ? 'Enter username' : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordCtrl,
                                obscureText: _obscure,
                                enabled: !_loading,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure
                                        ? Icons.visibility_off
                                        : Icons.visibility),
                                    color: Colors.white54,
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _loading ? null : _login(),
                                validator: (v) =>
                                    v == null || v.isEmpty ? 'Enter password' : null,
                              ),
                              const SizedBox(height: 28),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _login,
                                  child: _loading
                                      ? const SizedBox(
                                          height: 22, width: 22,
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

                      // Loading status message
                      if (_loading) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1E35),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF00D4FF).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16, height: 16,
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
                            : () => Navigator.pushNamed(context, '/register'),
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
