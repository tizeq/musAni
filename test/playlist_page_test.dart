import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musani/files/local_tracks.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/models.dart';
import 'package:musani/playlists/models.dart';
import 'package:musani/ui/library_page.dart';
import 'package:musani/ui/library_workspace.dart';
import 'package:musani/ui/playlist_actions.dart';
import 'package:musani/ui/playlist_page.dart';
import 'package:musani/ui/metadata_editor_dialog.dart';

import 'support/library_fakes.dart';
import 'support/playlist_fakes.dart';

class _AlbumWriteRepository extends MemoryPlaylistRepository {
  int writes = 0;

  @override
  Future<AlbumWriteReport> writeAlbumTags(String id, int revision) async {
    writes++;
    return const AlbumWriteReport([
      AlbumWriteItem(
        '/tmp/a.mp3',
        AlbumWriteStatus.saved,
        backupPath: '/backups/a.mp3',
      ),
    ]);
  }
}

void main() {
  late MemoryPlaylistRepository repo;
  late LibraryController library;
  setUp(() {
    repo = MemoryPlaylistRepository();
    library = LibraryController(
      FakeLibraryRepository(sampleLibraryTracks('/tmp')),
    );
  });
  tearDown(() => library.dispose());
  Future<void> browser(WidgetTester tester) async {
    await library.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryPage(
            controller: library,
            playlists: repo,
            onPlay: (_, _) async {},
            onPlayQuery: (_, {startPath}) async {},
            onPlayPlaylist: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<UserPlaylist> populated() async {
    final playlist = await repo.create('Любимое');
    await repo.add(playlist.id, 0, [
      const PlaylistTrackRef(
        path: '/tmp/a.mp3',
        title: 'Song A',
        artists: ['Artist A'],
        durationMs: 60000,
      ),
      const PlaylistTrackRef(
        path: '/tmp/b.flac',
        title: 'Song B',
        artists: ['Artist B'],
        durationMs: 90000,
      ),
    ]);
    return (await repo.detail(playlist.id)).playlist;
  }

  Future<void> page(
    WidgetTester tester,
    String id, {
    PlaylistPlayback? play,
    PlaylistLinkPicker? picker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlaylistPage(
          id: id,
          repository: repo,
          onPlay: play,
          linkPicker: picker ?? () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('catalog album opens its editable playlist-backed tab', (
    tester,
  ) async {
    final base = await populated();
    final detail = await repo.detail(base.id);
    repo.items[base.id] = PlaylistDetail(
      UserPlaylist(
        id: base.id,
        name: 'Концерт',
        revision: base.revision,
        updatedMs: base.updatedMs,
        isAlbum: true,
        albumMetadata: const UserAlbumMetadata(artist: 'Ансамбль', year: 1998),
      ),
      [
        for (final entry in detail.entries)
          PlaylistEntry(
            id: entry.id,
            position: entry.position,
            track: entry.track,
            fileState: entry.fileState,
            albumDisc: 7,
            albumTrackNumber: entry.position + 1,
          ),
      ],
    );
    final key = GlobalKey<LibraryWorkspaceState>();
    final played = <LocalTrack>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryWorkspace(
          key: key,
          library: library,
          playlists: repo,
          onPlay: (_, _) async {},
          onPlayQuery: (_, {startPath}) async {},
          onPlayPlaylist: (tracks, _) async => played.addAll(tracks),
          child: const SizedBox(),
        ),
      ),
    );
    key.currentState!.openAlbum(
      LibraryAlbum(
        id: 'playlist:${base.id}',
        title: 'Концерт',
        artist: 'Ансамбль',
        year: 1998,
        trackCount: 2,
        durationMs: 150000,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistPage), findsOneWidget);
    expect(find.text('Ансамбль · 1998'), findsOneWidget);
    expect(find.textContaining('Диск 7'), findsNothing);
    expect(find.textContaining('№ '), findsNothing);
    await tester.tap(find.text('Воспроизвести альбом'));
    await tester.pumpAndSettle();
    expect(played.map((t) => t.name), ['Song A', 'Song B']);
    expect(played.every((t) => t.playlistEntry?.$1 == base.id), isTrue);
  });

  testWidgets('physical album export requires explicit confirmation', (
    tester,
  ) async {
    final albums = _AlbumWriteRepository();
    repo = albums;
    final playlist = await populated();
    final detail = await repo.detail(playlist.id);
    repo.items[playlist.id] = PlaylistDetail(
      UserPlaylist(
        id: playlist.id,
        name: 'Альбом',
        revision: playlist.revision,
        updatedMs: playlist.updatedMs,
        isAlbum: true,
      ),
      detail.entries,
    );
    await page(tester, playlist.id);
    Future<void> openExport() async {
      await tester.tap(find.byTooltip('Действия плейлиста'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Записать теги в MP3 и FLAC'));
      await tester.pumpAndSettle();
    }

    await openExport();
    expect(albums.writes, 0);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(albums.writes, 0);

    await openExport();
    await tester.tap(find.text('Записать теги'));
    await tester.pumpAndSettle();
    expect(albums.writes, 1);
    expect(find.text('Результат записи тегов'), findsOneWidget);
    expect(find.textContaining('/backups/a.mp3'), findsOneWidget);
  });

  testWidgets(
    'playlist context menu opens the existing metadata editor for its path',
    (tester) async {
      final playlist = await populated();
      await browser(tester);
      await tester.tap(find.text('Плейлисты'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Любимое'));
      await tester.pumpAndSettle();
      for (final entry in repo.items[playlist.id]!.entries) {
        await tester.tap(find.byKey(Key('playlist-entry-menu-${entry.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Редактировать метаданные'));
        // Only inspect routing here. TagLib's isolate uses real I/O, while
        // pumpAndSettle advances the widget test's virtual clock.
        await tester.pump();
        final dialog = tester.widget<MetadataEditorDialog>(
          find.byType(MetadataEditorDialog),
        );
        expect(dialog.path, entry.track.path);
        expect(dialog.controller, same(library));
        await tester.tap(find.text('Отмена'));
        await tester.pumpAndSettle();
      }
      expect(repo.items[playlist.id]!.entries, hasLength(2));
    },
  );

  testWidgets('metadata edit is disabled for an unavailable playlist track', (
    tester,
  ) async {
    final playlist = await populated();
    final entries = repo.items[playlist.id]!.entries;
    repo.update(
      playlist.id,
      entries: [
        PlaylistEntry(
          id: entries.first.id,
          position: 0,
          track: entries.first.track,
          fileState: PlaylistFileState.missing,
          error: 'Missing',
        ),
        entries.last,
      ],
    );
    await browser(tester);
    await tester.tap(find.text('Плейлисты'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Любимое'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('playlist-entry-menu-${entries.first.id}')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(
              PopupMenuItem<String>,
              'Редактировать метаданные',
            ),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets(
    'navigation creates, validates, renames and deletes a playlist only after confirmation',
    (tester) async {
      await browser(tester);
      await tester.tap(find.text('Плейлисты'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Создать плейлист'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Введите название'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('playlist-name')),
        'Для прогулки',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Для прогулки'), findsOneWidget);
      await tester.tap(find.byTooltip('Действия плейлиста'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переименовать'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('playlist-name')), 'Вечер');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Вечер'), findsOneWidget);
      for (final confirm in [false, true]) {
        await tester.tap(find.byTooltip('Действия плейлиста'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Удалить плейлист'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Аудиофайлы сохранятся'), findsOneWidget);
        await tester.tap(find.text(confirm ? 'Удалить' : 'Отмена'));
        await tester.pumpAndSettle();
        expect(repo.items.length, confirm ? 0 : 1);
      }
    },
  );

  testWidgets(
    'multiple selected library tracks and track context menu add to the chosen playlist',
    (tester) async {
      final playlist = await repo.create('Mix');
      await browser(tester);
      await tester.tap(find.text('Треки'));
      await tester.pumpAndSettle();
      for (final id in [1, 2]) {
        await tester.tap(find.byKey(Key('select-track-$id')));
        await tester.pumpAndSettle();
      }
      expect(find.text('Выбрано: 2'), findsOneWidget);
      await tester.tap(find.text('Добавить в плейлист'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('add-to-${playlist.id}')));
      await tester.pumpAndSettle();
      expect(
        repo.items[playlist.id]!.entries.map((entry) => entry.track.title),
        ['Первый трек', 'Второй трек'],
      );
      expect(find.text('Выбрано: 2'), findsNothing);
      await tester.tap(find.byKey(const Key('track-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить в плейлист'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('add-to-${playlist.id}')));
      await tester.pumpAndSettle();
      expect(repo.items[playlist.id]!.entries, hasLength(3));
    },
  );

  testWidgets(
    'playlist page plays exact order and index, reorders, removes and shows duration',
    (tester) async {
      final playlist = await populated();
      List<LocalTrack>? played;
      int? selected;
      await page(
        tester,
        playlist.id,
        play: (tracks, index) async {
          played = tracks;
          selected = index;
        },
      );
      expect(find.text('2 треков · 2:30'), findsOneWidget);
      await tester.tap(find.text('Воспроизвести плейлист'));
      await tester.pumpAndSettle();
      expect(played!.map((track) => track.name), ['Song A', 'Song B']);
      expect(selected, 0);
      final first = repo.items[playlist.id]!.entries.first.id;
      await tester.tap(find.byKey(Key('playlist-entry-menu-$first')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переместить ниже'));
      await tester.pumpAndSettle();
      expect(repo.items[playlist.id]!.entries.first.track.title, 'Song B');
      await tester.tap(find.text('Song A'));
      await tester.pumpAndSettle();
      expect(played!.map((track) => track.name), ['Song B', 'Song A']);
      expect(selected, 1);
      await tester.tap(find.byKey(Key('playlist-entry-menu-$first')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить из плейлиста'));
      await tester.pumpAndSettle();
      expect(repo.items[playlist.id]!.entries, hasLength(1));
      expect(find.text('1 треков · 1:30'), findsOneWidget);
    },
  );

  testWidgets('dragging a handle persists the new order', (tester) async {
    final playlist = await populated();
    await page(tester, playlist.id);
    final start = tester.getCenter(find.byIcon(Icons.drag_handle).first);
    final destination = tester.getCenter(find.byIcon(Icons.drag_handle).last);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    await gesture.moveTo(
      destination +
          Offset(0, tester.getSize(find.byType(ListTile).last).height * 1.5),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(repo.reorders, 1);
    expect(repo.items[playlist.id]!.entries.first.track.title, 'Song B');
  });

  testWidgets(
    'missing-file state blocks play, shows restore errors and restores the same entry',
    (tester) async {
      final playlist = await populated();
      final original = repo.items[playlist.id]!.entries;
      final missing = original.first;
      repo.update(
        playlist.id,
        entries: [
          PlaylistEntry(
            id: missing.id,
            position: 0,
            track: missing.track,
            fileState: PlaylistFileState.missing,
            error: 'Файл перемещён или недоступен',
          ),
          original.last,
        ],
      );
      repo.failure = const FileSystemException('Нет прав');
      await page(
        tester,
        playlist.id,
        play: (_, _) async {},
        picker: () async => '/tmp/restored.mp3',
      );
      expect(find.byKey(Key('playlist-missing-${missing.id}')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Воспроизвести плейлист'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Восстановить ссылку'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Нет прав'), findsOneWidget);
      repo.failure = null;
      await tester.tap(find.byTooltip('Восстановить ссылку'));
      await tester.pumpAndSettle();
      expect(repo.items[playlist.id]!.entries.first.id, missing.id);
      expect(
        repo.items[playlist.id]!.entries.first.track.path,
        '/tmp/restored.mp3',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Воспроизвести плейлист'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('pending add prevents duplicate submits and errors allow retry', (
    tester,
  ) async {
    final playlist = await repo.create('Mix');
    repo.gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => addToPlaylist(context, repo, [
                const PlaylistTrackRef(path: '/tmp/a.mp3', title: 'A'),
              ]),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('add-to-${playlist.id}')));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Отмена'))
          .onPressed,
      isNull,
    );
    repo.failure = StateError('database busy');
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('database busy'), findsOneWidget);
    expect(repo.additions, 1);
    repo.failure = null;
    await tester.tap(find.byKey(Key('add-to-${playlist.id}')));
    await tester.pumpAndSettle();
    expect(repo.items[playlist.id]!.entries, hasLength(1));
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('playlist navigation and page fit width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await populated();
      await browser(tester);
      expect(tester.takeException(), isNull, reason: 'library browser');
      await tester.ensureVisible(find.text('Плейлисты'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Плейлисты'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'playlist list');
      await tester.tap(find.text('Любимое'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
