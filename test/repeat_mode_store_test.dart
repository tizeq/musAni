import 'package:flutter_test/flutter_test.dart';
import 'package:musani/playback/playback_engine.dart';
import 'package:musani/settings/repeat_mode_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('missing and unknown preferences fall back to Off', () async {
    expect(await PreferencesRepeatModeStore().load(), RepeatMode.off);
    await SharedPreferencesAsync().setString('playback.repeatMode', 'unknown');
    expect(await PreferencesRepeatModeStore().load(), RepeatMode.off);
  });

  for (final mode in RepeatMode.values) {
    test('$mode is restored by a new store instance', () async {
      await PreferencesRepeatModeStore().save(mode);
      expect(await PreferencesRepeatModeStore().load(), mode);
      expect(
        await SharedPreferencesAsync().getString('playback.repeatMode'),
        mode.name,
      );
    });
  }
}
