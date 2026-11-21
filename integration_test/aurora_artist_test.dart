import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:media_kit/media_kit.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/library/models.dart';
import 'package:musani/playback/media_kit_engine.dart';
import 'package:musani/playback/playback_engine.dart';
import 'package:musani/playlists/models.dart';
import 'package:musani/playlists/playlist_repository.dart';
import 'package:musani/settings/settings_controller.dart';
import 'package:musani/ui/album_page.dart';
import 'package:musani/ui/artist_page.dart';
import 'package:musani/ui/current_track_details.dart';
import 'package:musani/ui/metadata_editor_dialog.dart';
import 'package:musani/ui/musani_app.dart';
import 'package:musani/ui/playlist_page.dart';

import '../test/design_system_test.dart' show MemorySettingsStore;
import '../test/support/audio_fixtures.dart';
import '../test/support/memory_repeat_mode_store.dart';
import 'library_test.dart' show pumpUntil;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Aurora artist uses SQLite tracks, native playback and tag editing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 790));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      MediaKit.ensureInitialized();
      final directory = await Directory.systemTemp.createTemp('musani-aurora-');
      final music = Directory('${directory.path}/music');
      const artist = 'Северный свет';
      final first = await createAudioFixture(
        music,
        'flac',
        name: 'a',
        title: 'Восход',
        artist: artist,
      );
      final second = await createAudioFixture(
        music,
        'flac',
        name: 'b',
        title: 'Зенит',
        artist: artist,
        track: 2,
        withCover: false,
      );
      await createAudioFixture(music, 'flac', name: 'c', title: 'Чужой трек');
      final repo = LibraryRepository('${directory.path}/catalog');
      await repo.scan(addRoot: music.path);
      final track = (await repo.query(
        const LibraryQuery(view: LibraryView.tracks),
      )).tracks.singleWhere((track) => track.path == first.path);
      final playlists = PlaylistRepository(repo.directory);
      final playlist = await playlists.create('Избранное');
      await playlists.add(playlist.id, playlist.revision, [
        PlaylistTrackRef.fromLibrary(track),
      ]);
      final library = LibraryController(repo);
      final engine = MediaKitEngine(
        Player(),
        repeatModeStore: MemoryRepeatModeStore(),
      );
      final settings = SettingsController(
        MemorySettingsStore(),
        initial: AppSettings(
          style: MusaniTheme.atmosphere,
          colors: ColorMode.dark,
        ),
      );
      final page = find.byType(ArtistPage);
      final search = find.byKey(const Key('artist-search'));
      final play = find.byKey(const Key('artist-play-all'));
      final activeTrack = find.byKey(Key('artist-current-track-${track.id}'));
      final nowPlaying = find.byKey(const Key('now-playing-title'));
      String? dockTitle() => tester.widget<Text>(nowPlaying).data;
      Finder artistText(String text) =>
          find.descendant(of: page, matching: find.text(text));

      try {
        await engine.setVolume(0);
        await engine.setRepeatMode(RepeatMode.one);
        await tester.pumpWidget(
          MusaniApp(engine: engine, library: library, settings: settings),
        );
        await pumpUntil(tester, () => library.initialized && !library.loading);
        await tester.tap(find.text('Артисты'));
        final artistRow = find.widgetWithText(ListTile, artist);
        await pumpUntil(tester, () => artistRow.evaluate().isNotEmpty);
        await tester.tap(artistRow);
        await pumpUntil(
          tester,
          () => artistText('Восход').evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('artist-aurora-cover')), findsOneWidget);

        await tester.enterText(search, 'Восход');
        await pumpUntil(tester, () => artistText('Зенит').evaluate().isEmpty);
        await tester.tap(play);
        await pumpUntil(
          tester,
          () => engine.state.playing && activeTrack.evaluate().isNotEmpty,
        );
        expect(engine.state.queue.map((entry) => entry.uri), [
          first.uri,
          second.uri,
        ]);
        expect(engine.state.repeatMode, RepeatMode.one);
        expect(dockTitle(), 'Восход');
        expect(
          tester.widget<TrackPlaybackIndicator>(activeTrack).playing,
          isTrue,
        );
        expect(find.byKey(const Key('now-playing-artists')), findsOneWidget);

        final artistBounds = tester.getRect(page);
        await tester.tap(find.byTooltip('Открыть очередь'));
        await tester.pumpAndSettle();
        expect(page, findsOneWidget);
        expect(tester.getRect(page), artistBounds);
        expect(find.text('Зенит'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await pumpUntil(tester, () => !engine.state.playing);
        expect(
          tester.widget<TrackPlaybackIndicator>(activeTrack).playing,
          isFalse,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('aurora-collection')), findsNothing);
        expect(page, findsOneWidget);
        expect(tester.widget<TextField>(search).controller!.text, 'Восход');
        expect(activeTrack, findsOneWidget);

        final drawer = find.byKey(const Key('aurora-collection'));
        await tester.tap(find.byTooltip('Коллекция и очередь'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('collection-mode-collection')));
        final preview = find.descendant(
          of: drawer,
          matching: find.text('Альбом'),
        );
        await pumpUntil(tester, () => preview.evaluate().isNotEmpty);
        await tester.tap(preview);
        await tester.pumpAndSettle();
        expect(drawer, findsNothing);
        expect(find.byType(AlbumPage), findsOneWidget);
        await tester.tap(find.byTooltip(artist));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(search).controller!.text, 'Восход');

        await tester.tap(find.byKey(Key('track-menu-${track.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Редактировать метаданные'));
        final title = find.byKey(const Key('metadata-TITLE'));
        await pumpUntil(tester, () => title.evaluate().isNotEmpty);
        await tester.pumpAndSettle();
        await tester.enterText(title, 'Восход над морем');
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Сохранить'),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.text('Сохранить'));
        await pumpUntil(
          tester,
          () =>
              find.byType(MetadataEditorDialog).evaluate().isEmpty &&
              dockTitle() == 'Восход над морем' &&
              artistText('Восход над морем').evaluate().isNotEmpty,
        );
        expect(
          (await repo.track(track.id))?.metadata.title,
          'Восход над морем',
        );
        expect(engine.state.queue.map((entry) => entry.uri), [
          first.uri,
          second.uri,
        ]);
        expect(engine.state.repeatMode, RepeatMode.one);

        await settings.update(
          settings.value.copyWith(colors: ColorMode.light, reduceMotion: true),
        );
        await tester.pumpAndSettle();
        expect(activeTrack, findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.binding.setSurfaceSize(const Size(1586, 992));
        await tester.pumpAndSettle();
        final window = find.byKey(const Key('aurora-window'));
        final header = find.byKey(const Key('aurora-window-header'));
        final navigation = find.byKey(const Key('library-navigation'));
        final collection = find.byKey(const Key('aurora-collection'));
        final dock = find.byKey(const Key('playback-dock'));
        for (final control in [
          'Поиск',
          'Добавить папку',
          'Настройки',
          'Действия библиотеки',
        ]) {
          expect(find.byTooltip(control), findsOneWidget);
        }
        final collectionToggle = find.byTooltip('Коллекция и очередь');
        if (collection.evaluate().isEmpty) {
          await tester.tap(collectionToggle);
          await tester.pumpAndSettle();
        }
        expect(window, findsOneWidget);
        expect(header, findsOneWidget);
        expect(navigation, findsOneWidget);
        expect(collection, findsOneWidget);
        expect(page, findsOneWidget);
        expect(find.text('Ваша музыка'), findsNothing);
        expect(tester.getRect(page).bottom, lessThan(tester.getRect(dock).top));

        await tester.tap(
          find.descendant(of: navigation, matching: find.text('Плейлисты')),
        );
        final playlistTile = find.byKey(Key('playlist-${playlist.id}'));
        await pumpUntil(tester, () => playlistTile.evaluate().isNotEmpty);
        await tester.tap(playlistTile);
        final playPlaylist = find.text('Воспроизвести плейлист');
        await pumpUntil(tester, () => playPlaylist.evaluate().isNotEmpty);
        expect(find.byType(PlaylistPage), findsOneWidget);
        expect(header, findsOneWidget);
        expect(navigation, findsOneWidget);
        expect(collection, findsOneWidget);
        await tester.tap(playPlaylist);
        await pumpUntil(
          tester,
          () => engine.state.queue.length == 1 && engine.state.playing,
        );
        expect(engine.state.queue.single.uri, first.uri);

        await tester.tap(find.byTooltip(artist));
        await tester.pumpAndSettle();
        expect(page, findsOneWidget);
        expect(activeTrack, findsOneWidget);
        expect(find.byType(PlaylistPage), findsNothing);

        await settings.update(
          settings.value.copyWith(style: MusaniTheme.minimal),
        );
        await tester.pumpAndSettle();
        expect(page, findsOneWidget);
        expect(find.byKey(const Key('artist-aurora')), findsNothing);
        expect(play, findsNothing);
        expect(tester.widget<TextField>(search).controller!.text, 'Восход');
        expect(artistText('Восход над морем'), findsOneWidget);
        expect(dockTitle(), 'Восход над морем');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        settings.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}
