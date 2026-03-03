import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/logger.dart';
import 'storage/secure_storage.dart';
import 'core/auth_manager.dart';
import 'core/ble_manager.dart';

import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
    return MaterialApp(
      title: 'Mi Band 6 Authenticator',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
