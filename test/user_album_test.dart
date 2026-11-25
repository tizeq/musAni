import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/library/models.dart';
import 'package:musani/metadata/audio_digest.dart';
import 'package:musani/playlists/models.dart';
import 'package:musani/playlists/playlist_repository.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/catalog_fixture.dart';
import 'support/audio_fixtures.dart';

void main() {
  late Directory temp;
  late Directory music;
  late File mp3;
  late File flac;
  late LibraryRepository library;
  late PlaylistRepository playlists;
  late List<PlaylistTrackRef> refs;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('musani-user-album-');
    music = Directory('${temp.path}/music');
    mp3 = await createAudioFixture(
      music,
      'mp3',
      name: 'a',
      title: 'Первая',
      artist: 'Солист',
      album: 'Исходный',
    );
    flac = await createAudioFixture(
      music,
      'flac',
      name: 'b',
      title: 'Вторая',
      artist: 'Гость',
      album: 'Исходный',
    );
    library = LibraryRepository('${temp.path}/catalog');
    playlists = PlaylistRepository(library.directory);
    await library.scan(addRoot: music.path);
    refs = (await library.query(const LibraryQuery(view: LibraryView.tracks)))
        .tracks
        .map(PlaylistTrackRef.fromLibrary)
        .toList();
  });
  tearDown(() => temp.delete(recursive: true));
  const shared = UserAlbumMetadata(
    artist: 'Ансамбль',
    year: 1998,
    genre: 'Джаз',
    disc: 2,
  );

  Future<PlaylistDetail> album(
    String name,
    Iterable<PlaylistTrackRef> tracks,
  ) async {
    final list = await playlists.create(name);
    if (tracks.isNotEmpty)
      await playlists.add(list.id, list.revision, tracks.toList());
    final detail = await playlists.detail(list.id);
    await playlists.updateAlbum(
      list.id,
      detail.playlist.revision,
      name,
      shared,
    );
    return playlists.detail(list.id);
  }

  Future<Uint8List> alternateCover() async {
    final path = '${temp.path}/alternate.png';
    await ffmpeg([
      '-f',
      'lavfi',
      '-i',
      'color=red:s=24x24',
      '-frames:v',
      '1',
      '-threads',
      '1',
      path,
    ]);
    return File(path).readAsBytes();
  }

  test('shared metadata, art, search, queue ordering and detach use one album identity', () async {
    expect(
      (await library.query(const LibraryQuery())).albums.single.title,
      'Исходный',
    );
    final detail = await album('Сборник', refs);
    final id = detail.playlist.id;
    final effectiveId = 'playlist:$id';
    expect(
      (await library.query(const LibraryQuery())).albums.single.id,
      effectiveId,
    );
    final cover = await alternateCover();
    await playlists.setArtwork(id, detail.playlist.revision, cover);
    var rows = await library.albumTracks(effectiveId);
    expect(rows.map((t) => t.metadata.title), ['Вторая', 'Первая']);
    expect(rows.map((t) => t.metadata.artists.single), ['Гость', 'Солист']);
    expect(rows.map((t) => t.metadata.trackNumber), [1, 2]);
    for (final row in rows) {
      expect(row.metadata.album, 'Сборник');
      expect(row.metadata.albumArtist, 'Ансамбль');
      expect(row.metadata.year, 1998);
      expect(row.metadata.genre, 'Джаз');
      expect(row.metadata.discNumber, 2);
      expect(row.metadata.coverKey, rows.first.metadata.coverKey);
      expect(row.metadata.properties['ALBUM'], ['Исходный']);
    }
    expect(
      await File(library.coverPath(rows.first.metadata.coverKey!))
          .readAsBytes(),
      cover,
    );
    expect(
      (await library.query(const LibraryQuery(search: 'ДЖАЗ')))
          .albums
          .single
          .id,
      effectiveId,
    );
    expect(
      (await library.query(
        const LibraryQuery(view: LibraryView.tracks, search: 'АНСАМБЛЬ'),
      )).total,
      2,
    );
    var refreshed = await playlists.detail(id);
    final reversed = refreshed.entries.reversed.map((e) => e.id).toList();
    await playlists.reorder(id, refreshed.playlist.revision, reversed);
    refreshed = await playlists.detail(id);
    await playlists.setAlbumDisc(
      id,
      refreshed.playlist.revision,
      reversed.last,
      4,
    );
    rows = await library.albumTracks(effectiveId);
    expect(
      rows.map((t) => (t.path, t.metadata.discNumber, t.metadata.trackNumber)),
      [(mp3.path, 2, 1), (flac.path, 4, 1)],
    );
    refreshed = await playlists.detail(id);
    await playlists.remove(id, refreshed.playlist.revision, reversed.first);
    expect((await library.trackByPath(mp3.path))?.metadata.album, 'Исходный');
    expect(
      (await library.albumTracks(effectiveId)).single.metadata.trackNumber,
      1,
    );
    refreshed = await playlists.detail(id);
    await playlists.updateProperties(
      id,
      refreshed.playlist.revision,
      name: 'Сборник',
      isAlbum: false,
    );
    expect(
      (await library.query(const LibraryQuery())).albums.single.title,
      'Исходный',
    );
    expect((await playlists.detail(id)).entries.single.track.title, 'Вторая');
  });

  test('empty albums appear in search, external tracks are indexed virtually, conflicts are transactional', () async {
    final first = await album('Основной', [refs.first]);
    final second = await album('ПУСТОЙ %', []);
    final id = second.playlist.id;
    expect(
      (await library.query(const LibraryQuery(search: 'пустой %')))
          .albums
          .single
          .trackCount,
      0,
    );
    final alias = await Link('${temp.path}/alias.flac').create(refs.first.path);
    await expectLater(
      playlists.add(id, second.playlist.revision, [
        PlaylistTrackRef(path: alias.path, title: 'Псевдоним'),
      ]),
      throwsStateError,
    );
    final external = await createAudioFixture(
      Directory('${temp.path}/external'),
      'ogg',
      artist: 'Гость',
      title: 'Вне папки',
    );
    final ref = PlaylistTrackRef(path: external.path, title: 'Вне папки');
    await expectLater(
      playlists.add(id, second.playlist.revision, [ref, refs.first]),
      throwsStateError,
    );
    expect((await playlists.detail(id)).entries, isEmpty);
    await playlists.add(id, second.playlist.revision, [ref]);
    final externalTrack = (await library.trackByPath(external.path))!;
    expect(externalTrack.metadata.title, 'Вне папки');
    expect(externalTrack.metadata.album, 'ПУСТОЙ %');
    expect(externalTrack.metadata.artists, ['Гость']);
    expect(
      (await library.query(const LibraryQuery(view: LibraryView.artists)))
          .artists
          .firstWhere((a) => a.name == 'Гость')
          .trackCount,
      2,
    );
    expect(
      (await library.query(
        const LibraryQuery(view: LibraryView.tracks, search: 'ВНЕ ПАПКИ'),
      )).tracks.single.path,
      external.path,
    );
    await playlists.delete(first.playlist.id, first.playlist.revision);
    final latest = await playlists.detail(id);
    await playlists.add(id, latest.playlist.revision, [refs.first]);
    expect(
      (await library.albumTracks('playlist:$id')).last.metadata.trackNumber,
      2,
    );
  });

  test(
    'v5 overlap keeps existing entries and transfers ownership after removal',
    () async {
      final a = await playlists.create('Первый');
      final b = await playlists.create('Второй');
      await playlists.add(a.id, a.revision, [refs.first]);
      await playlists.add(b.id, b.revision, [refs.first]);
      final db = sqlite3.open(library.databasePath);
      try {
        dropV6AlbumStorage(db);
        db.execute(
          "UPDATE playlists SET is_album=1, created_at=CASE WHEN id=? THEN 10 ELSE 20 END",
          [a.id],
        );
        db.execute('PRAGMA user_version=5');
      } finally {
        db.dispose();
      }
      final first = await playlists.detail(a.id);
      final second = await playlists.detail(b.id);
      expect(first.entries.single.albumConflict, isNull);
      expect(second.entries.single.albumConflict, 'Первый');
      expect(
        (await library.trackByPath(refs.first.path))!.albumId,
        'playlist:${a.id}',
      );
      await playlists.remove(
        a.id,
        first.playlist.revision,
        first.entries.single.id,
      );
      expect((await playlists.detail(b.id)).entries.single.albumTrackNumber, 1);
      expect(
        (await library.trackByPath(refs.first.path))!.albumId,
        'playlist:${b.id}',
      );
    },
  );

  test('batch TagLib export preserves audio and individual tags and reports partial failures', () async {
    final ogg = await createAudioFixture(
      Directory('${temp.path}/elsewhere'),
      'ogg',
    );
    final missing = '${music.path}/missing.mp3';
    final detail = await album('Сборник', [
      ...refs,
      PlaylistTrackRef(path: ogg.path, title: 'OGG'),
      PlaylistTrackRef(path: missing, title: 'Нет файла'),
    ]);
    final before = {
      mp3.path: audioDigest(mp3.path, '.mp3'),
      flac.path: audioDigest(flac.path, '.flac'),
    };
    for (final file in [mp3, flac]) {
      final tag = TagLibFile.open(file.path)!;
      try {
        tag.setProperties({
          ...tag.properties,
          'COMMENT': ['Сохранить этот комментарий'],
        });
        expect(tag.save(), isTrue);
      } finally {
        tag.close();
      }
    }
    final cover = await alternateCover();
    await playlists.setArtwork(
      detail.playlist.id,
      detail.playlist.revision,
      cover,
    );
    await expectLater(
      playlists.writeAlbumTags(detail.playlist.id, detail.playlist.revision),
      throwsStateError,
    );
    final exported = await playlists.writeAlbumTags(
      detail.playlist.id,
      detail.playlist.revision + 1,
    );
    expect(exported.catalogWarning, isNull);
    expect(exported.items.map((i) => i.status), [
      AlbumWriteStatus.saved,
      AlbumWriteStatus.saved,
      AlbumWriteStatus.unsupported,
      AlbumWriteStatus.failed,
    ], reason: exported.items.map((i) => i.message).toString());
    for (final (index, file) in [flac, mp3].indexed) {
      final tag = TagLibFile.open(file.path)!;
      try {
        expect(tag.album, 'Сборник');
        expect(tag.title, index == 0 ? 'Вторая' : 'Первая');
        expect(tag.artist, index == 0 ? 'Гость' : 'Солист');
        expect(tag.properties['ALBUMARTIST'], ['Ансамбль']);
        expect(tag.properties['COMMENT'], ['Сохранить этот комментарий']);
        expect(tag.properties['DISCNUMBER'], ['2/2']);
        expect(tag.track, index + 1);
        expect(tag.year, 1998);
        expect(tag.genre, 'Джаз');
        expect(tag.coverData, cover);
      } finally {
        tag.close();
      }
      expect(
        audioDigest(file.path, index == 0 ? '.flac' : '.mp3'),
        before[file.path],
      );
      expect(File(exported.items[index].backupPath!).existsSync(), isTrue);
      expect(
        (await library.trackByPath(file.path))!.metadata.properties['ALBUM'],
        ['Сборник'],
      );
    }
    expect(
      (await library.query(const LibraryQuery())).albums.single.id,
      'playlist:${detail.playlist.id}',
    );
  });
}
