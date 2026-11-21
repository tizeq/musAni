import 'dart:io';

import 'package:crypto/crypto.dart';
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
import 'package:musani/ui/current_track_details.dart';
import 'package:musani/ui/musani_app.dart';
import 'package:musani/ui/playlist_page.dart';
import 'package:musani/ui/player_page.dart';

import '../test/design_system_test.dart' show MemorySettingsStore;
import '../test/support/audio_fixtures.dart';
import '../test/support/memory_repeat_mode_store.dart';
import 'library_test.dart' show pumpUntil;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native playlist row uses its exact occurrence in the queue', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final dir = await Directory.systemTemp.createTemp('musani-playlist-queue-');
    final music = Directory('${dir.path}/music');
    final a = await createAudioFixture(
      music,
      'flac',
      name: 'a',
      title: 'Entry A',
      durationSeconds: 8,
      withCover: false,
    );
    final b = await createAudioFixture(
      music,
      'flac',
      name: 'b',
      title: 'Entry B',
      durationSeconds: 8,
      withCover: false,
    );
    final repo = LibraryRepository('${dir.path}/catalog');
    await repo.scan(addRoot: music.path);
    final library = LibraryController(repo);
    final playlistRepo = PlaylistRepository(repo.directory);
    final tracks = (await repo.query(
      const LibraryQuery(view: LibraryView.tracks),
    )).tracks;
    final playlist = await playlistRepo.create('Повторяющиеся треки');
    await playlistRepo.add(playlist.id, playlist.revision, [
      for (final i in [0, 1, 0]) PlaylistTrackRef.fromLibrary(tracks[i]),
    ]);
    final entries = (await playlistRepo.detail(playlist.id)).entries;
    final engine = MediaKitEngine(
      Player(),
      repeatModeStore: MemoryRepeatModeStore(),
    );
    await engine.setVolume(0);
    await engine.setRepeatMode(RepeatMode.all);
    final settings = SettingsController(
      MemorySettingsStore(),
      initial: AppSettings(style: MusaniTheme.atmosphere, reduceMotion: true),
    );
    Finder indicator(int index) =>
        find.byKey(Key('playlist-current-track-${entries[index].id}'));
    try {
      await tester.pumpWidget(
        MusaniApp(engine: engine, library: library, settings: settings),
      );
      await pumpUntil(tester, () => library.initialized && !library.loading);
      await tester.tap(find.text('Плейлисты'));
      final playlistTile = find.byKey(Key('playlist-${playlist.id}'));
      await pumpUntil(tester, () => playlistTile.evaluate().isNotEmpty);
      await tester.tap(playlistTile);
      final last = find.byKey(ValueKey(entries.last.id));
      await pumpUntil(tester, () => last.evaluate().isNotEmpty);
      await tester.tap(
        find.descendant(of: last, matching: find.text('Entry A')),
      );
      await pumpUntil(
        tester,
        () =>
            engine.state.index == 2 &&
            engine.state.duration.inSeconds == 8 &&
            indicator(2).evaluate().isNotEmpty,
      );
      expect(engine.state.queue.map((track) => track.uri), [
        a.uri,
        b.uri,
        a.uri,
      ]);
      expect(engine.state.currentTrack!.playlistEntry, (
        playlist.id,
        entries.last.id,
      ));
      expect(indicator(0), findsNothing);

      await tester.tap(find.byTooltip('Предыдущий'));
      await pumpUntil(
        tester,
        () => engine.state.index == 1 && indicator(1).evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Следующий'));
      await pumpUntil(
        tester,
        () => engine.state.index == 2 && indicator(2).evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Следующий'));
      await pumpUntil(
        tester,
        () => engine.state.index == 0 && indicator(0).evaluate().isNotEmpty,
      );
      expect(indicator(2), findsNothing);

      await tester.tap(find.byTooltip('Пауза'));
      await pumpUntil(
        tester,
        () =>
            !engine.state.playing &&
            !tester.widget<TrackPlaybackIndicator>(indicator(0)).playing,
      );
      await tester.tap(find.byTooltip('Открыть очередь'));
      final queueActive = find.byKey(const Key('queue-current-track-0'));
      await pumpUntil(tester, () => queueActive.evaluate().isNotEmpty);
      expect(
        tester.widget<TrackPlaybackIndicator>(queueActive).playing,
        isFalse,
      );
      expect(find.byKey(const Key('queue-current-track-2')), findsNothing);
      expect(engine.state.repeatMode, RepeatMode.all);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      settings.dispose();
      await dir.delete(recursive: true);
    }
  });

  testWidgets(
    'native playlist CRUD, multi-add, ordering, playback, missing link recovery and restart',
    (tester) async {
      MediaKit.ensureInitialized();
      final dir = await Directory.systemTemp.createTemp(
        'musani-playlist-native-',
      );
      final music = Directory('${dir.path}/music');
      final a = await createAudioFixture(
        music,
        'mp3',
        name: 'a',
        title: 'Native A',
      );
      final b = await createAudioFixture(
        music,
        'flac',
        name: 'b',
        title: 'Native B',
      );
      final hashes = {
        for (final file in [a, b])
          file.path: sha256.convert(await file.readAsBytes()).toString(),
      };
      final library = LibraryRepository('${dir.path}/catalog');
      await library.scan(addRoot: music.path);
      final tracks = (await library.query(
        const LibraryQuery(view: LibraryView.tracks),
      )).tracks;
      final repo = PlaylistRepository(library.directory);
      final controller = LibraryController(library);
      final engine = MediaKitEngine(
        Player(),
        repeatModeStore: MemoryRepeatModeStore(),
      );
      await engine.setRepeatMode(RepeatMode.one);
      await engine.open([tracks.first.playable]);
      var previousQueue = engine.state.queue;
      final movedPath = '${dir.path}/moved.flac';
      Future<void> idle() async {
        await tester.pump();
        await pumpUntil(
          tester,
          () =>
              find.byType(LinearProgressIndicator).evaluate().isEmpty &&
              !controller.loading,
        );
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: PlayerPage(
              engine: engine,
              library: controller,
              playlistLinkPicker: () async => movedPath,
            ),
          ),
        );
        await pumpUntil(
          tester,
          () =>
              controller.initialized &&
              !controller.loading &&
              engine.state.playing,
        );
        await tester.tap(find.text('Плейлисты'));
        await idle();
        await tester.tap(find.text('Создать плейлист'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('playlist-name')), 'Empty');
        await tester.tap(find.text('Сохранить'));
        await pumpUntil(tester, () => find.text('Empty').evaluate().isNotEmpty);
        final empty = (await repo.list()).single;
        expect((await repo.detail(empty.id)).entries, isEmpty);
        await tester.tap(find.text('Треки'));
        await idle();
        await tester.tap(find.byKey(Key('track-menu-${tracks.first.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Добавить в плейлист'));
        final existing = find.byKey(Key('add-to-${empty.id}'));
        await pumpUntil(tester, () => existing.evaluate().isNotEmpty);
        await tester.tap(existing);
        await pumpUntil(
          tester,
          () => find
              .text('В плейлист «Empty» добавлено записей: 1')
              .evaluate()
              .isNotEmpty,
        );
        expect((await repo.detail(empty.id)).entries.single.track.path, a.path);
        tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
            .clearSnackBars();
        for (final track in tracks) {
          await tester.tap(find.byKey(Key('select-track-${track.id}')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Добавить в плейлист'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Новый плейлист'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('playlist-name')),
          'Evening',
        );
        await tester.tap(find.text('Сохранить'));
        await pumpUntil(
          tester,
          () => find.text('Новый плейлист').evaluate().isEmpty,
        );
        await pumpUntil(
          tester,
          () => find
              .text('В плейлист «Evening» добавлено записей: 2')
              .evaluate()
              .isNotEmpty,
        );
        final playlist = (await repo.list()).singleWhere(
          (item) => item.name == 'Evening',
        );
        var detail = await repo.detail(playlist.id);
        expect(detail.entries.map((entry) => entry.track.title), [
          'Native A',
          'Native B',
        ]);
        expect(identical(previousQueue, engine.state.queue), isTrue);
        await tester.tap(find.text('Плейлисты'));
        await idle();
        await tester.tap(find.text('Evening'));
        await idle();
        expect(find.byType(PlaylistPage), findsOneWidget);
        await tester.tap(
          find.byKey(Key('playlist-entry-menu-${detail.entries.first.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Переместить ниже'));
        await idle();
        detail = await repo.detail(playlist.id);
        expect(detail.entries.map((entry) => entry.track.title), [
          'Native B',
          'Native A',
        ]);
        expect(identical(previousQueue, engine.state.queue), isTrue);
        await tester.tap(find.text('Воспроизвести плейлист'));
        await pumpUntil(
          tester,
          () => engine.state.queue.length == 2 && engine.state.playing,
        );
        expect(engine.state.queue.map((track) => track.name), [
          'Native B',
          'Native A',
        ]);
        expect(engine.state.repeatMode, RepeatMode.one);
        previousQueue = engine.state.queue;
        await tester.tap(find.byTooltip('Действия плейлиста'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Переименовать'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('playlist-name')), 'Road');
        await tester.tap(find.text('Сохранить'));
        await idle();
        await tester.tap(
          find.byKey(Key('playlist-entry-menu-${detail.entries.last.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Удалить из плейлиста'));
        await idle();
        expect(identical(previousQueue, engine.state.queue), isTrue);
        expect(await a.exists(), isTrue);
        await b.rename(movedPath);
        await controller.refresh();
        await pumpUntil(
          tester,
          () => find
              .textContaining('Недоступных файлов: 1')
              .evaluate()
              .isNotEmpty,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Воспроизвести плейлист'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byTooltip('Восстановить ссылку'));
        await idle();
        detail = await repo.detail(playlist.id);
        expect(detail.entries.single.available, isTrue);
        expect(detail.entries.single.track.path, movedPath);
        expect(identical(previousQueue, engine.state.queue), isTrue);
        expect(
          sha256.convert(await File(movedPath).readAsBytes()).toString(),
          hashes[b.path],
        );
        final reopened = await PlaylistRepository(library.directory)
            .detail(playlist.id);
        expect(reopened.playlist.name, 'Road');
        expect(reopened.entries.single.id, detail.entries.single.id);
        await tester.tap(find.text('Воспроизвести плейлист'));
        await pumpUntil(
          tester,
          () =>
              engine.state.queue.length == 1 &&
              engine.state.queue.single.uri.toFilePath() == movedPath &&
              engine.state.playing,
        );
        expect(engine.state.repeatMode, RepeatMode.one);
        previousQueue = engine.state.queue;
        await tester.tap(find.byTooltip('Действия плейлиста'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Удалить плейлист'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Отмена'));
        await tester.pumpAndSettle();
        expect(
          (await repo.list()).map((item) => item.id),
          unorderedEquals([empty.id, playlist.id]),
        );
        await tester.tap(find.byTooltip('Действия плейлиста'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Удалить плейлист'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Удалить'));
        await pumpUntil(
          tester,
          () => find.byType(PlaylistPage).evaluate().isEmpty,
        );
        expect((await repo.list()).single.id, empty.id);
        expect(identical(previousQueue, engine.state.queue), isTrue);
        expect(
          sha256.convert(await a.readAsBytes()).toString(),
          hashes[a.path],
        );
        expect(await File(movedPath).exists(), isTrue);
        expect(engine.state.error, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await dir.delete(recursive: true);
      }
    },
  );
}
