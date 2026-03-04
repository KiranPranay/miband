import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/ble_manager.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bleManager = context.watch<BLEManager>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Band'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Reconnecting banner ──────────────────────────────────────
            if (bleManager.isReconnecting) _buildReconnectBanner(),

            // ── Card 1: Band Info ────────────────────────────────────────
            _BandInfoCard(bleManager: bleManager),

            const SizedBox(height: 16),

            // ── Card 2: Activity ─────────────────────────────────────────
            // Always shown: displays live data when connected+authenticated,
            // or last-known data with a "Last synced" label otherwise.
            _ActivityCard(bleManager: bleManager),
          ],
        ),
      ),
    );
  }

  Widget _buildReconnectBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Reconnecting to band...'),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Card 1 — Band Info
// ──────────────────────────────────────────────────────────────────────────────

class _BandInfoCard extends StatelessWidget {
  final BLEManager bleManager;

  const _BandInfoCard({required this.bleManager});

  @override
  Widget build(BuildContext context) {
    final connected = bleManager.isConnected;
    final authState = bleManager.authState;
    final device = bleManager.device;
    final battery = bleManager.batteryLevel;

    String authLabel;
    Color authColor;
    switch (authState) {
      case AuthState.authenticating:
        authLabel = 'Authenticating…';
        authColor = Colors.orange;
        break;
      case AuthState.authenticated:
        authLabel = 'Authenticated';
        authColor = Colors.green;
        break;
      case AuthState.failed:
        authLabel = 'Auth Failed';
        authColor = Colors.red;
        break;
      default:
        authLabel = 'Not Authenticated';
        authColor = Colors.grey;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.watch, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    device?.platformName.isNotEmpty == true
                        ? device!.platformName
                        : 'Mi Band',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                // Battery badge
                if (battery != null)
                  _BatteryBadge(level: battery)
                else if (connected)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: 'Connection',
              value: connected ? 'Connected' : 'Disconnected',
              color: connected ? Colors.green : Colors.red,
            ),
            const Divider(height: 20),
            _InfoRow(
              label: 'Auth',
              value: authLabel,
              color: authColor,
            ),
            if (device != null) ...[
              const Divider(height: 20),
              _InfoRow(
                label: 'MAC Address',
                value: device.remoteId.str,
                color: Colors.blueGrey,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Card 2 — Today's Activity (always visible, shows last-known data)
// ──────────────────────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final BLEManager bleManager;
  const _ActivityCard({required this.bleManager});

  @override
  Widget build(BuildContext context) {
    final m = bleManager.metrics;
    final isLive = bleManager.authState == AuthState.authenticated;
    final lastSync = bleManager.lastSyncTime;
    final hasData = m.steps > 0 || m.distanceMeters > 0 || m.calories > 0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "Today's Activity",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // Live indicator or last-sync badge
                if (isLive)
                  _LiveBadge()
                else if (lastSync != null)
                  _LastSyncBadge(time: lastSync),
              ],
            ),
            const SizedBox(height: 20),
            if (!hasData && !isLive)
              // Never had data — show a subtle empty state
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    'No activity data yet.\nConnect your band to start syncing.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MetricTile(
                    icon: Icons.directions_walk,
                    label: 'Steps',
                    value: _fmt(m.steps),
                    color: Colors.deepPurple,
                  ),
                  _MetricTile(
                    icon: Icons.straighten,
                    label: 'Distance',
                    value: '${m.distanceMeters} m',
                    color: Colors.teal,
                  ),
                  _MetricTile(
                    icon: Icons.local_fire_department,
                    label: 'Calories',
                    value: '${m.calories} kcal',
                    color: Colors.deepOrange,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}k';
    }
    return n.toString();
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Live badge
// ──────────────────────────────────────────────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Live',
            style: TextStyle(
              color: Colors.green.shade700,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Last Synced badge
// ──────────────────────────────────────────────────────────────────────────────

class _LastSyncBadge extends StatelessWidget {
  final DateTime time;
  const _LastSyncBadge({required this.time});

  String _ago() {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            'Synced ${_ago()}',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ──────────────────────────────────────────────────────────────────────────────

class _BatteryBadge extends StatelessWidget {
  final int level;
  const _BatteryBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    final color = level > 50
        ? Colors.green
        : level > 20
            ? Colors.orange
            : Colors.red;

    final icon = level > 80
        ? Icons.battery_full
        : level > 50
            ? Icons.battery_4_bar
            : level > 20
                ? Icons.battery_2_bar
                : Icons.battery_1_bar;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 2),
        Text(
          '$level%',
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
