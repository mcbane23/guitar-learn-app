import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';

/// User settings, stored on the device only.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences? _prefs;

  static Future<AppSettings> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    return AppSettings._(prefs).._read();
  }

  /// Settings that are not saved (for tests).
  factory AppSettings.inMemory() => AppSettings._(null);

  /// null = follow the device language.
  AppLanguage? language;
  bool leftHanded = false;
  bool thinStringOnTop = true;
  bool showNoteNames = false;
  bool showChordName = true;
  bool highContrast = false;
  bool countIn = true;
  double defaultSpeed = 0.75;
  double volume = 0.9;

  void _read() {
    final p = _prefs;
    if (p == null) return;
    final lang = p.getString('language');
    language = AppLanguage.values.where((l) => l.name == lang).firstOrNull;
    leftHanded = p.getBool('leftHanded') ?? leftHanded;
    thinStringOnTop = p.getBool('thinStringOnTop') ?? thinStringOnTop;
    showNoteNames = p.getBool('showNoteNames') ?? showNoteNames;
    showChordName = p.getBool('showChordName') ?? showChordName;
    highContrast = p.getBool('highContrast') ?? highContrast;
    countIn = p.getBool('countIn') ?? countIn;
    defaultSpeed = p.getDouble('defaultSpeed') ?? defaultSpeed;
    volume = p.getDouble('volume') ?? volume;
  }

  /// The language to show, resolving "same as phone".
  AppLanguage resolveLanguage(Locale? device) {
    if (language != null) return language!;
    if (device?.languageCode == 'sr' || device?.languageCode == 'hr' || device?.languageCode == 'bs') {
      return device?.scriptCode == 'Cyrl' ? AppLanguage.srCyrl : AppLanguage.srLatn;
    }
    return AppLanguage.en;
  }

  void update(void Function(AppSettings s) change) {
    change(this);
    notifyListeners();
    final p = _prefs;
    if (p == null) return;
    if (language == null) {
      p.remove('language');
    } else {
      p.setString('language', language!.name);
    }
    p.setBool('leftHanded', leftHanded);
    p.setBool('thinStringOnTop', thinStringOnTop);
    p.setBool('showNoteNames', showNoteNames);
    p.setBool('showChordName', showChordName);
    p.setBool('highContrast', highContrast);
    p.setBool('countIn', countIn);
    p.setDouble('defaultSpeed', defaultSpeed);
    p.setDouble('volume', volume);
  }
}

class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({super.key, required AppSettings settings, required super.child})
      : super(notifier: settings);

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}
