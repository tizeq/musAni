import 'dart:io';

import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:media_kit/media_kit.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/library/models.dart';
import 'package:musani/metadata/track_editor.dart';
import 'package:musani/playback/media_kit_engine.dart';
import 'package:musani/playback/playback_engine.dart';
import 'package:musani/ui/metadata_editor_dialog.dart';
import 'package:musani/ui/album_page.dart';
import 'package:musani/ui/artist_page.dart';
import 'package:musani/ui/library_widgets.dart';
import 'package:musani/ui/player_page.dart';

import '../test/support/audio_fixtures.dart';
import '../test/support/memory_repeat_mode_store.dart';
import 'library_test.dart' show pumpUntil;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'edit MP3/FLAC from context menu while playing or paused; update catalog immediately',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      MediaKit.ensureInitialized();
      final dir = await Directory.systemTemp.createTemp('musani-edit-native-');
      final music = Directory('${dir.path}/music');
      final mp3 = await createAudioFixture(
        music,
        'mp3',
        name: 'a',
        title: 'Original MP3',
      );
      final flac = await createAudioFixture(
        music,
        'flac',
        name: 'b',
        title: 'Original FLAC',
      );
      final repo = LibraryRepository('${dir.path}/catalog');
      await repo.scan(addRoot: music.path);
      final original = (await repo.query(
        const LibraryQuery(view: LibraryView.tracks),
      )).tracks;
      final external = TagLibFile.open(mp3.path)!;
      external.title = 'Fresh external MP3 title';
      expect(external.save(), isTrue);
      external.close();
      final controller = LibraryController(repo);
      final engine = MediaKitEngine(
        Player(),
        repeatModeStore: MemoryRepeatModeStore(),
      );
      await engine.setRepeatMode(RepeatMode.one);
      await engine.open(
        original.map((track) => track.playable).toList(),
        index: original.indexWhere((t) => t.path == flac.path),
      );
      final queue = engine.state.queue;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: PlayerPage(engine: engine, library: controller),
          ),
        );
        await pumpUntil(
          tester,
          () =>
              controller.initialized &&
              !controller.loading &&
              engine.state.playing,
        );
        await tester.tap(find.text('Треки'));
        await pumpUntil(tester, () => !controller.loading);
        await tester.pumpAndSettle();
        for (final track in original) {
          final index = original.indexWhere((value) => value.id == track.id);
          await engine.jump(index);
          await pumpUntil(
            tester,
            () => engine.state.index == index && engine.state.playing,
          );
          final paused = track.path == mp3.path;
          if (paused) {
            if (engine.state.playing) await engine.toggle();
          } else if (!engine.state.playing) {
            await engine.toggle();
          }
          await pumpUntil(tester, () => engine.state.playing != paused);
          await tester.tap(find.byKey(Key('track-menu-${track.id}')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Редактировать метаданные'));
          await pumpUntil(
            tester,
            () => find.byKey(const Key('metadata-TITLE')).evaluate().isNotEmpty,
          );
          await tester.pumpAndSettle();
          final title = tester
              .widget<TextFormField>(find.byKey(const Key('metadata-TITLE')))
              .controller!
              .text;
          expect(
            title,
            track.path == mp3.path
                ? 'Fresh external MP3 title'
                : 'Original FLAC',
          );
          await tester.enterText(
            find.byKey(const Key('metadata-TITLE')),
            'Updated ${track.id}',
          );
          await tester.enterText(
            find.byKey(const Key('metadata-artist-0')),
            'Tyler, The Creator',
          );
          await tester.ensureVisible(
            find.byKey(const Key('metadata-add-artist')),
          );
          await tester.tap(find.byKey(const Key('metadata-add-artist')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const Key('metadata-artist-1')),
          );
          await tester.enterText(
            find.byKey(const Key('metadata-artist-1')),
            'Guest ${track.id}',
          );
          if (track.path == mp3.path) {
            await tester.ensureVisible(find.byKey(const Key('metadata-ALBUM')));
            await tester.enterText(find.byKey(const Key('metadata-ALBUM')), '');
          }
          await tester.pump();
          await tester.tap(find.text('Сохранить'));
          await pumpUntil(
            tester,
            () =>
                find.byType(MetadataEditorDialog).evaluate().isEmpty &&
                !controller.loading,
          );
          final updated = await repo.track(track.id);
          expect(updated!.metadata.title, 'Updated ${track.id}');
          expect(updated.metadata.artists, [
            'Tyler, The Creator',
            'Guest ${track.id}',
          ]);
          if (track.path == mp3.path) expect(updated.albumId, isNull);
          await pumpUntil(
            tester,
            () =>
                tester
                    .widget<Text>(find.byKey(const Key('now-playing-artists')))
                    .data ==
                'Tyler, The Creator / Guest ${track.id}',
          );
          expect(
            tester
                .widget<Text>(find.byKey(const Key('now-playing-title')))
                .data,
            'Updated ${track.id}',
          );
          expect(
            (await TagLibTrackEditor('${dir.path}/unused').read(track.path))
                .fields['TITLE'],
            'Updated ${track.id}',
          );
          expect(identical(queue, engine.state.queue), isTrue);
          expect(engine.state.repeatMode, RepeatMode.one);
          expect(engine.state.playing, !paused);
          expect(engine.state.error, isNull);
        }
        // Clearing the final album tag from the album page returns to the
        // library; both tracks remain available through each credited artist.
        await tester.tap(find.text('Альбомы'));
        await pumpUntil(tester, () => !controller.loading);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Альбом'));
        await tester.pumpAndSettle();
        expect(find.byType(AlbumPage), findsOneWidget);
        final flacTrack = original.singleWhere(
          (track) => track.path == flac.path,
        );
        await tester.ensureVisible(
          find.byKey(Key('track-menu-${flacTrack.id}')),
        );
        await tester.tap(find.byKey(Key('track-menu-${flacTrack.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Редактировать метаданные'));
        await pumpUntil(
          tester,
          () => find.byKey(const Key('metadata-ALBUM')).evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.byKey(const Key('metadata-ALBUM')));
        await tester.enterText(find.byKey(const Key('metadata-ALBUM')), '');
        await tester.pump();
        await tester.tap(find.text('Сохранить'));
        await pumpUntil(
          tester,
          () =>
              find.byType(AlbumPage).evaluate().isEmpty && !controller.loading,
        );
        expect(controller.status.albumCount, 0);
        expect(controller.status.trackCount, 2);
        expect(identical(queue, engine.state.queue), isTrue);
        await tester.tap(find.text('Артисты'));
        await pumpUntil(tester, () => !controller.loading);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tyler, The Creator'));
        await pumpUntil(
          tester,
          () => find.text('Updated ${flacTrack.id}').evaluate().isNotEmpty,
        );
        expect(controller.query.view, LibraryView.artists);
        expect(
          find.descendant(
            of: find.byType(ArtistPage),
            matching: find.byType(LibraryTrackTile),
          ),
          findsNWidgets(2),
        );
        await tester.tap(find.text('Updated ${flacTrack.id}'));
        await pumpUntil(
          tester,
          () =>
              !identical(engine.state.queue, queue) &&
              engine.state.currentTrack?.uri == flac.uri &&
              engine.state.playing,
        );
        expect(
          engine.state.queue.map((track) => track.uri),
          unorderedEquals([mp3.uri, flac.uri]),
        );
        expect(engine.state.currentTrack!.artists, [
          'Tyler, The Creator',
          'Guest ${flacTrack.id}',
        ]);
        expect(engine.state.repeatMode, RepeatMode.one);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await dir.delete(recursive: true);
      }
    },
  );
}
