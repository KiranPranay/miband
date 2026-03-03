import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth_manager.dart';
import '../core/ble_manager.dart';
import 'device_scan_screen.dart';
import 'auth_key_screen.dart';
import 'debug_console.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authManager = context.watch<AuthManager>();
    final bleManager = context.watch<BLEManager>();

    return Scaffold(
      appBar: AppBar(title: const Text('Mi Band Authenticator')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildStatusCard(authManager, bleManager, context),
            const SizedBox(height: 24),
            _buildActionButtons(context, bleManager),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    AuthManager auth,
    BLEManager ble,
    BuildContext context,
  ) {
    String connStatus = ble.isConnected ? "Connected" : "Disconnected";
    Color connColor = ble.isConnected ? Colors.green : Colors.red;

    String authStatus;
    Color authColor;

    switch (ble.authState) {
      case AuthState.notAuthenticated:
        authStatus = "Not Authenticated";
        authColor = Colors.grey;
        break;
      case AuthState.authenticating:
        authStatus = "Authenticating...";
        authColor = Colors.yellow;
        break;
      case AuthState.authenticated:
        authStatus = "Authenticated";
        authColor = Colors.green;
        break;
      case AuthState.failed:
        authStatus = "Auth Failed";
        authColor = Colors.red;
        break;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _InfoRow(
              label: "Key Present",
              value: auth.hasKey ? "Yes" : "No",
              color: auth.hasKey ? Colors.green : Colors.red,
            ),
            const Divider(),
            _InfoRow(label: "Connection", value: connStatus, color: connColor),
            const Divider(),
            _InfoRow(label: "Auth State", value: authStatus, color: authColor),
            const Divider(),
            _InfoRow(
              label: "MAC Address",
              value: ble.device?.remoteId.str ?? "N/A",
              color: Colors.blueAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, BLEManager ble) {
    return Column(
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text('Scan Devices'),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
          icon: const Icon(Icons.key),
          label: const Text('Update Auth Key'),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AuthKeyScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        if (ble.isConnected)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: Colors.redAccent,
            ),
            icon: const Icon(Icons.cancel),
            label: const Text(
              'Disconnect',
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () => ble.disconnect(),
          ),
        const SizedBox(height: 32),
        TextButton.icon(
          icon: const Icon(Icons.bug_report),
          label: const Text('View Debug Log'),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DebugConsole()),
            );
          },
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
