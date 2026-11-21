import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/library/models.dart';
import 'package:musani/playlists/models.dart';
import 'package:musani/metadata/track_editor.dart';
import 'package:musani/playlists/playlist_repository.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/audio_fixtures.dart';

void main() {
  late Directory dir;
  late Directory music;
  late LibraryRepository library;
  late PlaylistRepository repo;
  late List<LibraryTrack> tracks;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('musani-playlist-');
    music = Directory('${dir.path}/music');
    await createAudioFixture(music, 'mp3', name: 'a', title: 'A');
    await createAudioFixture(music, 'flac', name: 'b', title: 'B');
    library = LibraryRepository('${dir.path}/catalog');
    repo = PlaylistRepository(library.directory);
    await library.scan(addRoot: music.path);
    tracks = (await library.query(const LibraryQuery(view: LibraryView.tracks)))
        .tracks;
  });
  tearDown(() => dir.delete(recursive: true));
  List<PlaylistTrackRef> refs() =>
      tracks.map(PlaylistTrackRef.fromLibrary).toList();
  Future<String> hash(String path) async =>
      sha256.convert(await File(path).readAsBytes()).toString();

  test('create, rename, duplicate names and restart retain stable identities and validate names', () async {
    final a = await repo.create('  Любимое  ');
    final b = await repo.create('Любимое');
    expect(a.name, 'Любимое');
    expect(a.id, isNot(b.id));
    await repo.rename(a.id, a.revision, "Ночь ' OR 1=1 --");
    final reopened = PlaylistRepository(library.directory);
    final list = await reopened.list();
    expect(list.map((item) => item.id).toSet(), {a.id, b.id});
    expect(
      list.singleWhere((item) => item.id == a.id).name,
      "Ночь ' OR 1=1 --",
    );
    expect(list.singleWhere((item) => item.id == a.id).revision, 1);
    for (final name in ['', ' ', 'bad\u0000name', 'a' * 201]) {
      await expectLater(repo.create(name), throwsFormatException);
    }
    expect(await repo.list(), hasLength(2));
  });

  test('ordered entries and repeated tracks persist; membership in many playlists does not duplicate catalog or audio', () async {
    final hashes = {
      for (final track in tracks) track.path: await hash(track.path),
    };
    final a = await repo.create('A');
    await repo.add(a.id, a.revision, [refs()[1], refs()[0], refs()[1]]);
    var detail = await repo.detail(a.id);
    expect(detail.entries.map((entry) => entry.track.title), ['B', 'A', 'B']);
    expect(detail.entries.map((entry) => entry.id).toSet(), hasLength(3));
    expect(
      detail.playlist.durationMs,
      tracks[0].metadata.durationMs + 2 * tracks[1].metadata.durationMs,
    );
    final order = detail.entries
        .map((entry) => entry.id)
        .toList()
        .reversed
        .toList();
    await repo.reorder(a.id, detail.playlist.revision, order);
    detail = await PlaylistRepository(library.directory).detail(a.id);
    expect(detail.entries.map((entry) => entry.id), order);
    expect(detail.entries.map((entry) => entry.position), [0, 1, 2]);
    for (var i = 0; i < 20; i++) {
      final other = await repo.create('Other $i');
      await repo.add(other.id, other.revision, [refs().first]);
    }
    expect((await library.status()).trackCount, 2);
    for (final entry in hashes.entries) {
      expect(await hash(entry.key), entry.value);
    }
  });

  test('remove and delete leave audio and other playlists untouched; tombstones preserve IDs', () async {
    final a = await repo.create('A');
    final b = await repo.create('B');
    await repo.add(a.id, 0, refs());
    await repo.add(b.id, 0, refs());
    final first = await repo.detail(a.id);
    await repo.remove(a.id, first.playlist.revision, first.entries.first.id);
    var changed = await repo.detail(a.id);
    expect(changed.entries.single.id, first.entries.last.id);
    expect(changed.entries.single.position, 0);
    expect((await repo.detail(b.id)).entries, hasLength(2));
    await repo.delete(a.id, changed.playlist.revision);
    expect((await repo.list()).single.id, b.id);
    await expectLater(repo.detail(a.id), throwsStateError);
    for (final track in tracks) {
      expect(await File(track.path).exists(), isTrue);
    }
    final db = sqlite3.open(library.databasePath);
    try {
      expect(
        db.select('SELECT deleted_at FROM playlists WHERE id=?', [
          a.id,
        ]).single['deleted_at'],
        isNotNull,
      );
      expect(
        db.select(
          'SELECT id FROM playlist_entries WHERE playlist_id=? AND deleted_at IS NOT NULL',
          [a.id],
        ),
        hasLength(2),
      );
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      db.dispose();
    }
  });

  test('stale mutations, invalid permutations and partial additions roll back atomically', () async {
    final a = await repo.create('A');
    await repo.add(a.id, 0, refs());
    final detail = await repo.detail(a.id);
    await expectLater(repo.rename(a.id, 0, 'lost update'), throwsStateError);
    await expectLater(repo.delete(a.id, 0), throwsStateError);
    final ids = detail.entries.map((entry) => entry.id).toList();
    for (final bad in [
      [ids.first],
      [ids.first, ids.first],
      [ids.first, 'foreign'],
    ]) {
      await expectLater(
        repo.reorder(a.id, detail.playlist.revision, bad),
        throwsStateError,
      );
    }
    await expectLater(
      repo.add(a.id, detail.playlist.revision, [
        refs().first,
        const PlaylistTrackRef(path: 'relative.mp3', title: 'bad'),
      ]),
      throwsFormatException,
    );
    final unchanged = await repo.detail(a.id);
    expect(unchanged.playlist.revision, detail.playlist.revision);
    expect(unchanged.entries.map((entry) => entry.id), ids);
    final other = await repo.create('Other');
    await repo.add(other.id, 0, refs());
    await expectLater(
      repo.remove(
        a.id,
        unchanged.playlist.revision,
        (await repo.detail(other.id)).entries.first.id,
      ),
      throwsStateError,
    );
  });

  test('missing file survives catalog pruning and can be relinked without changing entry identity, order or audio', () async {
    final a = await repo.create('A');
    await repo.add(a.id, 0, refs());
    final original = await repo.detail(a.id);
    final entry = original.entries.first;
    final digest = await hash(entry.track.path);
    final moved = await File(entry.track.path).rename('${dir.path}/moved.mp3');
    await library.scan();
    var detail = await repo.detail(a.id);
    expect(detail.entries, hasLength(2));
    expect(detail.entries.first.track.trackId, isNull);
    expect(detail.entries.first.fileState, PlaylistFileState.missing);
    expect(detail.entries.first.track.title, 'A');
    expect(detail.entries.first.error, contains('перемещён'));
    expect(detail.playlist.durationMs, original.playlist.durationMs);
    await expectLater(
      repo.relink(
        a.id,
        detail.playlist.revision,
        entry.id,
        '${dir.path}/missing.mp3',
      ),
      throwsA(isA<FileSystemException>()),
    );
    final corrupt = await File('${dir.path}/bad.flac').writeAsString('bad');
    await expectLater(
      repo.relink(a.id, detail.playlist.revision, entry.id, corrupt.path),
      throwsFormatException,
    );
    detail = await repo.detail(a.id);
    expect(detail.playlist.revision, original.playlist.revision);
    await repo.relink(a.id, detail.playlist.revision, entry.id, moved.path);
    detail = await PlaylistRepository(library.directory).detail(a.id);
    expect(detail.entries.first.id, entry.id);
    expect(detail.entries.first.position, entry.position);
    expect(detail.entries.first.available, isTrue);
    expect(detail.entries.first.track.path, moved.path);
    expect(await hash(moved.path), digest);
  });

  test('read permission errors are visible and returning paths reattach after source removal', () async {
    final a = await repo.create('A');
    await repo.add(a.id, 0, refs());
    await Process.run('chmod', ['000', tracks.first.path]);
    try {
      expect(
        (await repo.detail(a.id)).entries.first.fileState,
        PlaylistFileState.unreadable,
      );
    } finally {
      await Process.run('chmod', ['644', tracks.first.path]);
    }
    await library.removeRoot((await library.status()).roots.single.id);
    expect((await library.status()).trackCount, 0);
    expect(
      (await repo.detail(a.id)).entries.every((entry) => entry.available),
      isTrue,
    );
    await library.scan(addRoot: music.path);
    final current = (await library.query(
      const LibraryQuery(view: LibraryView.tracks),
    )).tracks;
    expect(
      (await repo.detail(a.id)).entries.map((entry) => entry.track.trackId),
      current.map((track) => track.id),
    );
  });

  test('directly opened files outside the library get real labels and duration without tag writes', () async {
    final outside = await createAudioFixture(
      Directory('${dir.path}/outside'),
      'flac',
      title: 'External song',
    );
    final before = await hash(outside.path);
    final playlist = await repo.create('Outside');
    await repo.add(playlist.id, 0, [
      PlaylistTrackRef(path: outside.path, title: 'filename.flac'),
    ]);
    final entry = (await repo.detail(playlist.id)).entries.single;
    expect(entry.track.title, 'External song');
    expect(entry.track.durationMs, greaterThanOrEqualTo(900));
    expect(entry.track.trackId, isNull);
    expect(entry.available, isTrue);
    expect(await hash(outside.path), before);
    expect((await library.status()).trackCount, 2);
  });

  test('tag edits refresh playlist snapshots and survive subsequent catalog removal', () async {
    final playlist = await repo.create('Tags');
    await repo.add(playlist.id, 0, [refs().first]);
    final editor = TagLibTrackEditor('${dir.path}/backups');
    await editor.save(
      await editor.read(tracks.first.path),
      const MetadataPatch(
        {'TITLE': 'Edited song'},
        artists: ['Tyler, The Creator', 'Guest'],
      ),
    );
    await library.reindexTrack(tracks.first.path);
    final updated = (await repo.detail(playlist.id)).entries.single;
    expect(updated.track.title, 'Edited song');
    expect(updated.track.artists, ['Tyler, The Creator', 'Guest']);
    await library.removeRoot((await library.status()).roots.single.id);
    final retained = (await repo.detail(playlist.id)).entries.single;
    expect(retained.id, updated.id);
    expect(retained.track.title, 'Edited song');
    expect(retained.track.artists, updated.track.artists);
    expect(retained.track.trackId, isNull);
    expect(retained.available, isTrue);
  });

  for (final format in ['mp3', 'flac']) {
    test(
      '$format external playlist edit preserves entries and stays outside catalog',
      () async {
        final file = await createAudioFixture(
          Directory('${dir.path}/outside'),
          format,
        );
        final playlist = await repo.create('External');
        final ref = PlaylistTrackRef(path: file.path, title: 'Old');
        await repo.add(playlist.id, 0, [ref, ref]);
        final before = await repo.detail(playlist.id);
        final editor = TagLibTrackEditor('${dir.path}/backups');
        await editor.save(
          await editor.read(file.path),
          const MetadataPatch(
            {'TITLE': 'New title'},
            artists: ['Tyler, The Creator', 'Guest'],
          ),
        );
        await library.reindexTrack(file.path);
        final after = await PlaylistRepository(library.directory)
            .detail(playlist.id);
        expect(after.entries.map((e) => e.id), before.entries.map((e) => e.id));
        expect(after.entries.map((e) => e.position), [0, 1]);
        for (final entry in after.entries) {
          expect(entry.track.title, 'New title');
          expect(entry.track.artists, ['Tyler, The Creator', 'Guest']);
          expect(entry.track.trackId, isNull);
        }
        expect((await library.status()).trackCount, 2);
        expect(await library.trackByPath(file.path), isNull);
      },
    );
  }

  test('v2 upgrade adds playlist storage without changing the catalog; newer schemas are refused', () async {
    var db = sqlite3.open(library.databasePath);
    db.execute('DROP TABLE playlist_artwork');
    db.execute('DROP TABLE playlist_entries');
    db.execute('DROP TABLE playlists');
    db.execute('PRAGMA user_version=2');
    final old = db
        .select('SELECT * FROM tracks ORDER BY id')
        .map((row) => Map<String, Object?>.from(row))
        .toList();
    db.dispose();
    expect(await PlaylistRepository(library.directory).list(), isEmpty);
    db = sqlite3.open(library.databasePath);
    try {
      expect(db.select('PRAGMA user_version').single.values.single, 5);
      expect(
        db
            .select('SELECT * FROM tracks ORDER BY id')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
        old,
      );
      db.execute('PRAGMA user_version=999');
    } finally {
      db.dispose();
    }
    await expectLater(repo.list(), throwsStateError);
  });

  test(
    'v3 playlists keep their entries and save or reset artwork atomically',
    () async {
      final playlist = await repo.create('Обложки');
      const secondCover = PlaylistTrackRef(
        path: '/missing/snapshot.flac',
        title: 'Снимок',
        coverKey: 'snapshot',
      );
      await repo.add(playlist.id, playlist.revision, [
        refs().first,
        refs().first,
        secondCover,
        secondCover,
      ]);
      final before = await repo.detail(playlist.id);
      final audioHash = await hash(tracks.first.path);
      final db = sqlite3.open(library.databasePath);
      db.execute('DROP TABLE playlist_artwork');
      db.execute('ALTER TABLE playlists DROP COLUMN is_album');
      db.execute('PRAGMA user_version=3');
      db.dispose();

      final restored = PlaylistRepository(library.directory);
      final fallback = await restored.artwork(playlist.id);
      expect(fallback.trackCovers, [
        tracks.first.metadata.coverKey,
        'snapshot',
      ]);
      expect(fallback.image, isNull);
      final image = await File('${music.path}/cover.png').readAsBytes();
      await restored.setArtwork(playlist.id, before.playlist.revision, image);
      await expectLater(
        repo.setArtwork(playlist.id, before.playlist.revision, null),
        throwsStateError,
      );
      expect((await repo.artwork(playlist.id)).image, orderedEquals(image));

      final after = await repo.detail(playlist.id);
      await repo.setArtwork(playlist.id, after.playlist.revision, null);
      expect(
        (await restored.artwork(playlist.id)).trackCovers,
        fallback.trackCovers,
      );
      expect(
        (await repo.detail(playlist.id)).entries.map((entry) => entry.id),
        before.entries.map((entry) => entry.id),
      );
      expect(await hash(tracks.first.path), audioHash);
    },
  );

  test('v4 playlists become ordinary playlists; album properties preserve artwork, entries and tags', () async {
    final playlist = await repo.create('Порядок');
    await repo.add(playlist.id, playlist.revision, [
      refs()[1],
      refs()[0],
      refs()[1],
    ]);
    final image = await File('${music.path}/cover.png').readAsBytes();
    await repo.setArtwork(playlist.id, playlist.revision + 1, image);
    final before = await repo.detail(playlist.id);
    final audioHashes = [for (final track in tracks) await hash(track.path)];
    final db = sqlite3.open(library.databasePath);
    try {
      db.execute('ALTER TABLE playlists DROP COLUMN is_album');
      db.execute('PRAGMA user_version=4');
    } finally {
      db.dispose();
    }

    final reopened = PlaylistRepository(library.directory);
    final migrated = await reopened.detail(playlist.id);
    expect(migrated.playlist.isAlbum, isFalse);
    expect(migrated.playlist.revision, before.playlist.revision);
    expect(
      migrated.entries.map((entry) => entry.id),
      before.entries.map((entry) => entry.id),
    );
    await reopened.updateProperties(
      playlist.id,
      migrated.playlist.revision,
      name: 'Мой альбом',
      isAlbum: true,
    );
    await expectLater(
      reopened.updateProperties(
        playlist.id,
        migrated.playlist.revision,
        name: 'Устаревшая правка',
        isAlbum: false,
      ),
      throwsStateError,
    );
    final saved = await PlaylistRepository(library.directory)
        .detail(playlist.id);
    expect(saved.playlist.isAlbum, isTrue);
    expect(saved.playlist.name, 'Мой альбом');
    expect(saved.playlist.revision, before.playlist.revision + 1);
    expect(
      saved.entries.map(
        (entry) => (entry.id, entry.position, entry.track.trackId),
      ),
      before.entries.map(
        (entry) => (entry.id, entry.position, entry.track.trackId),
      ),
    );
    expect((await reopened.artwork(playlist.id)).image, orderedEquals(image));
    await reopened.updateProperties(
      playlist.id,
      saved.playlist.revision,
      name: 'Мой альбом',
      isAlbum: false,
    );
    expect((await reopened.list()).single.isAlbum, isFalse);
    expect([for (final track in tracks) await hash(track.path)], audioHashes);
    final upgraded = sqlite3.open(library.databasePath);
    try {
      expect(upgraded.select('PRAGMA user_version').single.values.single, 5);
      expect(upgraded.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      upgraded.dispose();
    }
  });
}
