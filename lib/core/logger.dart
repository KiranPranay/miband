import 'package:flutter/foundation.dart';

class BLELogger extends ChangeNotifier {
  final List<String> _logs = [];

  List<String> get logs => List.unmodifiable(_logs);

  void e(String message) {
    debugPrint('[ERROR] $message');
    _logs.add('[${DateTime.now().toLocal()}] [ERROR] $message');
    notifyListeners();
  }

  void d(String message) {
    debugPrint('[DEBUG] $message');
    _logs.add('[${DateTime.now().toLocal()}] [DEBUG] $message');
    notifyListeners();
  }

  void i(String message) {
    debugPrint('[INFO] $message');
    _logs.add('[${DateTime.now().toLocal()}] [INFO] $message');
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }
}
