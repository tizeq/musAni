import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/library/models.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/audio_fixtures.dart';
import 'support/catalog_fixture.dart';

void main() {
  late Directory dir;
  late Directory music;
  late LibraryRepository repo;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('musani-artist-library-');
    music = await Directory('${dir.path}/music').create();
    repo = LibraryRepository('${dir.path}/catalog');
  });
  tearDown(() => dir.delete(recursive: true));

  Future<File> fixture(
    String name, {
    String album = 'Same title',
    String albumArtist = 'Album owner',
    List<String> artists = const ['Tyler, The Creator', 'Guest'],
  }) async {
    await File('${music.path}/$name.flac').parent.create(recursive: true);
    final file = await createAudioFixture(
      music,
      'flac',
      name: name,
      album: album,
      albumArtist: albumArtist,
      withCover: false,
    );
    final tag = TagLibFile.open(file.path)!;
    try {
      expect(tag.setProperties(tag.properties..['ARTIST'] = artists), isEmpty);
      expect(tag.save(), isTrue);
    } finally {
      tag.close();
    }
    return file;
  }

  test('one file belongs to every track artist; album artist is independent and untagged tracks create no albums', () async {
    final file = await fixture('shared', album: '');
    await repo.scan(addRoot: music.path);
    final status = await repo.status();
    expect(status.trackCount, 1);
    expect(status.artistCount, 2);
    expect(status.albumCount, 0);
    expect((await repo.query(const LibraryQuery())).albums, isEmpty);
    final artists = (await repo.query(
      const LibraryQuery(view: LibraryView.artists),
    )).artists;
    expect(artists.map((artist) => artist.name), [
      'Guest',
      'Tyler, The Creator',
    ]);
    expect(artists.map((artist) => artist.trackCount), [1, 1]);
    expect(artists.map((artist) => artist.albumCount), [0, 0]);
    final ids = <int>{};
    for (final artist in artists) {
      final tracks = (await repo.query(
        LibraryQuery(view: LibraryView.tracks, artistId: artist.id),
      )).tracks;
      expect(tracks.single.path, file.path);
      expect(tracks.single.albumId, isNull);
      expect(tracks.single.metadata.album, '');
      expect(tracks.single.metadata.albumArtist, 'Album owner');
      ids.add(tracks.single.id);
      expect((await repo.query(LibraryQuery(artistId: artist.id))).total, 0);
    }
    expect(ids, hasLength(1));
    expect(await repo.albumTracks(''), isEmpty);
    expect(
      (await repo.query(
        const LibraryQuery(view: LibraryView.tracks, artistId: 'album owner'),
      )).total,
      0,
    );
  });

  test('album groups use album title and declared album artist, never track credits', () async {
    await fixture('main', artists: ['Main']);
    await fixture('guest', artists: ['Guest', 'Main']);
    await fixture('other', albumArtist: 'Different owner', artists: ['Main']);
    await fixture('untagged', album: '', artists: ['Main']);
    await repo.scan(addRoot: music.path);
    expect((await repo.status()).trackCount, 4);
    expect((await repo.status()).albumCount, 2);
    final albums = (await repo.query(const LibraryQuery())).albums;
    expect(albums.map((album) => album.artist).toSet(), {
      'Album owner',
      'Different owner',
    });
    final main = albums.singleWhere((album) => album.artist == 'Album owner');
    expect(main.trackCount, 2);
    expect(
      (await repo.albumTracks(main.id))
          .map((track) => track.metadata.artists)
          .toList(),
      containsAll([
        ['Main'],
        ['Guest', 'Main'],
      ]),
    );
    final guestAlbum = (await repo.query(const LibraryQuery(artistId: 'guest')))
        .albums
        .single;
    expect(guestAlbum.id, main.id);
    expect(
      guestAlbum.trackCount,
      2,
    ); // Whole album, not duplicate filtered subset.
    final artists = (await repo.query(
      const LibraryQuery(view: LibraryView.artists),
    )).artists;
    expect(
      artists.singleWhere((artist) => artist.name == 'Main').trackCount,
      4,
    );
    expect(
      artists.singleWhere((artist) => artist.name == 'Main').albumCount,
      2,
    );
  });

  test('missing album artist stays empty; same-folder guests group together and homonyms in other folders stay separate', () async {
    await fixture('a', albumArtist: '', artists: ['A']);
    await fixture('b', albumArtist: '', artists: ['B']);
    await fixture('nested/c', albumArtist: '', artists: ['A']);
    await repo.scan(addRoot: music.path);
    final albums = (await repo.query(const LibraryQuery())).albums;
    expect(albums, hasLength(2));
    expect(albums.map((album) => album.trackCount).toSet(), {1, 2});
    expect(albums.map((album) => album.artist).toSet(), {''});
    final rows = (await repo.query(
      const LibraryQuery(view: LibraryView.tracks),
    )).tracks;
    expect(rows.map((track) => track.metadata.albumArtist).toSet(), {''});
    // A literal album name "Без альбома" is still a real, explicit tag.
    await fixture('literal', album: 'Без альбома', albumArtist: 'Real owner');
    await repo.scan();
    expect(
      (await repo.query(const LibraryQuery(search: 'Без альбома')))
          .albums
          .single
          .title,
      'Без альбома',
    );
  });

  test('v1 migration is offline, transactional, idempotent and preserves original user data and audio', () async {
    await fixture(
      'a',
      albumArtist: '',
      artists: ['Tyler, The Creator', 'Guest'],
    );
    await fixture('b', albumArtist: '', artists: ['Other']);
    await fixture('c', album: '', albumArtist: 'Album owner');
    await repo.scan(addRoot: music.path);
    var db = sqlite3.open(repo.databasePath);
    // v1 and v2 keep the same physical tables. Recreate v1's derived values,
    // including split guest albums and its artificial untagged album.
    db.execute(
      "UPDATE tracks SET album_artist=artist,album_artist_sort=artist_sort,album_id='old-'||id,album=CASE WHEN album_tagged=0 THEN 'Без альбома' ELSE album END",
    );
    db.execute(
      "UPDATE roots SET last_scan=123456,error='preserve root warning'",
    );
    db.execute("UPDATE tracks SET warning='preserve track warning'");
    final sharedId = db
        .select("SELECT id FROM tracks WHERE path LIKE '%/a.flac'")
        .single['id'];
    db.execute('DELETE FROM track_artists WHERE track_id=?', [sharedId]);
    db.execute(
      "INSERT INTO track_artists(track_id,artist_key,name) VALUES (?,'tyler','Tyler'),(?,'the creator','The Creator')",
      [sharedId, sharedId],
    );
    dropV6AlbumStorage(db);
    db.execute('DROP TABLE playlist_artwork');
    db.execute('DROP TABLE playlist_entries');
    db.execute('DROP TABLE playlists');
    db.execute('PRAGMA user_version=1');
    final beforeRows = db
        .select(
          'SELECT id,path,size,modified_us,changed_us,title,year,genre,track_number,disc_number,duration_ms,cover_key,warning,properties,added_at FROM tracks ORDER BY id',
        )
        .map((row) => Map<String, Object?>.from(row))
        .toList();
    final beforeRoots = db
        .select('SELECT * FROM roots')
        .map((row) => Map<String, Object?>.from(row))
        .toList();
    final beforeLinks = db
        .select('SELECT * FROM track_roots ORDER BY track_id')
        .map((row) => Map<String, Object?>.from(row))
        .toList();
    db.dispose();
    final hashes = <String, String>{};
    for (final file in music.listSync(recursive: true).whereType<File>()) {
      hashes[file.path.substring(music.path.length)] = sha256
          .convert(await file.readAsBytes())
          .toString();
    }
    final offline = await music.rename('${dir.path}/offline');
    final migrated = LibraryRepository(repo.directory);
    // Several worker connections race to initialize the same legacy catalog.
    final statuses = await Future.wait([
      migrated.status(),
      LibraryRepository(repo.directory).status(),
    ]);
    for (final status in statuses) {
      expect(status.trackCount, 3);
      expect(status.albumCount, 1);
      expect(status.artistCount, 3);
      expect(status.roots.single.error, 'preserve root warning');
    }
    final tracks = (await migrated.query(
      const LibraryQuery(view: LibraryView.tracks),
    )).tracks;
    expect(
      tracks
          .singleWhere((track) => track.path.endsWith('/a.flac'))
          .metadata
          .artists,
      ['Tyler, The Creator', 'Guest'],
    );
    expect(
      tracks.singleWhere((track) => track.path.endsWith('/c.flac')).albumId,
      isNull,
    );
    expect(
      (await migrated.query(const LibraryQuery())).albums.single.trackCount,
      2,
    );
    db = sqlite3.open(repo.databasePath);
    try {
      expect(db.select('PRAGMA user_version').single.values.single, 6);
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      expect(
        db
            .select(
              'SELECT id,path,size,modified_us,changed_us,title,year,genre,track_number,disc_number,duration_ms,cover_key,warning,properties,added_at FROM tracks ORDER BY id',
            )
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
        beforeRows,
      );
      expect(
        db
            .select('SELECT * FROM roots')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
        beforeRoots,
      );
      expect(
        db
            .select('SELECT * FROM track_roots ORDER BY track_id')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
        beforeLinks,
      );
    } finally {
      db.dispose();
    }
    await LibraryRepository(repo.directory).status();
    for (final entry in hashes.entries) {
      expect(
        sha256
            .convert(await File('${offline.path}${entry.key}').readAsBytes())
            .toString(),
        entry.value,
      );
    }
    await offline.rename(music.path);
    final scan = await migrated.scan();
    expect(scan.updated, 0);
    expect(scan.unchanged, 3);
    final unchanged = (await migrated.query(
      const LibraryQuery(view: LibraryView.tracks),
    )).tracks;
    expect(
      unchanged.map((track) => track.id).toSet(),
      tracks.map((track) => track.id).toSet(),
    );
    await fixture('new');
    await migrated.scan();
    expect(
      (await migrated.query(const LibraryQuery(view: LibraryView.tracks)))
          .tracks
          .lastWhere((track) => track.path.endsWith('/new.flac'))
          .id,
      greaterThan(
        tracks.map((track) => track.id).reduce((a, b) => a > b ? a : b),
      ),
    );
  });

  test('failed migration rolls back all derived changes and keeps v1 data', () async {
    await fixture('a');
    await fixture('b');
    await repo.scan(addRoot: music.path);
    var db = sqlite3.open(repo.databasePath);
    db.execute(
      "UPDATE tracks SET album_id='legacy-group',album_artist='legacy-artist'",
    );
    db.execute(
      "UPDATE tracks SET properties='broken JSON' WHERE id=(SELECT MAX(id) FROM tracks)",
    );
    db.execute('PRAGMA user_version=1');
    final before = db
        .select('SELECT * FROM tracks ORDER BY id')
        .map((row) => Map<String, Object?>.from(row))
        .toList();
    final artists = db
        .select('SELECT * FROM track_artists ORDER BY track_id,artist_key')
        .map((row) => Map<String, Object?>.from(row))
        .toList();
    db.dispose();
    await expectLater(
      LibraryRepository(repo.directory).status(),
      throwsFormatException,
    );
    db = sqlite3.open(repo.databasePath);
    try {
      expect(db.select('PRAGMA user_version').single.values.single, 1);
      expect(
        db
            .select('SELECT * FROM tracks ORDER BY id')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
        before,
      );
      expect(
        db
            .select('SELECT * FROM track_artists ORDER BY track_id,artist_key')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
        artists,
      );
    } finally {
      db.dispose();
    }
  });
}
