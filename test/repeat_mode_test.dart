import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musani/files/local_tracks.dart';
import 'package:musani/playback/media_kit_engine.dart';
import 'package:musani/playback/playback_engine.dart';

import 'support/memory_repeat_mode_store.dart';
import 'support/recording_platform_player.dart';

void main() {
  test('repeat cycles Off -> All -> One -> Off', () {
    expect(const PlaybackState().repeatMode, RepeatMode.off);
    expect(RepeatMode.off.next, RepeatMode.all);
    expect(RepeatMode.all.next, RepeatMode.one);
    expect(RepeatMode.one.next, RepeatMode.off);
  });

  late RecordingPlatformPlayer backend;
  late MemoryRepeatModeStore store;
  late MediaKitEngine engine;
  setUp(() {
    backend = RecordingPlatformPlayer();
    store = MemoryRepeatModeStore();
    engine = MediaKitEngine(
      Player(platformPlayer: backend),
      repeatModeStore: store,
    );
  });
  tearDown(() => engine.dispose());

  const nativeModes = {
    RepeatMode.off: PlaylistMode.none,
    RepeatMode.all: PlaylistMode.loop,
    RepeatMode.one: PlaylistMode.single,
  };
  for (final mode in RepeatMode.values) {
    test(
      'restores $mode before opening a queue without rewriting it',
      () async {
        store.value = mode;
        await engine.restoreRepeatMode();
        expect(engine.state.repeatMode, mode);
        expect(backend.modes, [nativeModes[mode]]);
        expect(store.savedModes, isEmpty);
        expect(engine.state.queue, isEmpty);
      },
    );

    test('$mode is applied, emitted and saved', () async {
      final emitted = engine.changes.firstWhere(
        (state) => state.repeatMode == mode,
      );
      await engine.setRepeatMode(mode);
      expect((await emitted).repeatMode, mode);
      expect(backend.modes, [nativeModes[mode]]);
      expect(store.value, mode);
      expect(store.savedModes, [mode]);
    });

    test('$mode survives open, manual selection, pause and seek', () async {
      final tracks = [
        LocalTrack(Uri.file('/tmp/a.wav'), 'a.wav'),
        LocalTrack(Uri.file('/tmp/b.wav'), 'b.wav'),
      ];
      await engine.setRepeatMode(mode);
      await engine.open(tracks);
      await engine.jump(1);
      expect(engine.state.index, 1);
      await engine.toggle();
      expect(engine.state.playing, isFalse);
      await engine.seek(const Duration(seconds: 2));
      expect(engine.state.playing, isFalse);
      expect(engine.state.position, const Duration(seconds: 2));
      expect(engine.state.repeatMode, mode);
      expect(store.savedModes, [mode]);
    });
  }

  test('read failure falls back to Off with a visible error', () async {
    store.loadError = StateError('read denied');
    await engine.restoreRepeatMode();
    expect(engine.state.repeatMode, RepeatMode.off);
    expect(engine.state.error, contains('read denied'));
  });

  test(
    'album starts at selected index with full order and repeat mode intact',
    () async {
      final tracks = [
        LocalTrack(Uri.file('/tmp/a.wav'), 'a'),
        LocalTrack(Uri.file('/tmp/b.wav'), 'b'),
      ];
      await engine.setRepeatMode(RepeatMode.one);
      await engine.open(tracks, index: 1);
      expect(engine.state.index, 1);
      expect(engine.state.queue, tracks);
      expect(engine.state.repeatMode, RepeatMode.one);
      await expectLater(engine.open(tracks, index: 2), throwsRangeError);
      expect(engine.state.queue, tracks);
      expect(engine.state.index, 1);
    },
  );

  test('native failure does not save a mode that was not applied', () async {
    backend.modeError = StateError('native failure');
    await expectLater(engine.setRepeatMode(RepeatMode.one), throwsStateError);
    expect(engine.state.repeatMode, RepeatMode.off);
    expect(store.value, RepeatMode.off);
    expect(store.savedModes, isEmpty);
  });

  test(
    'write failure is reported while state reflects active native mode',
    () async {
      store.saveError = StateError('write denied');
      await expectLater(
        engine.setRepeatMode(RepeatMode.all),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('write denied'),
          ),
        ),
      );
      expect(engine.state.repeatMode, RepeatMode.all);
      expect(store.value, RepeatMode.off);
    },
  );
}
