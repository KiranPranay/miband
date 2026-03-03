import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/logger.dart';

class DebugConsole extends StatelessWidget {
  const DebugConsole({super.key});

  @override
  Widget build(BuildContext context) {
    final logger = context.watch<BLELogger>();
    final logs = logger.logs.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => context.read<BLELogger>().clearLogs(),
            tooltip: 'Clear Logs',
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: logs.length,
        padding: const EdgeInsets.all(8.0),
        itemBuilder: (context, index) {
          final log = logs[index];
          Color textColor = Colors.white70;
          if (log.contains('[ERROR]')) textColor = Colors.redAccent;
          if (log.contains('[INFO]')) textColor = Colors.lightBlueAccent;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(
              log,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: textColor,
              ),
            ),
          );
        },
      ),
    );
  }
}
