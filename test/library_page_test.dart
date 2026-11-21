import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:media_kit/media_kit.dart';
import 'package:musani/files/local_tracks.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/models.dart';
import 'package:musani/settings/settings_controller.dart';
import 'package:musani/ui/artist_page.dart';
import 'package:musani/playback/media_kit_engine.dart';
import 'package:musani/playback/playback_engine.dart';
import 'package:musani/ui/library_page.dart';
import 'package:musani/ui/library_navigation.dart';
import 'package:musani/ui/album_page.dart';
import 'package:musani/ui/player_page.dart';
import 'package:musani/ui/playlist_page.dart';

import 'design_system_test.dart' show MemorySettingsStore;
import 'support/library_fakes.dart';
import 'support/memory_repeat_mode_store.dart';
import 'support/playlist_fakes.dart';
import 'support/recording_platform_player.dart';

class _SlowArtistRepository extends FakeLibraryRepository {
  _SlowArtistRepository(super.tracks);
  final gate = Completer<void>();

  @override
  Future<LibraryResult> query(LibraryQuery query) async {
    if (query.view == LibraryView.artists) await gate.future;
    return super.query(query);
  }
}

void main() {
  late Directory directory;
  late FakeLibraryRepository repository;
  late LibraryController controller;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('musani-widget-');
    for (var i = 0; i < 2; i++) {
      await File('${directory.path}/$i.mp3').writeAsBytes([0]);
    }
    repository = FakeLibraryRepository(sampleLibraryTracks(directory.path));
    controller = LibraryController(repository);
  });
  tearDown(() => directory.delete(recursive: true));

  Future<void> browser(
    WidgetTester tester, {
    FolderPicker? picker,
    bool reduceMotion = false,
    SettingsController? settings,
    MemoryPlaylistRepository? playlists,
  }) async {
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: LibraryPage(
            controller: controller,
            onPlay: (_, _) async {},
            onPlayQuery: (_, {startPath}) async {},
            folderPicker: picker ?? () async => null,
            playlists: playlists ?? MemoryPlaylistRepository(),
            onPlayPlaylist: (_, _) async {},
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'dragging the sidebar changes its order and keeps the active section',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemorySettingsStore();
      final settings = SettingsController(store);
      await browser(tester, settings: settings);
      final albums = find.byKey(const Key('library-drag-albums'));
      final playlists = find.byKey(const Key('library-drag-playlists'));
      expect(
        tester.getTopLeft(albums).dy,
        lessThan(tester.getTopLeft(playlists).dy),
      );
      await tester.timedDrag(
        albums,
        const Offset(0, 164),
        const Duration(milliseconds: 350),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(albums).dy,
        greaterThan(tester.getTopLeft(playlists).dy),
      );
      expect(controller.query.view, LibraryView.albums);
      expect(
        tester
            .widget<LibraryNavigation>(find.byType(LibraryNavigation))
            .selected,
        0,
      );
      await tester.pumpWidget(const SizedBox());
      settings.dispose();

      final restored = SettingsController(store);
      await restored.restore();
      await tester.binding.setSurfaceSize(const Size(600, 720));
      await browser(tester, settings: restored);
      expect(
        tester.widget<LibraryNavigation>(find.byType(LibraryNavigation)).order,
        [
          LibrarySection.artists,
          LibrarySection.tracks,
          LibrarySection.playlists,
          LibrarySection.albums,
        ],
      );
      expect(
        tester.getTopLeft(find.text('Артисты')).dx,
        lessThan(tester.getTopLeft(find.text('Альбомы')).dx),
      );
      await tester.pumpWidget(const SizedBox());
      restored.dispose();
      controller.dispose();
    },
  );

  testWidgets('artist and album tabs keep state and reuse the same pages', (
    tester,
  ) async {
    final sample = repository.tracks.first;
    repository.tracks.addAll([
      for (var id = 3; id < 40; id++)
        LibraryTrack(
          id: id,
          path: '/tmp/$id.mp3',
          albumId: sample.albumId,
          metadata: sample.metadata,
          size: sample.size,
          modifiedUs: sample.modifiedUs,
          changedUs: sample.changedUs,
        ),
    ]);
    await browser(tester);
    final nav = find.byType(LibraryNavigation);
    final catalog = find.byKey(const Key('workspace-library'));
    final artistRow = find.widgetWithText(ListTile, 'Исполнитель');
    final artistTab = find.byKey(const Key('tab-artist-artist'));
    final albumTab = find.byKey(const Key('tab-album-album'));
    final artistSearch = find.byKey(const Key('artist-search'));
    final librarySearch = find.byKey(const Key('library-search'));
    final artistPage = find.byType(ArtistPage);
    final albumPage = find.byType(AlbumPage);
    ScrollPosition scrollPosition(Finder list) => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;
    Future<void> tap(Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> search(Finder finder, String text) async {
      await tester.enterText(finder, text);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    await tap(find.descendant(of: nav, matching: find.text('Артисты')));
    await search(librarySearch, 'Поиск в каталоге');
    await tap(artistRow);
    final artistState = tester.state(artistPage);
    expect(controller.query.view, LibraryView.artists);
    expect(controller.query.search, 'Поиск в каталоге');
    await search(artistSearch, 'Поиск во вкладке');
    final artistList = find.descendant(
      of: artistPage,
      matching: find.byType(ListView),
    );
    await tester.drag(artistList, const Offset(0, -280));
    await tester.pumpAndSettle();
    final artistOffset = scrollPosition(artistList).pixels;
    expect(artistOffset, greaterThan(0));

    await tap(catalog);
    expect(
      tester.widget<TextField>(librarySearch).controller!.text,
      'Поиск в каталоге',
    );
    await tap(artistRow);
    expect(artistTab, findsOneWidget);
    expect(tester.state(artistPage), same(artistState));
    expect(
      tester.widget<TextField>(artistSearch).controller!.text,
      'Поиск во вкладке',
    );
    expect(scrollPosition(artistList).pixels, artistOffset);
    await tap(find.descendant(of: artistPage, matching: find.text('Альбомы')));
    await tap(find.widgetWithText(ListTile, 'Север'));
    final albumState = tester.state(albumPage);
    final albumList = find.byType(CustomScrollView);
    await tester.drag(albumList, const Offset(0, -360));
    await tester.pumpAndSettle();
    final albumOffset = scrollPosition(albumList).pixels;
    expect(albumOffset, greaterThan(0));

    await tap(artistTab);
    await tap(find.widgetWithText(ListTile, 'Север'));
    expect(albumTab, findsOneWidget);
    expect(tester.state(albumPage), same(albumState));
    expect(scrollPosition(albumList).pixels, albumOffset);
    expect(repository.albumReads, 1);
    await tap(find.byKey(const Key('close-artist-artist')));
    expect(tester.state(albumPage), same(albumState));
    await tap(find.byKey(const Key('close-album-album')));
    expect(albumPage, findsNothing);
    expect(catalog, findsNothing);
    expect(
      tester.widget<TextField>(librarySearch).controller!.text,
      'Поиск в каталоге',
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  for (final reduced in [false, true]) {
    testWidgets('playlist route has its own transition (reduced: $reduced)', (
      tester,
    ) async {
      final playlists = MemoryPlaylistRepository();
      await playlists.create('Список');
      await browser(tester, reduceMotion: reduced, playlists: playlists);
      await tester.tap(
        find.descendant(
          of: find.byType(LibraryNavigation),
          matching: find.text('Плейлисты'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Список'));
      await tester.pump();
      final page = find.byType(PlaylistPage);
      final route = ModalRoute.of(tester.element(page))!;
      expect(route.transitionDuration.inMilliseconds, reduced ? 0 : 120);
      expect(route.reverseTransitionDuration.inMilliseconds, reduced ? 0 : 90);
      final start = tester.getTopLeft(page);
      await tester.pumpAndSettle();
      final settled = tester.getTopLeft(page);
      expect(start.dy, settled.dy);
      expect(start.dx - settled.dx, reduced ? 0 : closeTo(12, 1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets(
    'tabs keep their search, list position and loaded results on return',
    (tester) async {
      final sample = repository.tracks.first;
      repository.tracks.addAll([
        for (var i = 3; i <= 50; i++)
          LibraryTrack(
            id: i,
            path: '${directory.path}/$i.mp3',
            albumId: sample.albumId,
            metadata: sample.metadata,
            size: sample.size,
            modifiedUs: sample.modifiedUs,
            changedUs: sample.changedUs,
          ),
      ]);
      await browser(tester);
      const search = Key('library-search');
      final nav = find.byType(LibraryNavigation);
      Future<void> select(String label) async {
        await tester.tap(find.descendant(of: nav, matching: find.text(label)));
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byKey(search), 'Запрос альбомов');
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      await select('Треки');
      expect(
        tester.widget<TextField>(find.byKey(search)).controller!.text,
        isEmpty,
      );
      await tester.enterText(find.byKey(search), 'Запрос треков');
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      final list = find.byType(ListView);
      await tester.drag(list, const Offset(0, -368));
      await tester.pumpAndSettle();
      double position() => tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          )
          .position
          .pixels;
      final offset = position();
      expect(offset, greaterThan(300));
      final calls = repository.queries.length;
      final navPosition = tester.getTopLeft(nav);
      await select('Плейлисты');
      expect(tester.getTopLeft(nav), navPosition);
      expect(find.byKey(search), findsNothing);
      await select('Альбомы');
      expect(
        tester.widget<TextField>(find.byKey(search)).controller!.text,
        'Запрос альбомов',
      );
      await select('Треки');
      expect(
        tester.widget<TextField>(find.byKey(search)).controller!.text,
        'Запрос треков',
      );
      expect(position(), closeTo(offset, 1));
      expect(repository.queries.length, calls);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'selection updates before a slow query completes (reduce motion: $reduced)',
      (tester) async {
        final pending = _SlowArtistRepository(repository.tracks);
        controller.dispose();
        controller = LibraryController(pending);
        await browser(tester, reduceMotion: reduced);
        final nav = find.byType(LibraryNavigation);
        final destination = find.descendant(
          of: nav,
          matching: find.text('Артисты'),
        );
        final button = find
            .ancestor(of: destination, matching: find.byType(InkWell))
            .first;
        final overlay = tester.widget<InkWell>(button).overlayColor!;
        final hover = overlay.resolve({WidgetState.hovered});
        final pressed = overlay.resolve({
          WidgetState.hovered,
          WidgetState.pressed,
        });
        expect(hover, isNot(Colors.transparent));
        expect(pressed, isNot(hover));

        await tester.tap(destination);
        await tester.pump();
        expect(controller.loading, isTrue);
        expect(
          tester.widget<LibraryNavigation>(nav).selected,
          LibraryView.artists.index,
        );
        final selected = tester.widget<Material>(
          find.ancestor(of: destination, matching: find.byType(Material)).first,
        );
        expect(selected.animationDuration, Duration.zero);
        expect(selected.color, isNot(Colors.transparent));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        double panelOffset() => tester
            .widget<Transform>(find.byKey(const Key('library-tab-content')))
            .transform
            .getTranslation()
            .y;
        expect(panelOffset(), reduced ? 0.0 : greaterThan(0));
        await tester.pump(const Duration(milliseconds: 120));
        expect(panelOffset(), 0);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.pump(const Duration(milliseconds: 35));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.tap(
          find.descendant(of: nav, matching: find.text('Альбомы')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Север'), findsOneWidget);
        pending.gate.complete();
        await tester.pumpAndSettle();
        expect(
          tester.widget<LibraryNavigation>(nav).selected,
          LibraryView.albums.index,
        );
        expect(find.text('Исполнитель'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  testWidgets(
    'an open album refreshes track artists after an edit from another view',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AlbumPage(
            album: repository.album,
            controller: controller,
            onPlay: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final old = repository.tracks.first;
      repository.tracks[0] = LibraryTrack(
        id: old.id,
        path: old.path,
        albumId: old.albumId,
        size: old.size,
        modifiedUs: old.modifiedUs,
        changedUs: old.changedUs,
        metadata: const TrackMetadata(
          title: 'Edited elsewhere',
          artists: ['Tyler, The Creator', 'Guest'],
          album: 'Север',
          albumArtist: 'Группа',
        ),
      );
      await controller.metadataChanged(old.path);
      await tester.pumpAndSettle();
      expect(find.text('Edited elsewhere'), findsOneWidget);
      expect(find.text('Tyler, The Creator / Guest · Север'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'album grid, search, artist filter and sorting call catalog queries',
    (tester) async {
      await browser(tester);
      expect(find.text('Север'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('library-search')),
        'не найдено',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Ничего не найдено'), findsOneWidget);
      expect(repository.queries.last.search, 'не найдено');
      await tester.enterText(find.byKey(const Key('library-search')), '');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Артисты'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Исполнитель'));
      await tester.pumpAndSettle();
      expect(repository.queries.last.artistId, 'artist');
      expect(repository.queries.last.view, LibraryView.tracks);
      expect(controller.query.view, LibraryView.artists);
      await tester.tap(find.byTooltip('Сортировка'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<LibrarySort> &&
              widget.value == LibrarySort.year,
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.queries.last.sort, LibrarySort.year);
      await tester.tap(find.byTooltip('По убыванию'));
      await tester.pumpAndSettle();
      expect(repository.queries.last.descending, isTrue);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'folder picker scans in background, shows progress and refreshes',
    (tester) async {
      repository.empty = true;
      repository.scanGate = Completer<void>();
      await browser(tester, picker: () async => '/music');
      await tester.tap(find.text('Выбрать папку с музыкой'));
      await tester.pump();
      expect(find.textContaining('Сканирование · 10 файлов'), findsOneWidget);
      expect(controller.scanning, isTrue);
      expect(repository.addedRoot, '/music');
      repository.scanGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Север'), findsOneWidget);
      await tester.tap(find.byTooltip('Обновить библиотеку'));
      await tester.pumpAndSettle();
      expect(repository.scans, 2);
      expect(repository.addedRoot, isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'untagged tracks use the displayed track query without an artificial album queue',
    (tester) async {
      final old = repository.tracks.first;
      final standalone = LibraryTrack(
        id: old.id,
        path: old.path,
        albumId: null,
        metadata: const TrackMetadata(
          title: 'Standalone',
          artists: ['Tyler, The Creator', 'Guest'],
          album: '',
          albumArtist: '',
          albumTagged: false,
        ),
        size: old.size,
        modifiedUs: old.modifiedUs,
        changedUs: old.changedUs,
      );
      repository.tracks[0] = standalone;
      controller.query = const LibraryQuery(view: LibraryView.tracks);
      await controller.load();
      LibraryQuery? played;
      String? path;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryPage(
              controller: controller,
              onPlay: (_, _) async => fail('Expected the catalog context'),
              onPlayQuery: (query, {startPath}) async {
                played = query;
                path = startPath;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standalone'));
      await tester.pumpAndSettle();
      expect(played?.view, LibraryView.tracks);
      expect(path, standalone.path);
      expect(repository.albumReads, 0);
      expect(find.text('Tyler, The Creator / Guest'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('cancelled folder dialog does not scan', (tester) async {
    repository.empty = true;
    await browser(tester);
    await tester.tap(find.text('Выбрать папку с музыкой'));
    await tester.pumpAndSettle();
    expect(repository.scans, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('library and album adapt at width $width', (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await browser(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Север'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Север'));
      await tester.pumpAndSettle();
      expect(find.byType(AlbumPage), findsOneWidget);
      expect(find.text('Воспроизвести альбом'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  for (final mode in RepeatMode.values) {
    testWidgets(
      'album playback starts selected track and retains $mode and navigation',
      (tester) async {
        final backend = RecordingPlatformPlayer();
        final engine = MediaKitEngine(
          Player(platformPlayer: backend),
          repeatModeStore: MemoryRepeatModeStore(mode),
        );
        await engine.restoreRepeatMode();
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerPage(engine: engine, library: controller),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Север'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Север'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Воспроизвести альбом'));
        await tester.pumpAndSettle();
        await tapForPlayback(
          tester,
          find.text('Воспроизвести альбом'),
          engine,
          0,
        );
        expect(engine.state.index, 0);
        expect(engine.state.queue, hasLength(2));
        final a = find.byKey(
          Key('library-current-track-${repository.tracks.first.id}'),
        );
        final b = find.byKey(
          Key('library-current-track-${repository.tracks.last.id}'),
        );
        expect(a, findsOneWidget);
        expect(b, findsNothing);
        await tester.ensureVisible(find.text('Второй трек'));
        await tester.pumpAndSettle();
        await tapForPlayback(tester, find.text('Второй трек'), engine, 1);
        expect(engine.state.index, 1);
        expect(a, findsNothing);
        expect(b, findsOneWidget);
        expect(engine.state.queue.map((track) => track.name), [
          'Первый трек',
          'Второй трек',
        ]);
        expect(engine.state.repeatMode, mode);
        await tester.tap(find.byTooltip('Очередь воспроизведения'));
        await tester.pumpAndSettle();
        expect(find.byType(AlbumPage), findsNothing);
        await tester.tap(find.byTooltip('Библиотека'));
        await tester.pumpAndSettle();
        expect(find.byType(AlbumPage), findsOneWidget);
        expect(engine.state.repeatMode, mode);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('album page survives a busy frame followed by a new queue', (
    tester,
  ) async {
    final gate = Completer<void>();
    final backend = RecordingPlatformPlayer()..openGate = gate;
    final engine = MediaKitEngine(
      Player(platformPlayer: backend),
      repeatModeStore: MemoryRepeatModeStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(engine: engine, library: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Север'));
    await tester.tap(find.text('Север'));
    await tester.pumpAndSettle();
    late Future<void> pending;
    await tester.runAsync(() async {
      pending = tester
          .widget<LibraryPage>(find.byType(LibraryPage))
          .onPlay(repository.tracks, 0);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!backend.opening) {
        if (DateTime.now().isAfter(deadline))
          throw StateError('Open was not requested');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    gate.complete();
    await tester.runAsync(() => pending);
    await tester.pumpAndSettle();
    expect(engine.state.queue, hasLength(2));
    expect(find.byType(AlbumPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unavailable library files leave the existing queue untouched', (
    tester,
  ) async {
    final engine = MediaKitEngine(
      Player(platformPlayer: RecordingPlatformPlayer()),
      repeatModeStore: MemoryRepeatModeStore(),
    );
    await engine.open([LocalTrack(Uri.file('/tmp/old.mp3'), 'Старая очередь')]);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(engine: engine, library: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Север'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Север'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => File('${directory.path}/1.mp3').delete());
    await tester.ensureVisible(find.text('Воспроизвести альбом'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester
          .widget<LibraryPage>(find.byType(LibraryPage))
          .onPlay(repository.tracks, 0),
    );
    await tester.pumpAndSettle();
    expect(engine.state.queue.single.name, 'Старая очередь');
    expect(find.textContaining('Ошибка:'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> tapForPlayback(
  WidgetTester tester,
  Finder target,
  MediaKitEngine engine,
  int index,
) async {
  await tester.runAsync(() async {
    await tester.tap(target);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (engine.state.queue.length != 2 || engine.state.index != index) {
      if (DateTime.now().isAfter(deadline))
        throw StateError('Playback did not start');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });
  await tester.pumpAndSettle();
}
