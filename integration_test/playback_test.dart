import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musani/files/local_tracks.dart';
import 'package:musani/playback/media_kit_engine.dart';
import 'package:musani/playback/playback_engine.dart';

import '../test/support/memory_repeat_mode_store.dart';

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 12));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Playback state timed out');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<List<LocalTrack>> createTracks(Directory directory) async {
  // 3 seconds PCM silence: real decoding without an audible test tone.
  const length = 44100 * 2 * 3;
  final bytes = Uint8List(44 + length);
  final data = ByteData.sublistView(bytes);
  void ascii(int offset, String text) =>
      bytes.setRange(offset, offset + text.length, text.codeUnits);
  ascii(0, 'RIFF');
  data.setUint32(4, 36 + length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 44100, Endian.little);
  data.setUint32(28, 88200, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, length, Endian.little);
  final a = await File('${directory.path}/Тест #1.wav').writeAsBytes(bytes);
  final b = await File('${directory.path}/second.wav').writeAsBytes(bytes);
  return LocalTracks().resolve([a.path, b.path]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native shuffle keeps the active track and restores queue order',
    (tester) async {
      MediaKit.ensureInitialized();
      final directory = await Directory.systemTemp.createTemp(
        'musani-shuffle-',
      );
      final engine = MediaKitEngine(
        Player(),
        repeatModeStore: MemoryRepeatModeStore(),
      );
      try {
        final tracks = await createTracks(directory);
        final duplicate = LocalTrack(tracks.first.uri, 'Повтор в очереди');
        final queue = [tracks.first, tracks.last, duplicate];
        await engine.open(queue, index: 2);
        await until(() => engine.state.position.inMilliseconds > 100);
        await engine.toggle();
        await until(() => !engine.state.playing);
        await engine.seek(const Duration(seconds: 1));
        await until(() => engine.state.position.inMilliseconds >= 900);
        final position = engine.state.position;
        await engine.setShuffle(true);
        final shuffled = engine.state;
        expect(shuffled.shuffle, isTrue);
        expect(shuffled.queue, unorderedEquals(queue));
        expect(shuffled.queue[shuffled.index], same(duplicate));
        expect(shuffled.position, position);
        expect(shuffled.playing, isFalse);
        await engine.setShuffle(false);
        expect(engine.state.shuffle, isFalse);
        expect(engine.state.queue, queue);
        expect(engine.state.index, 2);

        await engine.setShuffle(true);
        final replacement = [duplicate, tracks.last, tracks.first];
        final reported = <PlaybackState>[];
        final subscription = engine.changes.listen(reported.add);
        await engine.open(replacement, index: 1);
        await until(
          () =>
              engine.state.playing &&
              engine.state.position.inMilliseconds > 100,
        );
        final replaced = engine.state;
        expect(replaced.shuffle, isTrue);
        expect(replaced.currentTrack, same(tracks.last));
        expect(replaced.queue, unorderedEquals(replacement));
        expect(
          reported.where((state) => identical(state.queue, replaced.queue)),
          isNotEmpty,
        );
        expect(
          reported
              .where((state) => identical(state.queue, replaced.queue))
              .every((state) => identical(state.currentTrack, tracks.last)),
          isTrue,
        );
        await subscription.cancel();
        await engine.setShuffle(false);
        expect(engine.state.queue, replacement);
        expect(engine.state.index, 1);
      } finally {
        await engine.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  for (final mode in RepeatMode.values) {
    testWidgets(
      'native $mode: pause, seek, manual selection and end of queue',
      (tester) async {
        MediaKit.ensureInitialized();
        final directory = await Directory.systemTemp.createTemp(
          'musani-repeat-',
        );
        final store = MemoryRepeatModeStore(mode);
        final engine = MediaKitEngine(Player(), repeatModeStore: store);
        try {
          await engine.restoreRepeatMode();
          await engine.open(await createTracks(directory));
          await until(
            () =>
                engine.state.playing &&
                engine.state.position.inMilliseconds > 100,
          );
          expect(engine.state.repeatMode, mode);
          await engine.toggle();
          await until(() => !engine.state.playing);
          await engine.setRepeatMode(mode);
          await engine.seek(const Duration(seconds: 1));
          await until(() => engine.state.position.inMilliseconds >= 900);
          final pausedPosition = engine.state.position;
          await Future<void>.delayed(const Duration(milliseconds: 250));
          expect(engine.state.playing, isFalse);
          // libmpv can refine the seek timestamp to the nearest audio sample.
          expect(
            (engine.state.position - pausedPosition).abs(),
            lessThanOrEqualTo(const Duration(milliseconds: 1)),
          );
          expect(engine.state.index, 0);

          // Manual selection must work in Repeat One too, and retain the mode.
          await engine.jump(1);
          await until(
            () =>
                engine.state.index == 1 &&
                engine.state.playing &&
                engine.state.position.inMilliseconds > 100 &&
                engine.state.position.inMilliseconds < 1500,
          );
          expect(engine.state.repeatMode, mode);
          await engine.seek(const Duration(milliseconds: 2600));
          await until(() => engine.state.position.inMilliseconds >= 2500);
          switch (mode) {
            case RepeatMode.off:
              await until(() => !engine.state.playing);
              expect(engine.state.index, 1);
            case RepeatMode.all:
              await until(
                () => engine.state.index == 0 && engine.state.playing,
              );
            case RepeatMode.one:
              // Observe two restarts, rather than mistaking a stopped file for a loop.
              for (var cycle = 0; cycle < 2; cycle++) {
                await until(
                  () =>
                      engine.state.position.inMilliseconds < 1000 &&
                      engine.state.playing,
                );
                expect(engine.state.index, 1);
                if (cycle == 0) {
                  await engine.seek(const Duration(milliseconds: 2600));
                  await until(
                    () => engine.state.position.inMilliseconds >= 2500,
                  );
                }
              }
          }
          expect(engine.state.repeatMode, mode);
          expect(engine.state.error, isNull);
          expect(store.value, mode);
        } finally {
          await engine.dispose();
          await directory.delete(recursive: true);
        }
      },
    );
  }

  testWidgets(
    'native single-track queue and changing One -> All -> Off while playing',
    (tester) async {
      MediaKit.ensureInitialized();
      final directory = await Directory.systemTemp.createTemp('musani-single-');
      final engine = MediaKitEngine(
        Player(),
        repeatModeStore: MemoryRepeatModeStore(),
      );
      try {
        final tracks = await createTracks(directory);
        await engine.open([tracks.first]);
        await until(
          () => engine.state.playing && engine.state.duration.inSeconds == 3,
        );
        for (final mode in [RepeatMode.one, RepeatMode.all, RepeatMode.off]) {
          await engine.setRepeatMode(mode);
          expect(engine.state.playing, isTrue);
          await engine.seek(const Duration(milliseconds: 2600));
          await until(() => engine.state.position.inMilliseconds >= 2500);
          if (mode == RepeatMode.off) {
            await until(() => !engine.state.playing);
          } else {
            await until(
              () =>
                  engine.state.playing &&
                  engine.state.position.inMilliseconds < 1000,
            );
          }
          expect(engine.state.index, 0);
          expect(engine.state.error, isNull);
        }
      } finally {
        await engine.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets('native decode, seek, pause, volume and queue', (tester) async {
    MediaKit.ensureInitialized();
    final directory = await Directory.systemTemp.createTemp('musani-audio-');
    final engine = MediaKitEngine(
      Player(),
      repeatModeStore: MemoryRepeatModeStore(),
    );
    try {
      await engine.open(await createTracks(directory));
      await until(
        () =>
            engine.state.playing && engine.state.position.inMilliseconds > 100,
      );
      expect(engine.state.duration.inSeconds, 3);
      await engine.toggle();
      await until(() => !engine.state.playing);
      await engine.seek(const Duration(seconds: 1));
      await until(() => engine.state.position.inMilliseconds >= 900);
      await engine.setVolume(25);
      await until(() => engine.state.volume == 25);
      await engine.seek(const Duration(milliseconds: 2700));
      await engine.toggle();
      await until(() => engine.state.index == 1 && engine.state.playing);
      await engine.jump(0);
      await until(() => engine.state.index == 0 && engine.state.playing);
      await engine.jump(1);
      await until(() => engine.state.index == 1 && engine.state.playing);
      expect(engine.state.error, isNull);
      await until(() => !engine.state.playing);
    } finally {
      await engine.dispose();
      await directory.delete(recursive: true);
    }
  });
}
