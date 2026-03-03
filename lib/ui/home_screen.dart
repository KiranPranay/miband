import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth_manager.dart';
import '../core/ble_manager.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authManager = context.watch<AuthManager>();
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
            // ── Status / reconnect banner ────────────────────────────
            if (bleManager.isReconnecting) _buildReconnectBanner(),
            if (!bleManager.isConnected && !bleManager.isReconnecting)
              _buildDisconnectedBanner(context),

            // ── Card 1: Band Info ────────────────────────────────────
            _BandInfoCard(
              bleManager: bleManager,
              authManager: authManager,
            ),

            const SizedBox(height: 16),

            // ── Card 2: Activity ─────────────────────────────────────
            if (bleManager.authState == AuthState.authenticated)
              _ActivityCard(bleManager: bleManager)
            else
              _NotAuthCard(bleManager: bleManager),
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

  Widget _buildDisconnectedBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_disabled, color: Colors.redAccent),
          const SizedBox(width: 12),
          const Expanded(child: Text('Band not connected')),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            child: const Text('Connect'),
          ),
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
  final AuthManager authManager;

  const _BandInfoCard({required this.bleManager, required this.authManager});

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
            if (!authManager.hasKey) ...[
              const Divider(height: 20),
              _InfoRow(
                label: 'Auth Key',
                value: 'Not set — go to Settings',
                color: Colors.orange,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Card 2 — Today's Activity
// ──────────────────────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final BLEManager bleManager;
  const _ActivityCard({required this.bleManager});

  @override
  Widget build(BuildContext context) {
    final m = bleManager.metrics;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Today's Activity",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
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
// Placeholder when not yet authenticated
// ──────────────────────────────────────────────────────────────────────────────

class _NotAuthCard extends StatelessWidget {
  final BLEManager bleManager;
  const _NotAuthCard({required this.bleManager});

  @override
  Widget build(BuildContext context) {
    final isAuthenticating = bleManager.authState == AuthState.authenticating;

    return Card(
      elevation: 2,
      color: Colors.grey.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            if (isAuthenticating)
              const CircularProgressIndicator()
            else
              Icon(Icons.lock_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              isAuthenticating
                  ? 'Authenticating with band…'
                  : bleManager.isConnected
                      ? 'Authentication failed.\nCheck your auth key in Settings.'
                      : 'Connect your band to see activity data.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
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
