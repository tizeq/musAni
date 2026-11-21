import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:media_kit/media_kit.dart';
import 'package:musani/files/local_tracks.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/playback/media_kit_engine.dart';
import 'package:musani/playback/playback_engine.dart';
import 'package:musani/ui/library_page.dart';
import 'package:musani/ui/player_page.dart';

import 'support/library_fakes.dart';
import 'support/memory_repeat_mode_store.dart';
import 'support/recording_platform_player.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('musani-playlist-playback-');
    for (var i = 0; i < 2; i++) {
      await File('${dir.path}/$i.mp3').writeAsBytes([0]);
    }
  });
  tearDown(() => dir.delete(recursive: true));
  for (final mode in RepeatMode.values) {
    testWidgets(
      'playlist playback preserves duplicates, selected index and $mode; stale files preserve old queue',
      (tester) async {
        final libraryTracks = sampleLibraryTracks(dir.path);
        final library = LibraryController(FakeLibraryRepository(libraryTracks));
        final engine = MediaKitEngine(
          Player(platformPlayer: RecordingPlatformPlayer()),
          repeatModeStore: MemoryRepeatModeStore(mode),
        );
        await engine.restoreRepeatMode();
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerPage(engine: engine, library: library),
          ),
        );
        await tester.pumpAndSettle();
        final play = tester
            .widget<LibraryPage>(find.byType(LibraryPage))
            .onPlayPlaylist!;
        final queue = [
          libraryTracks[1].playable,
          libraryTracks[0].playable,
          libraryTracks[1].playable,
        ];
        await tester.runAsync(() => play(queue, 1));
        await tester.pumpAndSettle();
        expect(
          engine.state.queue.map((track) => track.uri),
          queue.map((track) => track.uri),
        );
        expect(engine.state.queue, hasLength(3));
        expect(engine.state.index, 1);
        expect(engine.state.repeatMode, mode);
        await tester.runAsync(
          () => engine.seek(const Duration(milliseconds: 250)),
        );
        final oldQueue = engine.state.queue;
        await tester.runAsync(
          () => play([
            queue.first,
            LocalTrack(Uri.file('${dir.path}/missing.mp3'), 'Missing'),
          ], 0),
        );
        await tester.pumpAndSettle();
        expect(identical(oldQueue, engine.state.queue), isTrue);
        expect(engine.state.index, 1);
        expect(engine.state.position, const Duration(milliseconds: 250));
        expect(engine.state.repeatMode, mode);
        expect(find.textContaining('Ошибка:'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
