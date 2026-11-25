import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musani/library/library_database.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/library/metadata_reader.dart';
import 'package:musani/library/models.dart';
import 'package:musani/metadata/track_editor.dart';

import 'support/audio_fixtures.dart';

class _QueueFixtureReader implements MetadataReader {
  @override
  TrackMetadata read(String path, String coverDirectory) {
    final number = int.parse(Uri.file(path).pathSegments.last.split('.').first);
    return TrackMetadata(
      title: number < 70 ? 'Queue ${number ~/ 2}' : 'Outside filter',
      artists: ['Tyler, The Creator', 'Guest ${number % 3}'],
      album: 'Album ${number % 4}',
      albumArtist: 'Album artist',
      year: 2000 + number % 10,
      trackNumber: number,
    );
  }
}

void main() {
  late Directory temporary;
  late Directory music;
  late LibraryRepository repository;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('musani-library-');
    music = await Directory('${temporary.path}/music').create();
    repository = LibraryRepository('${temporary.path}/catalog');
  });
  tearDown(() => temporary.delete(recursive: true));

  test(
    'playback snapshot matches all UI pages for each sort and direction',
    () async {
      for (var i = 0; i < 75; i++) {
        await File('${music.path}/$i.flac').writeAsBytes([0]);
      }
      await Directory(repository.directory).create();
      final db = LibraryDatabase(
        repository.databasePath,
        repository.coverDirectory,
      );
      try {
        await db.scan(addRoot: music.path, reader: _QueueFixtureReader());
      } finally {
        db.close();
      }
      final path = '${music.path}/0.flac';
      final firstRead = repository.trackByPath(path);
      final duplicate = repository.trackByPath(path);
      final missing = repository.trackByPath('${music.path}/missing.flac');
      final another = repository.trackByPath('${music.path}/74.flac');
      expect(identical(firstRead, duplicate), isTrue);
      expect((await firstRead)?.metadata.artists, [
        'Tyler, The Creator',
        'Guest 0',
      ]);
      expect(await missing, isNull);
      expect((await another)?.metadata.title, 'Outside filter');

      for (final sort in LibrarySort.values) {
        for (final descending in [false, true]) {
          final query = LibraryQuery(
            view: LibraryView.tracks,
            search: 'QUEUE',
            artistId: 'tyler, the creator',
            limit: 60,
            sort: sort,
            descending: descending,
          );
          final first = await repository.query(query);
          final second = await repository.query(query.page(first.length));
          final snapshot = await repository.playbackTracks(query.page(60));
          expect(first.tracks, hasLength(60));
          expect(second.tracks, hasLength(10));
          final expected = [...first.tracks, ...second.tracks];
          expect(
            snapshot.map((track) => (track.uri, track.name)),
            expected.map((track) => (track.playable.uri, track.metadata.title)),
          );
          expect(
            snapshot.map((track) => track.artists),
            expected.map((track) => track.metadata.artists),
          );
        }
      }
    },
  );

  test(
    'navigation reuses catalog results and refresh invalidates both caches',
    () async {
      final file = await createAudioFixture(music, 'mp3');
      await repository.scan(addRoot: music.path);
      final first = await repository.query(const LibraryQuery());
      expect(
        identical(first, await repository.query(const LibraryQuery())),
        isTrue,
      );
      final album = await repository.albumTracks(first.albums.single.id);
      expect(
        identical(album, await repository.albumTracks(first.albums.single.id)),
        isTrue,
      );
      await file.delete();
      await repository.scan();
      expect((await repository.query(const LibraryQuery())).total, 0);
      expect(await repository.albumTracks(first.albums.single.id), isEmpty);
    },
  );

  test('single-file edit refreshes album, search and cover caches; staging is ignored', () async {
    final file = await createAudioFixture(music, 'flac');
    final staging = await Directory('${music.path}/.musani-edit-leftover')
        .create();
    await file.copy('${staging.path}/track.flac');
    final report = await repository.scan(addRoot: music.path);
    expect(report.updated, 1);
    final oldAlbum = (await repository.query(const LibraryQuery()))
        .albums
        .single;
    final track = (await repository.albumTracks(oldAlbum.id)).single;
    final image = '${temporary.path}/new.png';
    await ffmpeg([
      '-f',
      'lavfi',
      '-i',
      'color=c=blue:s=32x32',
      '-frames:v',
      '1',
      '-threads',
      '1',
      image,
    ]);
    final editor = TagLibTrackEditor('${temporary.path}/backups');
    await editor.save(
      await editor.read(file.path),
      MetadataPatch({
        'TITLE': 'Brand new song',
        'ALBUM': 'Brand new album',
        'ALBUMARTIST': 'Brand new artist',
      }, coverPath: image),
    );
    await repository.reindexTrack(file.path);
    final updated = (await repository.query(const LibraryQuery()))
        .albums
        .single;
    expect(updated.title, 'Brand new album');
    expect(updated.artist, 'Brand new artist');
    expect(updated.coverKey, isNot(oldAlbum.coverKey));
    expect(
      await File(repository.coverPath(updated.coverKey!)).readAsBytes(),
      await File(image).readAsBytes(),
    );
    expect(await repository.albumTracks(oldAlbum.id), isEmpty);
    final newTrack = (await repository.albumTracks(updated.id)).single;
    expect(newTrack.id, track.id);
    expect(newTrack.metadata.title, 'Brand new song');
    expect(
      (await repository.query(
        const LibraryQuery(view: LibraryView.tracks, search: 'Brand new song'),
      )).tracks.single.id,
      track.id,
    );
  });

  test(
    'recursive four-format scan, grouping, covers, search and cached restart',
    () async {
      final hashes = <String, String>{};
      var track = 0;
      for (final extension in ['mp3', 'flac', 'm4a', 'ogg']) {
        final file = await createAudioFixture(
          Directory('${music.path}/nested/$extension'),
          extension,
          track: ++track,
          artist: track == 4 ? 'Гость' : 'Исполнитель',
        );
        hashes[file.path] = sha256.convert(await file.readAsBytes()).toString();
      }
      await File('${music.path}/README').writeAsString('not music');
      await File('${music.path}/ignored.txt').writeAsString('not music');
      await Link('${music.path}/loop').create(music.path);
      final report = await repository.scan(addRoot: music.path);
      expect(report.updated, 4);
      expect(report.warnings, isEmpty);
      final status = await repository.status();
      expect(status.trackCount, 4);
      expect(status.albumCount, 1);
      expect(status.artistCount, 2);
      final albums = await repository.query(const LibraryQuery());
      final album = albums.albums.single;
      expect(album.artist, 'Группа');
      expect(album.trackCount, 4);
      expect(File(repository.coverPath(album.coverKey!)).existsSync(), isTrue);
      final ordered = await repository.albumTracks(album.id);
      expect(ordered.map((value) => value.metadata.trackNumber), [1, 2, 3, 4]);
      expect(ordered.map((value) => value.id).toSet(), hasLength(4));
      expect(
        (await repository.query(const LibraryQuery(search: 'ПЕРВАЯ'))).total,
        1,
      );
      expect(
        (await repository.query(const LibraryQuery(view: LibraryView.artists)))
            .artists
            .map((value) => value.name),
        ['Гость', 'Исполнитель'],
      );
      final guest = await repository.query(
        const LibraryQuery(artistId: 'гость'),
      );
      expect(guest.albums.single.trackCount, 4);
      final refresh = await repository.scan();
      expect(refresh.updated, 0);
      expect(refresh.unchanged, 4);
      for (final entry in hashes.entries) {
        expect(
          sha256.convert(await File(entry.key).readAsBytes()).toString(),
          entry.value,
        );
      }
      // A cached launch does not even require the source drive to be mounted.
      await music.rename('${temporary.path}/offline');
      final reopened = LibraryRepository(repository.directory);
      expect((await reopened.status()).trackCount, 4);
      expect(
        (await reopened.query(const LibraryQuery())).albums.single.title,
        'Альбом',
      );
    },
  );

  test('incremental add/change/delete preserves stable IDs and repeat-free catalog reads', () async {
    final first = await createAudioFixture(music, 'mp3');
    await repository.scan(addRoot: music.path);
    final original = (await repository.query(
      const LibraryQuery(view: LibraryView.tracks),
    )).tracks.single;
    final replacement = await createAudioFixture(
      music,
      'mp3',
      name: 'replacement',
      title: 'Изменённое название',
      track: 2,
    );
    await replacement.rename(first.path);
    final added = await createAudioFixture(
      music,
      'ogg',
      name: 'added',
      title: 'Добавлено',
      track: 1,
    );
    final result = await repository.scan();
    expect(result.updated, 2);
    final rows = (await repository.query(
      const LibraryQuery(view: LibraryView.tracks),
    )).tracks;
    final changed = rows.singleWhere((value) => value.path == first.path);
    expect(changed.id, original.id);
    expect(changed.metadata.title, 'Изменённое название');
    await first.delete();
    final deleted = await repository.scan();
    expect(deleted.removed, 1);
    expect(deleted.unchanged, 1);
    expect(
      (await repository.query(const LibraryQuery(view: LibraryView.tracks)))
          .tracks
          .single
          .path,
      added.path,
    );
  });

  test('overlapping/duplicate folders deduplicate files; removal never deletes audio', () async {
    final nested = Directory('${music.path}/nested');
    final file = await createAudioFixture(nested, 'flac');
    await repository.scan(addRoot: music.path);
    final duplicate = await repository.scan(addRoot: '${music.path}/../music');
    expect(duplicate.updated, 0);
    expect((await repository.status()).roots, hasLength(1));
    await repository.scan(addRoot: nested.path);
    final status = await repository.status();
    expect(status.trackCount, 1);
    expect(status.roots, hasLength(2));
    await repository.removeRoot(
      status.roots.firstWhere((root) => root.path == music.path).id,
    );
    expect((await repository.status()).trackCount, 1);
    await repository.removeRoot((await repository.status()).roots.single.id);
    expect((await repository.status()).trackCount, 0);
    expect(await file.exists(), isTrue);
  });

  test(
    'unavailable root is reported and its cached records are retained',
    () async {
      await createAudioFixture(music, 'm4a');
      await repository.scan(addRoot: music.path);
      await music.rename('${temporary.path}/offline');
      final result = await repository.scan();
      expect(result.warnings, isNotEmpty);
      expect(result.removed, 0);
      expect((await repository.status()).trackCount, 1);
      expect((await repository.status()).roots.single.error, isNotNull);
      await Directory('${temporary.path}/offline').rename(music.path);
      await repository.scan();
      expect((await repository.status()).roots.single.error, isNull);
    },
  );

  test('corrupt audio, missing tags and missing cached covers do not break refresh', () async {
    await createAudioFixture(music, 'flac');
    await createAudioFixture(
      Directory('${music.path}/untagged'),
      'ogg',
      title: '',
      album: '',
      artist: '',
      albumArtist: '',
      withCover: false,
    );
    await File('${music.path}/broken.mp3').writeAsString('broken');
    final initial = await repository.scan(addRoot: music.path);
    expect(initial.updated, 3);
    expect(initial.warnings, isNotEmpty);
    final albums = (await repository.query(const LibraryQuery())).albums;
    final cover = albums
        .firstWhere((album) => album.coverKey != null)
        .coverKey!;
    await File(repository.coverPath(cover)).delete();
    final refreshed = await repository.scan();
    expect(refreshed.updated, 1);
    expect(await File(repository.coverPath(cover)).exists(), isTrue);
    final rows = (await repository.query(
      const LibraryQuery(view: LibraryView.tracks),
    )).tracks;
    expect(
      rows
          .singleWhere((track) => track.path.endsWith('broken.mp3'))
          .metadata
          .warning,
      isNotNull,
    );
    expect(
      rows
          .singleWhere((track) => track.path.contains('untagged'))
          .metadata
          .albumTagged,
      isFalse,
    );
  });

  test(
    'search escapes SQL wildcards and pagination/sorting remain deterministic',
    () async {
      await createAudioFixture(
        music,
        'mp3',
        name: 'a',
        title: '100%_track',
        artist: 'А',
      );
      await createAudioFixture(
        music,
        'mp3',
        name: 'b',
        title: 'Beta',
        artist: 'Б',
      );
      await repository.scan(addRoot: music.path);
      expect(
        (await repository.query(
          const LibraryQuery(view: LibraryView.tracks, search: '%_'),
        )).total,
        1,
      );
      expect(
        (await repository.query(const LibraryQuery(search: "' OR 1=1 --")))
            .total,
        0,
      );
      final first = await repository.query(
        const LibraryQuery(view: LibraryView.tracks, limit: 1),
      );
      final second = await repository.query(
        const LibraryQuery(view: LibraryView.tracks, offset: 1, limit: 1),
      );
      expect(first.total, 2);
      expect(first.tracks.single.id, isNot(second.tracks.single.id));
      expect(
        (await repository.query(
          const LibraryQuery(
            view: LibraryView.tracks,
            descending: true,
            limit: 1,
          ),
        )).tracks.single.id,
        second.tracks.single.id,
      );
    },
  );

  test(
    'unreadable subfolder retains cached files until a complete scan',
    () async {
      final protected = Directory('${music.path}/protected');
      await createAudioFixture(protected, 'flac');
      final removed = await createAudioFixture(music, 'mp3');
      await repository.scan(addRoot: music.path);
      await removed.delete();
      await Process.run('chmod', ['000', protected.path]);
      try {
        final incomplete = await repository.scan();
        expect(incomplete.warnings, isNotEmpty);
        expect(incomplete.removed, 0);
        expect((await repository.status()).trackCount, 2);
      } finally {
        await Process.run('chmod', ['700', protected.path]);
      }
      final complete = await repository.scan();
      expect(complete.removed, 1);
      expect((await repository.status()).roots.single.error, isNull);
    },
  );

  test('read-only music files can be indexed without changes', () async {
    final file = await createAudioFixture(music, 'ogg');
    final before = sha256.convert(await file.readAsBytes());
    await Process.run('chmod', ['444', file.path]);
    final report = await repository.scan(addRoot: music.path);
    expect(report.updated, 1);
    expect(report.warnings, isEmpty);
    expect(sha256.convert(await file.readAsBytes()), before);
  });

  test(
    'worker scan sends progress while the caller event loop keeps running',
    () async {
      final fixture = await createAudioFixture(
        music,
        'mp3',
        name: 'source',
        withCover: false,
      );
      for (var i = 0; i < 200; i++) {
        await fixture.copy('${music.path}/copy-$i.mp3');
      }
      var ticks = 0;
      final progress = <ScanProgress>[];
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );
      try {
        final result = await repository.scan(
          addRoot: music.path,
          onProgress: progress.add,
        );
        expect(result.updated, 201);
        expect(ticks, greaterThan(1));
        expect(progress.last.visited, 201);
      } finally {
        timer.cancel();
      }
    },
  );
}
