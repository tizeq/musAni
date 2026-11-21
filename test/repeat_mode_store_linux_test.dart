import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musani/playback/media_kit_engine.dart';
import 'package:musani/playback/playback_engine.dart';
import 'package:musani/settings/repeat_mode_store.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:shared_preferences_linux/shared_preferences_linux.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'support/recording_platform_player.dart';

class TemporaryPathProvider extends PathProviderLinux {
  TemporaryPathProvider(this.path);
  final String path;

  @override
  Future<String> getApplicationSupportPath() async => path;
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('musani-preferences-');
  });
  tearDown(() => directory.delete(recursive: true));

  void recreateBackend() {
    SharedPreferencesAsyncPlatform.instance = SharedPreferencesAsyncLinux()
      ..pathProvider = TemporaryPathProvider(directory.path);
  }

  for (final mode in RepeatMode.values) {
    test('$mode survives a fresh Linux backend reading from disk', () async {
      recreateBackend();
      await PreferencesRepeatModeStore().save(mode);
      expect(
        await File('${directory.path}/shared_preferences.json').exists(),
        isTrue,
      );
      // Discard the plugin cache, just as when a new application starts.
      recreateBackend();
      expect(await PreferencesRepeatModeStore().load(), mode);
    });
  }

  test('malformed Linux preferences safely fall back to Off', () async {
    await File('${directory.path}/shared_preferences.json')
        .writeAsString('{broken');
    recreateBackend();
    final engine = MediaKitEngine(
      Player(platformPlayer: RecordingPlatformPlayer()),
      repeatModeStore: PreferencesRepeatModeStore(),
    );
    try {
      await engine.restoreRepeatMode();
      expect(engine.state.repeatMode, RepeatMode.off);
      expect(engine.state.error, contains('FormatException'));
    } finally {
      await engine.dispose();
    }
  });
}
