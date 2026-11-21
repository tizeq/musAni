import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_engine.dart';

abstract interface class RepeatModeStore {
  Future<RepeatMode> load();
  Future<void> save(RepeatMode mode);
}

class PreferencesRepeatModeStore implements RepeatModeStore {
  PreferencesRepeatModeStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;
  static const _key = 'playback.repeatMode';

  @override
  Future<RepeatMode> load() async =>
      switch (await _preferences.getString(_key)) {
        'all' => RepeatMode.all,
        'one' => RepeatMode.one,
        _ => RepeatMode.off,
      };

  @override
  Future<void> save(RepeatMode mode) => _preferences.setString(_key, mode.name);
}
