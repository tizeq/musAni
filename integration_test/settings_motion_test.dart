import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/library/models.dart';
import 'package:musani/playback/media_kit_engine.dart';
import 'package:musani/playlists/models.dart';
import 'package:musani/playlists/playlist_repository.dart';
import 'package:musani/settings/settings_controller.dart';
import 'package:musani/ui/album_page.dart';
import 'package:musani/ui/metadata_editor_dialog.dart';
import 'package:musani/ui/musani_app.dart';
import 'package:musani/ui/playlist_page.dart';

import '../test/design_system_test.dart' show MemorySettingsStore;
import '../test/support/audio_fixtures.dart';
import '../test/support/memory_repeat_mode_store.dart';
import 'library_test.dart' show pumpUntil;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'reduced motion reaches library, album, queue, playlists and tag editor',
    (tester) async {
      await binding.setSurfaceSize(const Size(1200, 860));
      addTearDown(() => binding.setSurfaceSize(null));
      MediaKit.ensureInitialized();
      final dir = await Directory.systemTemp.createTemp('musani-motion-');
      final music = Directory('${dir.path}/music');
      await createAudioFixture(
        music,
        'mp3',
        title: 'Test track',
        album: 'Test album',
      );
      final repository = LibraryRepository('${dir.path}/catalog');
      await repository.scan(addRoot: music.path);
      final track = (await repository.query(
        const LibraryQuery(view: LibraryView.tracks),
      )).tracks.single;
      final playlists = PlaylistRepository(repository.directory);
      final playlist = await playlists.create('Test playlist');
      await playlists.add(playlist.id, playlist.revision, [
        PlaylistTrackRef.fromLibrary(track),
      ]);
      final entry = (await playlists.detail(playlist.id)).entries.single;
      final initial = AppSettings(reduceMotion: true);
      final settings = SettingsController(
        MemorySettingsStore(initial),
        initial: initial,
      );
      final library = LibraryController(repository);
      final engine = MediaKitEngine(
        Player(),
        repeatModeStore: MemoryRepeatModeStore(),
      );
      await engine.setVolume(0);
      await engine.open([track.playable]);
      try {
        await tester.pumpWidget(
          MusaniApp(engine: engine, library: library, settings: settings),
        );
        await pumpUntil(tester, () => library.initialized && !library.loading);
        await tester.pumpAndSettle();

        void check(Finder place) {
          final route = ModalRoute.of(tester.element(place))!;
          expect(route.transitionDuration, Duration.zero);
          expect(route.reverseTransitionDuration, Duration.zero);
        }

        Future<void> tap(Finder target) async {
          await tester.tap(target);
          await tester.pump();
        }

        await tap(find.byTooltip('Папки библиотеки'));
        check(find.byType(AlertDialog));
        await tap(find.text('Закрыть'));

        final catalogRoute = ModalRoute.of(
          tester.element(find.byKey(const Key('library-search'))),
        );
        await tap(find.text('Test album'));
        await pumpUntil(
          tester,
          () => find.byKey(Key('track-menu-${track.id}')).evaluate().isNotEmpty,
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AlbumPage))),
          same(catalogRoute),
        );
        await tap(find.byKey(Key('track-menu-${track.id}')));
        final edit = find.widgetWithText(
          PopupMenuItem<String>,
          'Редактировать метаданные',
        );
        check(edit);
        await tap(edit);
        check(find.byType(MetadataEditorDialog));
        await pumpUntil(
          tester,
          () => find.byType(TextFormField).evaluate().isNotEmpty,
        );
        await tap(find.text('Отмена'));
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tap(find.byTooltip('Очередь воспроизведения'));
        await tap(find.byTooltip('Действия трека очереди'));
        final add = find.widgetWithText(
          PopupMenuItem<String>,
          'Добавить в плейлист',
        );
        check(add);
        await tap(add);
        check(find.byType(AlertDialog));
        await pumpUntil(
          tester,
          () => find.text('Test playlist').evaluate().isNotEmpty,
        );
        await tap(find.text('Отмена'));
        await tap(find.byTooltip('Библиотека'));

        await tap(find.text('Плейлисты'));
        await pumpUntil(
          tester,
          () => find.text('Test playlist').evaluate().isNotEmpty,
        );
        await tap(find.text('Test playlist'));
        await pumpUntil(
          tester,
          () => find
              .byKey(Key('playlist-entry-menu-${entry.id}'))
              .evaluate()
              .isNotEmpty,
        );
        check(find.byType(PlaylistPage));
        expect(
          tester
              .widget<ReorderableListView>(find.byType(ReorderableListView))
              .proxyDecorator,
          isNotNull,
        );
        await tap(find.byKey(Key('playlist-entry-menu-${entry.id}')));
        check(edit);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await dir.delete(recursive: true);
      }
    },
  );
}
