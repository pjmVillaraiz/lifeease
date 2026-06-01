import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'language_controller.dart';

class SettingsController extends ChangeNotifier {
  static late SettingsController instance;

  static const String _darkModeKey = 'darkMode';
  static const String _largeTextKey = 'largeText';
  static const String _highContrastKey = 'highContrast';
  static const String _tagalogKey = 'tagalog';
  static const String _notificationsKey = 'notificationsEnabled';
  static const String _soundKey = 'soundEnabled';
  static const String _vibrationKey = 'vibrationEnabled';
  static const String _reminderLeadTimeKey = 'reminderLeadTime';
  static const String _wakeWordKey = 'wakeWordEnabled';

  bool darkMode = false;
  bool largeText = false;
  bool highContrast = false;
  bool tagalog = false;

  bool notificationsEnabled = true;
  bool soundEnabled = true;
  bool vibrationEnabled = true;
  bool wakeWordEnabled = false;
  String reminderLeadTime = '15 minutes';

  SettingsController._();

  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final controller = SettingsController._();

    controller.darkMode = prefs.getBool(_darkModeKey) ?? false;
    controller.largeText = prefs.getBool(_largeTextKey) ?? false;
    controller.highContrast = prefs.getBool(_highContrastKey) ?? false;
    controller.tagalog = prefs.getBool(_tagalogKey) ?? false;
    controller.notificationsEnabled = prefs.getBool(_notificationsKey) ?? true;
    controller.soundEnabled = prefs.getBool(_soundKey) ?? true;
    controller.vibrationEnabled = prefs.getBool(_vibrationKey) ?? true;
    controller.wakeWordEnabled = prefs.getBool(_wakeWordKey) ?? false;
    controller.reminderLeadTime =
        prefs.getString(_reminderLeadTimeKey) ?? '15 minutes';

    SettingsController.instance = controller;
    LanguageController.isTagalog.value = controller.tagalog;
    return controller;
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  void updateDarkMode(bool enabled) {
    darkMode = enabled;
    _saveBool(_darkModeKey, enabled);
    notifyListeners();
  }

  void updateLargeText(bool enabled) {
    largeText = enabled;
    _saveBool(_largeTextKey, enabled);
    notifyListeners();
  }

  void updateHighContrast(bool enabled) {
    highContrast = enabled;
    _saveBool(_highContrastKey, enabled);
    notifyListeners();
  }

  void updateTagalog(bool enabled) {
    tagalog = enabled;
    LanguageController.isTagalog.value = enabled;
    _saveBool(_tagalogKey, enabled);
    notifyListeners();
  }

  void updateNotificationsEnabled(bool enabled) {
    notificationsEnabled = enabled;
    _saveBool(_notificationsKey, enabled);
    notifyListeners();
  }

  void updateSoundEnabled(bool enabled) {
    soundEnabled = enabled;
    _saveBool(_soundKey, enabled);
    notifyListeners();
  }

  void updateVibrationEnabled(bool enabled) {
    vibrationEnabled = enabled;
    _saveBool(_vibrationKey, enabled);
    notifyListeners();
  }

  void updateWakeWordEnabled(bool enabled) {
    wakeWordEnabled = enabled;
    _saveBool(_wakeWordKey, enabled);
    notifyListeners();
  }

  void updateReminderLeadTime(String value) {
    reminderLeadTime = value;
    _saveString(_reminderLeadTimeKey, value);
    notifyListeners();
  }

  ThemeMode get themeMode => darkMode ? ThemeMode.dark : ThemeMode.light;

  double get textScaleFactor => largeText ? 1.25 : 1.0;

  String translate(String english, String tagalogText) {
    return tagalog ? tagalogText : english;
  }
}
