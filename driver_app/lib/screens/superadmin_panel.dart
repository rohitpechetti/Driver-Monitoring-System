// lib/screens/superadmin_panel.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SuperAdminPanel extends StatefulWidget {
  const SuperAdminPanel({super.key});

  @override
  State<SuperAdminPanel> createState() => _SuperAdminPanelState();
}

class _SuperAdminPanelState extends State<SuperAdminPanel>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _user;
  List<dynamic> _allUsers = [];
  List<dynamic> _pendingAdmins = [];
  bool _loadingUsers = true;
  bool _loadingPending = true;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) setState(() => _user = args);
      _fetchAll();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    _fetchUsers();
    _fetchPending();
  }

  Future<void> _fetchUsers() async {
    setState(() => _loadingUsers = true);
    final result = await ApiService.getAllUsers();
    if (mounted) {
      setState(() {
        _allUsers = result['users'] ?? [];
        _loadingUsers = false;
      });
    }
  }

  Future<void> _fetchPending() async {
    setState(() => _loadingPending = true);
    final result = await ApiService.getPendingAdmins();
    if (mounted) {
      setState(() {
        _pendingAdmins = result['pending'] ?? [];
        _loadingPending = false;
      });
    }
  }

  Future<void> _approveAdmin(int userId, String username, String role) async {
    final confirmed = await _confirm(
        'Approve ${role == 'superadmin' ? 'Super Admin' : 'Admin'}',
        'Approve $username as ${role == 'superadmin' ? 'Super Admin' : 'Admin'}?',
        Colors.green);
    if (!confirmed) return;

    final result = await ApiService.approveAdmin(userId);
    _showSnack(result['message'] ?? '', result['success'] == true);
    if (result['success'] == true) _fetchAll();
  }

  Future<void> _rejectAdmin(int userId, String username) async {
    final confirmed = await _confirm(
        'Reject Admin', 'Reject and delete $username\'s registration?', Colors.red);
    if (!confirmed) return;

    final result = await ApiService.rejectAdmin(userId);
    _showSnack(result['message'] ?? '', result['success'] == true);
    if (result['success'] == true) _fetchAll();
  }

  Future<void> _deleteUser(int userId, String username) async {
    final confirmed = await _confirm(
        'Delete User', 'Permanently delete $username?', Colors.red);
    if (!confirmed) return;

    final result = await ApiService.deleteUser(userId);
    _showSnack(result['message'] ?? '', result['success'] == true);
    if (result['success'] == true) _fetchAll();
  }

  Future<bool> _confirm(String title, String message, Color color) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F1E35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: color, foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String msg, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _logout() async {
    await ApiService.clearSession();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'superadmin':
        return const Color(0xFFAF52DE);
      case 'admin':
        return const Color(0xFF00D4FF);
      default:
        return const Color(0xFF34C759);
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'superadmin':
        return Icons.security;
      case 'admin':
        return Icons.admin_panel_settings;
      default:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.security, color: Color(0xFFAF52DE), size: 22),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Super Admin',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (_user != null)
                  Text(_user!['username'] ?? '',
                      style: const TextStyle(fontSize: 11, color: Colors.white54)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _fetchAll),
          IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              onPressed: _logout),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFFAF52DE),
          labelColor: const Color(0xFFAF52DE),
          unselectedLabelColor: Colors.white38,
          tabs: [
            Tab(
              icon: badges(Icons.pending_actions, _pendingAdmins.length),
              text: 'Pending Approvals',
            ),
            const Tab(icon: Icon(Icons.group), text: 'All Users'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildPendingTab(),
          _buildUsersTab(),
        ],
      ),
    );
  }

  Widget badges(IconData icon, int count) {
    if (count == 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -6,
          top: -6,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
                color: Colors.red, shape: BoxShape.circle),
            child: Text('$count',
                style:
                    const TextStyle(color: Colors.white, fontSize: 9)),
          ),
        ),
      ],
    );
  }

  // ── Pending Admins Tab ─────────────────────────────────────────────────────

  Widget _buildPendingTab() {
    if (_loadingPending) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFAF52DE)));
    }
    if (_pendingAdmins.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 64, color: Colors.green),
            const SizedBox(height: 12),
            const Text('No pending approvals',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchPending,
      color: const Color(0xFFAF52DE),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingAdmins.length,
        itemBuilder: (_, i) => _buildPendingCard(_pendingAdmins[i]),
      ),
    );
  }

  Widget _buildPendingCard(Map<String, dynamic> admin) {
    final role = admin['role'] as String? ?? 'admin';
    final isSuperAdmin = role == 'superadmin';
    final roleColor = isSuperAdmin ? const Color(0xFFAF52DE) : Colors.amber;
    final roleLabel = isSuperAdmin ? 'SUPER ADMIN' : 'ADMIN';
    final roleIcon = isSuperAdmin ? Icons.security : Icons.admin_panel_settings;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: roleColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(roleIcon, color: roleColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(admin['username'] ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    Text(admin['email'] ?? '',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: roleColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(roleLabel,
                          style: TextStyle(
                              color: roleColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: const Text('PENDING',
                    style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _rejectAdmin(admin['id'], admin['username'] ?? ''),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('REJECT'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _approveAdmin(
                      admin['id'], admin['username'] ?? '', role),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('APPROVE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── All Users Tab ──────────────────────────────────────────────────────────

  Widget _buildUsersTab() {
    if (_loadingUsers) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFAF52DE)));
    }
    final nonSuper =
        _allUsers.where((u) => u['role'] != 'superadmin').toList();
    if (nonSuper.isEmpty) {
      return const Center(
          child: Text('No users found',
              style: TextStyle(color: Colors.white54)));
    }
    return RefreshIndicator(
      onRefresh: _fetchUsers,
      color: const Color(0xFFAF52DE),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: nonSuper.length,
        itemBuilder: (_, i) => _buildUserCard(nonSuper[i]),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> u) {
    final role = u['role'] as String? ?? 'user';
    final isApproved = (u['is_approved'] as int? ?? 0) == 1;
    final roleColor = _roleColor(role);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: roleColor.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: roleColor.withOpacity(0.15),
            child: Icon(_roleIcon(role), color: roleColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(u['username'] ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: roleColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(role.toUpperCase(),
                          style: TextStyle(
                              color: roleColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                Text(u['email'] ?? '',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          // Approval status
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color:
                  (isApproved ? Colors.green : Colors.orange).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isApproved ? Icons.check_circle : Icons.schedule,
              color: isApproved ? Colors.green : Colors.orange,
              size: 16,
            ),
          ),
          // Delete button
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            tooltip: 'Delete user',
            onPressed: () => _deleteUser(u['id'], u['username'] ?? ''),
          ),
        ],
      ),
    );
  }
}
