import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth_manager.dart';
import '../core/ble_manager.dart';
import 'device_scan_screen.dart';
import 'auth_key_screen.dart';
import 'debug_console.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authManager = context.watch<AuthManager>();
    final bleManager = context.watch<BLEManager>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ── Device ───────────────────────────────────────────────
          const _SectionHeader(title: 'Device'),
          ListTile(
            leading: const Icon(Icons.bluetooth_searching),
            title: const Text('Scan & Connect'),
            subtitle: bleManager.device != null
                ? Text(
                    bleManager.device!.remoteId.str,
                    style: const TextStyle(fontSize: 12),
                  )
                : const Text('No device paired'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
            ),
          ),
          if (bleManager.isConnected)
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.redAccent),
              title: const Text(
                'Disconnect',
                style: TextStyle(color: Colors.redAccent),
              ),
              subtitle: const Text('Stops auto-reconnect and disconnects'),
              onTap: () => bleManager.disconnect(),
            ),

          const Divider(),

          // ── Auth ─────────────────────────────────────────────────
          const _SectionHeader(title: 'Authentication'),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Auth Key'),
            subtitle: authManager.hasKey
                ? const Text('Key is set ✓',
                    style: TextStyle(color: Colors.green))
                : const Text('No key set',
                    style: TextStyle(color: Colors.orange)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AuthKeyScreen()),
            ),
          ),

          const Divider(),

          // ── Debug ─────────────────────────────────────────────────
          const _SectionHeader(title: 'Developer'),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Debug Log'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DebugConsole()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
