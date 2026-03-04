import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'core/logger.dart';
import 'storage/secure_storage.dart';
import 'core/auth_manager.dart';
import 'core/ble_manager.dart';

import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  final logger = BLELogger();
  final storage = StorageManager(logger);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: logger),
        Provider.value(value: storage),
        ChangeNotifierProvider(create: (_) => AuthManager(logger, storage)),
        ChangeNotifierProvider(create: (_) => BLEManager(logger, storage)),
      ],
      child: const MiBandApp(),
    ),
  );
}

class MiBandApp extends StatelessWidget {
  const MiBandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'Mi Band',
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const _AppRoot(),
      ),
    );
  }
}

/// Triggers auto-connect once after the widget tree is ready.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  @override
  void initState() {
    super.initState();
    // Auto-connect to the last known device after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BLEManager>().tryAutoConnect();
    });
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
