import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings i = AppSettings._();

  late SharedPreferences _p;
  ThemeMode mode = ThemeMode.system;
  double fontScale = 1.0;
  int lastBackupMs = 0;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final m = (_p.getInt('mode') ?? 0).clamp(0, 2).toInt();
    mode = ThemeMode.values[m];
    fontScale = _p.getDouble('font') ?? 1.0;
    lastBackupMs = _p.getInt('last_backup') ?? 0;
  }

  void setMode(ThemeMode m) {
    mode = m;
    _p.setInt('mode', m.index);
    notifyListeners();
  }

  void setFont(double f) {
    fontScale = f;
    _p.setDouble('font', f);
    notifyListeners();
  }

  void markBackup() {
    lastBackupMs = DateTime.now().millisecondsSinceEpoch;
    _p.setInt('last_backup', lastBackupMs);
    notifyListeners();
  }
}
