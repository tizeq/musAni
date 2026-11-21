import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart' as sqlite_loader;
import 'package:sqlite3/sqlite3.dart';

import '../files/local_tracks.dart';
import '../metadata/tag_values.dart';
import 'metadata_reader.dart';
import 'models.dart';
import '../playlists/models.dart';

part '../playlists/playlist_database.dart';

// Each repository worker has its own isolate and SQLite loader.
final _catalogSqlite = _loadCatalogSqlite();

Sqlite3 _loadCatalogSqlite() {
  sqlite_loader.open.overrideFor(
    sqlite_loader.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );
  return sqlite3;
}

/// Synchronous SQLite/TagLib work belongs to the repository's worker isolates.
class LibraryDatabase {
  static const _schemaVersion = 5;

  LibraryDatabase(String databasePath, this.coverDirectory)
    : _db = _catalogSqlite.open(databasePath) {
    _db.execute('PRAGMA foreign_keys = ON');
    _db.execute('PRAGMA busy_timeout = 5000');
    _db.execute('PRAGMA journal_mode = WAL');
    try {
      var version = _db.select('PRAGMA user_version').first.values.first as int;
      if (version > _schemaVersion)
        throw StateError('Каталог создан более новой версией musAni');
      if (version < _schemaVersion) {
        _db.execute('BEGIN IMMEDIATE');
        try {
          // Another worker may have migrated while this connection waited.
          version = _db.select('PRAGMA user_version').first.values.first as int;
          if (version > _schemaVersion)
            throw StateError('Каталог создан более новой версией musAni');
          if (version == 0) {
            _db.execute('''
      CREATE TABLE IF NOT EXISTS roots (
        id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE,
        last_scan INTEGER, error TEXT
      );
      CREATE TABLE IF NOT EXISTS tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE,
        size INTEGER NOT NULL, modified_us INTEGER NOT NULL, changed_us INTEGER NOT NULL,
        title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT NOT NULL,
        album_artist TEXT NOT NULL, album_id TEXT NOT NULL,
        year INTEGER NOT NULL, genre TEXT NOT NULL,
        track_number INTEGER NOT NULL, disc_number INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL, cover_key TEXT, warning TEXT,
        properties TEXT NOT NULL, album_tagged INTEGER NOT NULL, search_text TEXT NOT NULL,
        title_sort TEXT NOT NULL, artist_sort TEXT NOT NULL,
        album_sort TEXT NOT NULL, album_artist_sort TEXT NOT NULL, added_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS track_roots (
        root_id INTEGER NOT NULL REFERENCES roots(id) ON DELETE CASCADE,
        track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        PRIMARY KEY(root_id, track_id)
      );
      CREATE TABLE IF NOT EXISTS track_artists (
        track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        artist_key TEXT NOT NULL, name TEXT NOT NULL,
        PRIMARY KEY(track_id, artist_key)
      );
      CREATE INDEX IF NOT EXISTS tracks_album ON tracks(album_id);
      CREATE INDEX IF NOT EXISTS tracks_title ON tracks(title_sort);
      CREATE INDEX IF NOT EXISTS track_artists_key ON track_artists(artist_key);
      PRAGMA user_version = 1;
    ''');
            version = 1;
          }
          if (version == 1) {
            _migrateArtistsAndAlbums();
            version = 2;
          }
          if (version == 2) {
            _createPlaylists();
            version = 3;
          }
          if (version == 3) {
            _createPlaylistArtwork();
            version = 4;
          }
          if (version == 4) _addPlaylistAlbumFlag();
          _db.execute('COMMIT');
        } catch (_) {
          _db.execute('ROLLBACK');
          rethrow;
        }
      }
    } catch (_) {
      _db.dispose();
      rethrow;
    }
  }

  final Database _db;
  final String coverDirectory;
  void close() => _db.dispose();

  LibraryStatus status() => LibraryStatus(
    roots: [
      for (final row in _db.select('SELECT * FROM roots ORDER BY path'))
        LibraryRoot(
          row['id'] as int,
          row['path'] as String,
          row['last_scan'] as int?,
          row['error'] as String?,
        ),
    ],
    trackCount: _count('SELECT COUNT(*) FROM tracks'),
    albumCount: _count(
      "SELECT COUNT(DISTINCT NULLIF(album_id,'')) FROM tracks WHERE album_tagged=1",
    ),
    artistCount: _count('SELECT COUNT(DISTINCT artist_key) FROM track_artists'),
  );

  int _count(String sql, [List<Object?> parameters = const []]) =>
      _db.select(sql, parameters).first.values.first as int;

  void removeRoot(int id) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute('DELETE FROM roots WHERE id = ?', [id]);
      _pruneOrphans();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  int _pruneOrphans() {
    _db.execute(
      'DELETE FROM tracks WHERE NOT EXISTS '
      '(SELECT 1 FROM track_roots r WHERE r.track_id = tracks.id)',
    );
    return _db.updatedRows;
  }

  Future<ScanReport> scan({
    String? addRoot,
    MetadataReader? reader,
    void Function(ScanProgress)? onProgress,
  }) async {
    reader ??= TagLibMetadataReader();
    if (addRoot != null) {
      final canonical = await Directory(addRoot).resolveSymbolicLinks();
      if (!await Directory(canonical).exists())
        throw FileSystemException('Папка недоступна', canonical);
      _db.execute('INSERT OR IGNORE INTO roots(path) VALUES (?)', [canonical]);
      addRoot = canonical;
    }
    var visited = 0;
    var updated = 0;
    var unchanged = 0;
    var removed = 0;
    final warnings = <String>[];
    final stopwatch = Stopwatch()..start();
    var lastProgress = -150;
    void progress(String path, {bool force = false}) {
      if (force || stopwatch.elapsedMilliseconds - lastProgress >= 150) {
        onProgress?.call(ScanProgress(visited, updated, unchanged, path));
        lastProgress = stopwatch.elapsedMilliseconds;
      }
    }

    void warn(String message) {
      if (warnings.length < 50) warnings.add(message);
    }

    final roots = _db.select(
      'SELECT * FROM roots${addRoot == null ? '' : ' WHERE path = ?'}',
      addRoot == null ? [] : [addRoot],
    );
    _db.execute(
      'CREATE TEMP TABLE IF NOT EXISTS seen (id INTEGER PRIMARY KEY)',
    );
    for (final root in roots) {
      final rootId = root['id'] as int;
      final path = root['path'] as String;
      progress(path, force: true);
      var complete = true;
      String? rootError;
      _db.execute('BEGIN IMMEDIATE');
      try {
        _db.execute('DELETE FROM seen');
        try {
          await for (final entity in Directory(
            path,
          ).list(recursive: true, followLinks: false)) {
            progress(entity.path);
            if (p
                .split(entity.path)
                .any((part) => part.startsWith('.musani-edit-')))
              continue;
            // Directory symlinks are not followed, preventing loops and accidental
            // scans outside the chosen tree. Canonical roots deduplicate aliases.
            if (entity is! File ||
                !LocalTracks.extensions.contains(
                  p.extension(entity.path).replaceFirst('.', '').toLowerCase(),
                ))
              continue;
            visited++;
            try {
              final canonical = await entity.resolveSymbolicLinks();
              var before = await File(canonical).stat();
              if (before.type != FileSystemEntityType.file)
                throw FileSystemException(
                  'Файл исчез во время сканирования',
                  canonical,
                );
              final rows = _db.select(
                'SELECT id,size,modified_us,changed_us,cover_key FROM tracks WHERE path = ?',
                [canonical],
              );
              final old = rows.firstOrNull;
              final coverKey = old?['cover_key'] as String?;
              int trackId;
              if (old != null &&
                  old['size'] == before.size &&
                  old['modified_us'] ==
                      before.modified.microsecondsSinceEpoch &&
                  old['changed_us'] == before.changed.microsecondsSinceEpoch &&
                  (coverKey == null ||
                      File(p.join(coverDirectory, '$coverKey.art'))
                          .existsSync())) {
                unchanged++;
                trackId = old['id'] as int;
              } else {
                final readable = await File(canonical)
                    .open(mode: FileMode.read);
                await readable.close();
                var metadata = reader.read(canonical, coverDirectory);
                var after = await File(canonical).stat();
                if (!_sameRevision(before, after)) {
                  before = after;
                  metadata = reader.read(canonical, coverDirectory);
                  after = await File(canonical).stat();
                  if (!_sameRevision(before, after))
                    throw FileSystemException(
                      'Файл изменяется во время чтения; повторите обновление',
                      canonical,
                    );
                }
                trackId = _upsert(canonical, metadata, after);
                updated++;
                if (metadata.warning != null)
                  warn('${p.basename(canonical)}: ${metadata.warning}');
              }
              _db.execute('INSERT OR IGNORE INTO seen(id) VALUES (?)', [
                trackId,
              ]);
              _db.execute(
                'INSERT OR IGNORE INTO track_roots(root_id,track_id) VALUES (?,?)',
                [rootId, trackId],
              );
            } on FileSystemException catch (error) {
              complete = false;
              rootError = 'Не все файлы доступны: $error';
              warn(rootError);
            }
          }
        } on FileSystemException catch (error) {
          complete = false;
          rootError = 'Папка недоступна или прочитана не полностью: $error';
          warn(rootError);
        }
        if (complete) {
          _db.execute(
            'DELETE FROM track_roots WHERE root_id = ? AND track_id NOT IN (SELECT id FROM seen)',
            [rootId],
          );
          removed += _pruneOrphans();
        }
        _db.execute('UPDATE roots SET last_scan = ?, error = ? WHERE id = ?', [
          DateTime.now().millisecondsSinceEpoch,
          rootError,
          rootId,
        ]);
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }
    progress('', force: true);
    return ScanReport(
      visited: visited,
      updated: updated,
      unchanged: unchanged,
      removed: removed,
      warnings: warnings,
    );
  }

  bool _sameRevision(FileStat a, FileStat b) =>
      b.type == FileSystemEntityType.file &&
      a.size == b.size &&
      a.modified == b.modified &&
      a.changed == b.changed;

  String? _albumId(String path, TrackMetadata metadata) {
    if (!metadata.albumTagged || metadata.album.trim().isEmpty) return null;
    final albumArtists = artistValues(
      metadata.properties['ALBUMARTIST'] ?? [metadata.albumArtist],
    );
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              metadata.album.trim().toLowerCase(),
              albumArtists.map((value) => value.toLowerCase()).toList(),
              // No declared album artist: do not guess from guests/track credits or
              // merge unrelated same-title albums across different directories.
              if (albumArtists.isEmpty) p.dirname(path),
            ]),
          ),
        )
        .toString();
  }

  void _writeArtists(int id, List<String> artists) {
    _db.execute('DELETE FROM track_artists WHERE track_id=?', [id]);
    for (final artist in artistValues(artists)) {
      _db.execute(
        'INSERT INTO track_artists(track_id,artist_key,name) VALUES (?,?,?)',
        [id, artist.toLowerCase(), artist],
      );
    }
  }

  /// v1 retained the complete tag property map, so migration also works with an
  /// offline music drive. Preserve file revisions, roots, IDs and added_at.
  void _migrateArtistsAndAlbums() {
    for (final row in _db.select('SELECT * FROM tracks')) {
      final properties = _properties(row['properties'] as String);
      final existing = _db.select(
        'SELECT name FROM track_artists WHERE track_id=? ORDER BY rowid',
        [row['id']],
      );
      final artists =
          properties.containsKey('ARTIST') || properties.containsKey('ARTISTS')
          ? trackArtistValues(properties)
          : artistValues(existing.map((artist) => artist['name'] as String));
      if (artists.isEmpty) artists.add('Неизвестный исполнитель');
      final albumTagged = row['album_tagged'] == 1;
      final album = albumTagged ? (row['album'] as String).trim() : '';
      final metadata = TrackMetadata(
        title: row['title'] as String,
        artists: artists,
        album: album,
        albumArtist: albumArtistValue(properties),
        albumTagged: albumTagged && album.isNotEmpty,
        properties: properties,
      );
      _db.execute(
        """
        UPDATE tracks SET artist=?,artist_sort=?,album=?,album_sort=?,album_artist=?,
          album_artist_sort=?,album_id=?,album_tagged=?,search_text=? WHERE id=?
      """,
        [
          metadata.artist,
          metadata.artist.toLowerCase(),
          album,
          album.toLowerCase(),
          metadata.albumArtist,
          metadata.albumArtist.toLowerCase(),
          _albumId(row['path'] as String, metadata) ?? '',
          metadata.albumTagged ? 1 : 0,
          '${metadata.title} ${metadata.artist} $album ${metadata.albumArtist} ${row['genre']} ${row['year']}'
              .toLowerCase(),
          row['id'],
        ],
      );
      _writeArtists(row['id'] as int, artists);
    }
    _db.execute('PRAGMA user_version=2');
  }

  Map<String, List<String>> _properties(String json) =>
      (jsonDecode(json) as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as List<dynamic>).cast<String>()),
      );

  int _upsert(String path, TrackMetadata metadata, FileStat stat) {
    final albumId = _albumId(path, metadata);
    _db.execute(
      '''
      INSERT INTO tracks(path,size,modified_us,changed_us,title,artist,album,album_artist,
        album_id,year,genre,track_number,disc_number,duration_ms,cover_key,warning,
        properties,album_tagged,search_text,title_sort,artist_sort,album_sort,album_artist_sort,added_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(path) DO UPDATE SET size=excluded.size,modified_us=excluded.modified_us,
        changed_us=excluded.changed_us,title=excluded.title,artist=excluded.artist,
        album=excluded.album,album_artist=excluded.album_artist,album_id=excluded.album_id,
        year=excluded.year,genre=excluded.genre,track_number=excluded.track_number,
        disc_number=excluded.disc_number,duration_ms=excluded.duration_ms,cover_key=excluded.cover_key,
        warning=excluded.warning,properties=excluded.properties,album_tagged=excluded.album_tagged,search_text=excluded.search_text,
        title_sort=excluded.title_sort,artist_sort=excluded.artist_sort,album_sort=excluded.album_sort,album_artist_sort=excluded.album_artist_sort
    ''',
      [
        path,
        stat.size,
        stat.modified.microsecondsSinceEpoch,
        stat.changed.microsecondsSinceEpoch,
        metadata.title,
        metadata.artist,
        metadata.album,
        metadata.albumArtist,
        albumId ?? '', // v1's NOT NULL column; exposed as null in the model.
        metadata.year,
        metadata.genre,
        metadata.trackNumber,
        metadata.discNumber,
        metadata.durationMs,
        metadata.coverKey,
        metadata.warning,
        jsonEncode(metadata.properties),
        metadata.albumTagged ? 1 : 0,
        '${metadata.title} ${metadata.artist} ${metadata.album} ${metadata.albumArtist} ${metadata.genre} ${metadata.year}'
            .toLowerCase(),
        metadata.title.toLowerCase(),
        metadata.artist.toLowerCase(),
        metadata.album.toLowerCase(),
        metadata.albumArtist.toLowerCase(),
        DateTime.now().microsecondsSinceEpoch,
      ],
    );
    final id = _count('SELECT id FROM tracks WHERE path = ?', [path]);
    _writeArtists(id, metadata.artists);
    _updatePlaylistSnapshots(path, metadata, id);
    return id;
  }

  void _updatePlaylistSnapshots(String path, TrackMetadata metadata, int? id) {
    // Playlist membership survives catalog pruning; keep its fallback snapshot
    // current and reattach returning paths without changing order or identity.
    _db.execute(
      '''
      UPDATE playlist_entries SET track_id=?,title=?,artists=?,duration_ms=?,cover_key=?
      WHERE deleted_at IS NULL AND (track_id=? OR (track_id IS NULL AND path=?))
    ''',
      [
        id,
        metadata.title,
        jsonEncode(metadata.artists),
        metadata.durationMs,
        metadata.coverKey,
        id,
        path,
      ],
    );
  }

  (String, List<Object?>) _filter(LibraryQuery query) {
    final clauses = <String>['1=1'];
    final parameters = <Object?>[];
    if (query.search.trim().isNotEmpty) {
      clauses.add("t.search_text LIKE ? ESCAPE '\\'");
      final search = query.search
          .trim()
          .toLowerCase()
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      parameters.add('%$search%');
    }
    if (query.artistId != null) {
      clauses.add(
        'EXISTS (SELECT 1 FROM track_artists a WHERE a.track_id=t.id AND a.artist_key=?)',
      );
      parameters.add(query.artistId);
    }
    if (query.albumId != null) {
      clauses.add('t.album_id = ?');
      parameters.add(query.albumId);
    }
    return (clauses.join(' AND '), parameters);
  }

  String _trackOrder(LibraryQuery query) {
    final sort = switch (query.sort) {
      LibrarySort.title => 't.title_sort',
      LibrarySort.artist => 't.artist_sort',
      LibrarySort.year => 't.year',
      LibrarySort.added => 't.added_at',
    };
    final direction = query.descending ? 'DESC' : 'ASC';
    return '$sort $direction, t.album_sort, t.disc_number, t.track_number, t.id';
  }

  // The outer query supplies the tracks row as `t`.
  static const _trackArtistsJson = '''
    (SELECT json_group_array(name) FROM (
      SELECT name FROM track_artists WHERE track_id=t.id ORDER BY rowid
    ))
  ''';

  /// A single SQLite snapshot of the full result, regardless of the UI page.
  List<LocalTrack> playbackTracks(LibraryQuery query) {
    final (where, args) = _filter(query);
    final statement = _db.prepare('''
      SELECT t.path, t.title, $_trackArtistsJson AS artists
      FROM tracks t WHERE $where ORDER BY ${_trackOrder(query)}
    ''');
    try {
      final rows = statement.selectCursor(args);
      final tracks = <LocalTrack>[];
      while (rows.moveNext()) {
        final row = rows.current;
        tracks.add(
          LocalTrack(
            Uri.file(row['path'] as String),
            row['title'] as String,
            artists: List.unmodifiable(
              (jsonDecode(row['artists'] as String) as List).cast<String>(),
            ),
          ),
        );
      }
      return tracks;
    } finally {
      statement.dispose();
    }
  }

  LibraryResult query(LibraryQuery query) {
    final (where, args) = _filter(query);
    final direction = query.descending ? 'DESC' : 'ASC';
    final page = [
      ...args,
      query.limit.clamp(1, 500),
      query.offset.clamp(0, 1 << 31),
    ];
    switch (query.view) {
      case LibraryView.tracks:
        return LibraryResult(
          total: _count('SELECT COUNT(*) FROM tracks t WHERE $where', args),
          tracks: [
            for (final row in _db.select(
              'SELECT t.* FROM tracks t WHERE $where ORDER BY ${_trackOrder(query)} LIMIT ? OFFSET ?',
              page,
            ))
              _track(row),
          ],
        );
      case LibraryView.albums:
        final sort = switch (query.sort) {
          LibrarySort.title => 'album_sort',
          LibrarySort.artist => 'artist_sort',
          LibrarySort.year => 'year',
          LibrarySort.added => 'added_at',
        };
        return LibraryResult(
          total: _count(
            "SELECT COUNT(DISTINCT album_id) FROM tracks t WHERE $where AND t.album_tagged=1 AND t.album_id<>''",
            args,
          ),
          albums: [
            for (final row in _db.select('''
            SELECT album_id,MIN(album) title,MIN(album_artist) artist,MAX(year) year,
              COUNT(*) track_count,SUM(duration_ms) duration_ms,MIN(cover_key) cover_key,
              MIN(album_sort) album_sort,MIN(album_artist_sort) artist_sort,MAX(added_at) added_at
            FROM tracks WHERE album_tagged=1 AND album_id<>'' AND album_id IN (SELECT album_id FROM tracks t WHERE $where)
            GROUP BY album_id ORDER BY $sort $direction, album_id LIMIT ? OFFSET ?
          ''', page))
              LibraryAlbum(
                id: row['album_id'] as String,
                title: row['title'] as String,
                artist: row['artist'] as String,
                year: row['year'] as int,
                trackCount: row['track_count'] as int,
                durationMs: row['duration_ms'] as int,
                coverKey: row['cover_key'] as String?,
              ),
          ],
        );
      case LibraryView.artists:
        final sort = switch (query.sort) {
          LibrarySort.title || LibrarySort.artist => 'a.artist_key',
          LibrarySort.year => 'MAX(t.year)',
          LibrarySort.added => 'MAX(t.added_at)',
        };
        return LibraryResult(
          total: _count(
            'SELECT COUNT(DISTINCT a.artist_key) FROM track_artists a JOIN tracks t ON t.id=a.track_id WHERE $where',
            args,
          ),
          artists: [
            for (final row in _db.select('''
            SELECT a.artist_key,MIN(a.name) name,COUNT(*) track_count,
              COUNT(DISTINCT CASE WHEN t.album_tagged=1 THEN NULLIF(t.album_id,'') END) album_count,MIN(t.cover_key) cover_key
            FROM track_artists a JOIN tracks t ON t.id=a.track_id WHERE $where
            GROUP BY a.artist_key ORDER BY $sort $direction, a.artist_key LIMIT ? OFFSET ?
          ''', page))
              LibraryArtist(
                id: row['artist_key'] as String,
                name: row['name'] as String,
                trackCount: row['track_count'] as int,
                albumCount: row['album_count'] as int,
                coverKey: row['cover_key'] as String?,
              ),
          ],
        );
    }
  }

  List<LibraryTrack> albumTracks(String albumId) => [
    for (final row in _db.select(
      '''
    SELECT * FROM tracks WHERE album_id=? AND album_tagged=1 AND album_id<>''
    ORDER BY disc_number,CASE WHEN track_number=0 THEN 2147483647 ELSE track_number END,title_sort,id
  ''',
      [albumId],
    ))
      _track(row),
  ];

  LibraryTrack? track(int id) {
    final rows = _db.select('SELECT * FROM tracks WHERE id=?', [id]);
    return rows.isEmpty ? null : _track(rows.first);
  }

  LibraryTrack? trackByPath(String path) {
    final rows = _db.select('SELECT * FROM tracks WHERE path=?', [path]);
    return rows.isEmpty ? null : _track(rows.first);
  }

  TrackMetadata reindexTrack(String path) {
    final rows = _db.select('SELECT id FROM tracks WHERE path=?', [path]);
    final before = File(path).statSync();
    final metadata = TagLibMetadataReader().read(path, coverDirectory);
    final after = File(path).statSync();
    if (!_sameRevision(before, after))
      throw StateError('Файл изменился при обновлении каталога');
    if (metadata.warning != null) throw StateError(metadata.warning!);
    _db.execute('BEGIN IMMEDIATE');
    try {
      if (rows.isEmpty) {
        // Playlist/queue files need fresh snapshots without becoming catalog
        // orphans (which a later scan would prune).
        _updatePlaylistSnapshots(path, metadata, null);
      } else {
        _upsert(path, metadata, after);
      }
      _db.execute('COMMIT');
      return metadata;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  LibraryTrack _track(Row row) {
    final properties = _properties(row['properties'] as String);
    final artists = _db.select(
      'SELECT name FROM track_artists WHERE track_id=? ORDER BY rowid',
      [row['id']],
    );
    return LibraryTrack(
      id: row['id'] as int,
      path: row['path'] as String,
      albumId: (row['album_id'] as String).isEmpty
          ? null
          : row['album_id'] as String,
      size: row['size'] as int,
      modifiedUs: row['modified_us'] as int,
      changedUs: row['changed_us'] as int,
      metadata: TrackMetadata(
        title: row['title'] as String,
        artists: [for (final artist in artists) artist['name'] as String],
        album: row['album'] as String,
        albumArtist: row['album_artist'] as String,
        year: row['year'] as int,
        genre: row['genre'] as String,
        trackNumber: row['track_number'] as int,
        discNumber: row['disc_number'] as int,
        durationMs: row['duration_ms'] as int,
        coverKey: row['cover_key'] as String?,
        warning: row['warning'] as String?,
        properties: properties,
        albumTagged: row['album_tagged'] == 1,
      ),
    );
  }
}
