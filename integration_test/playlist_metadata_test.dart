import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:media_kit/media_kit.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/playback/media_kit_engine.dart';
import 'package:musani/playback/playback_engine.dart';
import 'package:musani/playlists/models.dart';
import 'package:musani/playlists/playlist_repository.dart';
import 'package:musani/ui/metadata_editor_dialog.dart';
import 'package:musani/ui/player_page.dart';
import 'package:musani/ui/album_artwork.dart';

import '../test/support/audio_fixtures.dart';
import '../test/support/memory_repeat_mode_store.dart';
import 'library_test.dart' show pumpUntil;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'edit external MP3/FLAC from playlist and refresh all repeated labels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      MediaKit.ensureInitialized();
      final dir = await Directory.systemTemp.createTemp(
        'musani-playlist-edit-',
      );
      final library = LibraryRepository('${dir.path}/catalog');
      final playlists = PlaylistRepository(library.directory);
      final playlist = await playlists.create('External');
      final refs = <PlaylistTrackRef>[];
      for (final format in ['mp3', 'flac']) {
        final file = await createAudioFixture(
          Directory('${dir.path}/music'),
          format,
          name: format,
          title: 'Old $format',
        );
        final ref = PlaylistTrackRef(path: file.path, title: 'Old $format');
        refs.addAll([ref, ref]);
      }
      await playlists.add(playlist.id, 0, refs);
      final original = await playlists.detail(playlist.id);
      final controller = LibraryController(library);
      final engine = MediaKitEngine(
        Player(),
        repeatModeStore: MemoryRepeatModeStore(),
      );
      await engine.setRepeatMode(RepeatMode.one);
      await engine.open(original.entries.map((e) => e.track.playable).toList());
      final queue = engine.state.queue;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerPage(engine: engine, library: controller),
          ),
        );
        await pumpUntil(
          tester,
          () => controller.initialized && !controller.loading,
        );
        await pumpUntil(
          tester,
          () =>
              tester
                  .widget<AlbumArtwork>(
                    find.byKey(const Key('now-playing-artwork')),
                  )
                  .path !=
              null,
        );
        await tester.tap(find.text('Плейлисты'));
        await tester.pumpAndSettle();
        await pumpUntil(
          tester,
          () => find.text('External').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('External'));
        await pumpUntil(
          tester,
          () => find.text('Old mp3').evaluate().length >= 2,
        );
        await tester.pumpAndSettle();
        for (final index in [0, 2]) {
          await engine.jump(index);
          // Keep playback paused while editing; saving must preserve that state.
          await pumpUntil(
            tester,
            () => engine.state.index == index && engine.state.playing,
          );
          await engine.toggle();
          await pumpUntil(tester, () => !engine.state.playing);
          final entry = original.entries[index];
          await tester.ensureVisible(
            find.byKey(Key('playlist-entry-menu-${entry.id}')),
          );
          await tester.tap(find.byKey(Key('playlist-entry-menu-${entry.id}')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Редактировать метаданные'));
          await pumpUntil(
            tester,
            () => find.byKey(const Key('metadata-TITLE')).evaluate().isNotEmpty,
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('metadata-TITLE')),
            'New $index',
          );
          await tester.enterText(
            find.byKey(const Key('metadata-artist-0')),
            'Tyler, The Creator',
          );
          await tester.ensureVisible(
            find.byKey(const Key('metadata-add-artist')),
          );
          await tester.tap(find.byKey(const Key('metadata-add-artist')));
          await tester.pump();
          await tester.ensureVisible(
            find.byKey(const Key('metadata-artist-1')),
          );
          await tester.enterText(
            find.byKey(const Key('metadata-artist-1')),
            'Guest',
          );
          await tester.tap(find.text('Сохранить'));
          await pumpUntil(
            tester,
            () =>
                find.byType(MetadataEditorDialog).evaluate().isEmpty &&
                !controller.loading,
          );
          await pumpUntil(
            tester,
            () =>
                tester
                    .widget<Text>(find.byKey(const Key('now-playing-title')))
                    .data ==
                'New $index',
          );
          await pumpUntil(
            tester,
            () => find.text('New $index').evaluate().length == 3,
          );
          expect(
            tester
                .widget<Text>(find.byKey(const Key('now-playing-artists')))
                .data,
            'Tyler, The Creator / Guest',
          );
          expect(engine.state.playing, isFalse);
          expect(engine.state.index, index);
          expect(engine.state.repeatMode, RepeatMode.one);
          expect(engine.state.queue, same(queue));
        }
        final reopened = await PlaylistRepository(library.directory)
            .detail(playlist.id);
        expect(
          reopened.entries.map((e) => e.id),
          original.entries.map((e) => e.id),
        );
        expect(
          reopened.entries.map((e) => e.track.trackId),
          everyElement(isNull),
        );
        expect(controller.status.trackCount, 0);
        await tester.tap(find.byTooltip('Очередь воспроизведения'));
        await tester.pumpAndSettle();
        expect(find.text('New 0'), findsNWidgets(2));
        expect(find.text('New 2'), findsNWidgets(3));
        expect(find.text('Tyler, The Creator / Guest'), findsNWidgets(5));
      } finally {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await dir.delete(recursive: true);
      }
    },
  );
}
