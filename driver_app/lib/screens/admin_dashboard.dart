// lib/screens/admin_dashboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _stats;
  List<dynamic> _logs = [];
  bool _loadingStats = true;
  bool _loadingLogs = true;
  String _filterUsername = '';
  late TabController _tabCtrl;
  final _filterCtrl = TextEditingController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) setState(() => _user = args);
      _fetchAll();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _fetchAll());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _filterCtrl.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    _fetchStats();
    _fetchLogs();
  }

  Future<void> _fetchStats() async {
    setState(() => _loadingStats = true);
    final result = await ApiService.getStats();
    if (mounted && result['success'] == true) {
      setState(() {
        _stats = result['stats'];
        _loadingStats = false;
      });
    } else {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _fetchLogs() async {
    setState(() => _loadingLogs = true);
    final result = await ApiService.getLogs(
        username: _filterUsername.isEmpty ? null : _filterUsername);
    if (mounted && result['success'] == true) {
      setState(() {
        _logs = result['logs'] ?? [];
        _loadingLogs = false;
      });
    } else {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _logout() async {
    await ApiService.clearSession();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  void _downloadReport(String type) {
    final url = type == 'csv'
        ? ApiService.getCsvUrl(
            username: _filterUsername.isEmpty ? null : _filterUsername)
        : ApiService.getPdfUrl(
            username: _filterUsername.isEmpty ? null : _filterUsername);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Download from: $url'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
  }

  Color _alertColor(String alertType) {
    if (alertType.contains('Drowsiness')) return const Color(0xFFFF9500);
    if (alertType.contains('Phone')) return const Color(0xFFFF3B30);
    if (alertType.contains('Distract')) return const Color(0xFFFF6B35);
    if (alertType.contains('Head')) return const Color(0xFFFF2D55);
    if (alertType.contains('No Driver')) return const Color(0xFFAF52DE);
    return Colors.blue;
  }

  IconData _alertIcon(String alertType) {
    if (alertType.contains('Drowsiness')) return Icons.bedtime;
    if (alertType.contains('Phone')) return Icons.smartphone;
    if (alertType.contains('Distract')) return Icons.visibility_off;
    if (alertType.contains('Head')) return Icons.arrow_downward;
    if (alertType.contains('No Driver')) return Icons.no_accounts;
    return Icons.warning;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.dashboard, color: Color(0xFF00D4FF), size: 22),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Admin Dashboard',
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
              icon: const Icon(Icons.refresh), onPressed: _fetchAll, tooltip: 'Refresh'),
          IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              onPressed: _logout,
              tooltip: 'Logout'),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF00D4FF),
          labelColor: const Color(0xFF00D4FF),
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart), text: 'Overview'),
            Tab(icon: Icon(Icons.list_alt), text: 'Logs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildOverview(),
          _buildLogsTab(),
        ],
      ),
    );
  }

  // ── Overview Tab ───────────────────────────────────────────────────────────

  Widget _buildOverview() {
    if (_loadingStats) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00D4FF)));
    }
    if (_stats == null) {
      return const Center(
          child: Text('Failed to load stats', style: TextStyle(color: Colors.white54)));
    }

    return RefreshIndicator(
      onRefresh: _fetchStats,
      color: const Color(0xFF00D4FF),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary cards row
          _SummaryCards(stats: _stats!),
          const SizedBox(height: 20),

          // Alert breakdown
          _buildSectionHeader('Alert Breakdown'),
          const SizedBox(height: 10),
          ..._buildAlertBreakdown(),
          const SizedBox(height: 20),

          // Top drivers
          _buildSectionHeader('Most Incidents - Drivers'),
          const SizedBox(height: 10),
          ..._buildTopDrivers(),
          const SizedBox(height: 20),

          // Recent activity
          _buildSectionHeader('Recent Activity'),
          const SizedBox(height: 10),
          ..._buildRecentActivity(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF00D4FF),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ],
    );
  }

  List<Widget> _buildAlertBreakdown() {
    final breakdown =
        (_stats!['alert_breakdown'] as List?) ?? [];
    if (breakdown.isEmpty) return [_emptyState('No alerts recorded')];
    return breakdown.map((item) {
      final type = item['status'] as String? ?? '';
      final count = item['count'] as int? ?? 0;
      final maxCount = (breakdown.first['count'] as int? ?? 1);
      final ratio = count / maxCount;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(_alertIcon(type), color: _alertColor(type), size: 18),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Text(type,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  backgroundColor: Colors.white12,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(_alertColor(type)),
                  minHeight: 8,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ],
        ),
      );
    }).toList();
  }

  List<Widget> _buildTopDrivers() {
    final drivers = (_stats!['top_drivers'] as List?) ?? [];
    if (drivers.isEmpty) return [_emptyState('No driver data')];
    return drivers.asMap().entries.map((e) {
      final idx = e.key;
      final item = e.value;
      final colors = [
        Colors.amber,
        Colors.grey.shade400,
        Colors.brown.shade400
      ];
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 0),
        leading: CircleAvatar(
          backgroundColor: (idx < 3 ? colors[idx] : Colors.white24)
              .withOpacity(0.2),
          child: Text('${idx + 1}',
              style: TextStyle(
                  color: idx < 3 ? colors[idx] : Colors.white54,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(item['username'] ?? '',
            style: const TextStyle(color: Colors.white)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('${item['incidents']} alerts',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ),
      );
    }).toList();
  }

  List<Widget> _buildRecentActivity() {
    final recent = (_stats!['recent_logs'] as List?) ?? [];
    if (recent.isEmpty) return [_emptyState('No recent activity')];
    return recent.take(5).map((log) {
      final type = log['status'] as String? ?? '';
      final ts = log['timestamp'] as String? ?? '';
      DateTime? dt;
      try {
        dt = DateTime.parse(ts);
      } catch (_) {}
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1E35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _alertColor(type).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_alertIcon(type), color: _alertColor(type), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  Text(log['username'] ?? '',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            if (dt != null)
              Text(DateFormat('HH:mm').format(dt),
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      );
    }).toList();
  }

  Widget _emptyState(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child:
              Text(msg, style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ),
      );

  // ── Logs Tab ───────────────────────────────────────────────────────────────

  Widget _buildLogsTab() {
    return Column(
      children: [
        // Filter + download row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filterCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Filter by driver...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFF1A2E48),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    _filterUsername = v.trim();
                    _fetchLogs();
                  },
                ),
              ),
              const SizedBox(width: 10),
              _DownloadBtn(
                  icon: Icons.table_chart,
                  label: 'CSV',
                  onTap: () => _downloadReport('csv')),
              const SizedBox(width: 8),
              _DownloadBtn(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF',
                  color: Colors.red,
                  onTap: () => _downloadReport('pdf')),
            ],
          ),
        ),
        // Log count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_logs.length} records',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ),
        // List
        Expanded(
          child: _loadingLogs
              ? const Center(
                  child:
                      CircularProgressIndicator(color: Color(0xFF00D4FF)))
              : _logs.isEmpty
                  ? const Center(
                      child: Text('No logs found',
                          style: TextStyle(color: Colors.white38)))
                  : RefreshIndicator(
                      onRefresh: _fetchLogs,
                      color: const Color(0xFF00D4FF),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _logs.length,
                        itemBuilder: (_, i) => _buildLogItem(_logs[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final type = log['status'] as String? ?? '';
    final ts = log['timestamp'] as String? ?? '';
    DateTime? dt;
    try {
      dt = DateTime.parse(ts);
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _alertColor(type).withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _alertColor(type).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_alertIcon(type), color: _alertColor(type), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 12, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(log['username'] ?? '',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          if (dt != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(DateFormat('dd MMM').format(dt),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11)),
                Text(DateFormat('HH:mm').format(dt),
                    style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _SummaryCards extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _SummaryCards({required this.stats});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: [
        _card('Total Alerts', '${stats['total_logs'] ?? 0}',
            Icons.notifications_active, const Color(0xFFFF3B30)),
        _card('Drivers', '${stats['total_users'] ?? 0}',
            Icons.drive_eta, const Color(0xFF00D4FF)),
        _card('Admins', '${stats['total_admins'] ?? 0}',
            Icons.admin_panel_settings, const Color(0xFF34C759)),
        _card('Pending', '${stats['pending_admins'] ?? 0}',
            Icons.pending, const Color(0xFFFF9500)),
      ],
    );
  }

  Widget _card(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11)),
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _DownloadBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF00D4FF),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
