import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:media_kit/media_kit.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/library/models.dart';
import 'package:musani/playback/media_kit_engine.dart';
import 'package:musani/playback/playback_engine.dart';
import 'package:musani/settings/settings_controller.dart';
import 'package:musani/ui/album_artwork.dart';
import 'package:musani/ui/album_page.dart';
import 'package:musani/ui/current_track_details.dart';
import 'package:musani/ui/musani_app.dart';
import 'package:musani/ui/player_page.dart';

import '../test/design_system_test.dart' show MemorySettingsStore;
import '../test/support/audio_fixtures.dart';
import '../test/support/memory_repeat_mode_store.dart';

Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline))
      fail('Library integration state timed out');
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'filtered track list plays beyond its first page in display order',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      MediaKit.ensureInitialized();
      final directory = await Directory.systemTemp.createTemp(
        'musani-track-queue-',
      );
      final repo = LibraryRepository('${directory.path}/catalog');
      final music = Directory('${directory.path}/music');
      final files = {
        for (final letter in ['A', 'B', 'C', 'D', 'Other'])
          letter: await createAudioFixture(
            music,
            'flac',
            name: letter,
            title: letter == 'Other' ? letter : 'Focus $letter',
            album: 'Album $letter',
            withCover: false,
            durationSeconds: 5,
          ),
      };
      final filler = await createAudioFixture(
        music,
        'flac',
        name: 'filler',
        title: 'Focus 00',
        durationSeconds: 5,
        withCover: false,
      );
      for (var i = 1; i < 60; i++) {
        await filler.copy('${music.path}/filler-$i.flac');
      }
      await repo.scan(addRoot: music.path);
      final library = LibraryController(repo)
        ..query = const LibraryQuery(view: LibraryView.tracks);
      final engine = MediaKitEngine(
        Player(),
        repeatModeStore: MemoryRepeatModeStore(),
      );
      await engine.setVolume(0);
      final settings = SettingsController(
        MemorySettingsStore(),
        initial: AppSettings(style: MusaniTheme.atmosphere, reduceMotion: true),
      );
      Finder indicator(int id) => find.byKey(Key('library-current-track-$id'));
      try {
        await tester.pumpWidget(
          MusaniApp(engine: engine, library: library, settings: settings),
        );
        await pumpUntil(tester, () => library.initialized && !library.loading);
        await tester.enterText(
          find.byKey(const Key('library-search')),
          'Focus',
        );
        await pumpUntil(
          tester,
          () => library.query.search == 'Focus' && !library.loading,
        );
        await tester.tap(find.byTooltip('По убыванию'));
        await pumpUntil(
          tester,
          () => library.query.descending && !library.loading,
        );
        expect(
          library.result.tracks.take(3).map((track) => track.metadata.title),
          ['Focus D', 'Focus C', 'Focus B'],
        );
        final b = library.result.tracks[2];
        final c = library.result.tracks[1];
        expect(library.result.length, 60);
        await tester.tap(find.text('Focus B'));
        await pumpUntil(
          tester,
          () =>
              engine.state.index == 2 &&
              engine.state.duration.inSeconds == 5 &&
              engine.state.playing &&
              indicator(b.id).evaluate().isNotEmpty,
        );
        expect(engine.state.queue.take(4).map((track) => track.uri), [
          for (final letter in ['D', 'C', 'B', 'A']) files[letter]!.uri,
        ]);
        expect(engine.state.queue, hasLength(64));
        expect(
          tester.widget<TrackPlaybackIndicator>(indicator(b.id)).playing,
          isTrue,
        );

        await tester.tap(find.byTooltip('Предыдущий'));
        await pumpUntil(
          tester,
          () =>
              engine.state.index == 1 && indicator(c.id).evaluate().isNotEmpty,
        );
        expect(indicator(b.id), findsNothing);
        await tester.tap(find.byTooltip('Следующий'));
        await pumpUntil(
          tester,
          () =>
              engine.state.index == 2 && indicator(b.id).evaluate().isNotEmpty,
        );
        await tester.tap(find.byTooltip('Пауза'));
        await pumpUntil(
          tester,
          () =>
              !engine.state.playing &&
              !tester.widget<TrackPlaybackIndicator>(indicator(b.id)).playing,
        );

        await engine.seek(const Duration(milliseconds: 4600));
        await engine.toggle();
        await pumpUntil(
          tester,
          () => engine.state.index == 3 && engine.state.playing,
        );
        expect(engine.state.currentTrack!.uri, files['A']!.uri);
        expect(indicator(b.id), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        settings.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'scan -> album UI -> native playback -> incremental refresh -> cached restart',
    (tester) async {
      MediaKit.ensureInitialized();
      final directory = await Directory.systemTemp.createTemp(
        'musani-library-native-',
      );
      final music = Directory('${directory.path}/music');
      final first = await createAudioFixture(
        music,
        'mp3',
        name: '01',
        title: 'Первый трек',
        album: 'Север',
        track: 1,
      );
      final second = await createAudioFixture(
        music,
        'flac',
        name: '02',
        title: 'Второй трек',
        album: 'Север',
        track: 2,
      );
      await createAudioFixture(
        music,
        'm4a',
        name: '03',
        album: 'Ночная линия',
        albumArtist: 'Эхо',
      );
      await createAudioFixture(
        music,
        'ogg',
        name: '04',
        album: 'Тихие города',
        albumArtist: 'Орбита',
      );
      final repository = LibraryRepository('${directory.path}/catalog');
      final controller = LibraryController(repository);
      final engine = MediaKitEngine(
        Player(),
        repeatModeStore: MemoryRepeatModeStore(),
      );
      final repaint = GlobalKey();
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: repaint,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: Brightness.dark,
                scaffoldBackgroundColor: const Color(0xff11161c),
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff6bd8b9),
                  brightness: Brightness.dark,
                ),
              ),
              home: PlayerPage(
                engine: engine,
                library: controller,
                folderPicker: () async => music.path,
              ),
            ),
          ),
        );
        await pumpUntil(
          tester,
          () => controller.initialized && !controller.loading,
        );
        await tester.tap(find.text('Выбрать папку с музыкой'));
        await pumpUntil(
          tester,
          () =>
              controller.status.trackCount == 4 &&
              !controller.scanning &&
              !controller.loading,
        );
        expect(controller.status.albumCount, 3);
        expect(find.byType(AlbumArtwork), findsNWidgets(3));
        await tester.pumpAndSettle();
        const screenshots = String.fromEnvironment('MUSANI_SCREENSHOT_DIR');
        if (screenshots.isNotEmpty) {
          final image =
              await (repaint.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$screenshots/musani-library.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        await tester.tap(find.byKey(const Key('repeat-mode')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('repeat-mode')));
        await tester.pumpAndSettle();
        expect(engine.state.repeatMode, RepeatMode.one);
        await tester.ensureVisible(find.text('Север'));
        await tester.tap(find.text('Север'));
        await pumpUntil(
          tester,
          () => find.text('Воспроизвести альбом').evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Воспроизвести альбом'));
        await tester.tap(find.text('Воспроизвести альбом'));
        await pumpUntil(
          tester,
          () => engine.state.queue.length == 2 && engine.state.playing,
        );
        expect(engine.state.index, 0);
        await tester.pumpAndSettle();
        expect(find.byType(AlbumPage), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Второй трек'),
          100,
          scrollable: find
              .descendant(
                of: find.byType(AlbumPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('Второй трек'));
        await pumpUntil(
          tester,
          () =>
              engine.state.index == 1 &&
              engine.state.playing &&
              engine.state.position.inMilliseconds > 50,
        );
        expect(engine.state.queue.map((track) => track.name), [
          'Первый трек',
          'Второй трек',
        ]);
        expect(engine.state.repeatMode, RepeatMode.one);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await createAudioFixture(
          music,
          'ogg',
          name: '05',
          title: 'Новый трек',
          album: 'Север',
          track: 3,
        );
        await first.delete();
        await tester.tap(find.byTooltip('Обновить библиотеку'));
        await pumpUntil(
          tester,
          () =>
              !controller.scanning &&
              !controller.loading &&
              controller.lastReport?.removed == 1,
        );
        expect(controller.lastReport!.updated, 1);
        expect(engine.state.queue, hasLength(2));
        expect(engine.state.index, 1);
        expect(engine.state.repeatMode, RepeatMode.one);
        expect(engine.state.error, isNull);
        final reopened = LibraryRepository(repository.directory);
        expect((await reopened.status()).trackCount, 4);
        final albums = (await reopened.query(const LibraryQuery())).albums;
        expect(
          albums.singleWhere((album) => album.title == 'Север').trackCount,
          2,
        );
        expect(await second.exists(), isTrue);
        expect(find.byType(AlbumPage), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await directory.delete(recursive: true);
      }
    },
  );
}
