part of '../library/library_database.dart';

extension PlaylistDatabase on LibraryDatabase {
  void _createPlaylists() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, revision INTEGER NOT NULL,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER
      );
      CREATE TABLE IF NOT EXISTS playlist_entries (
        id TEXT PRIMARY KEY, playlist_id TEXT NOT NULL REFERENCES playlists(id),
        track_id INTEGER REFERENCES tracks(id) ON DELETE SET NULL,
        path TEXT NOT NULL, title TEXT NOT NULL, artists TEXT NOT NULL,
        duration_ms INTEGER NOT NULL, cover_key TEXT, position INTEGER NOT NULL,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER
      );
      CREATE INDEX IF NOT EXISTS playlist_entries_order ON playlist_entries(playlist_id,deleted_at,position);
      CREATE INDEX IF NOT EXISTS playlist_entries_track ON playlist_entries(track_id);
      CREATE INDEX IF NOT EXISTS playlist_entries_path ON playlist_entries(path);
      PRAGMA user_version=3;
    ''');
  }

  void _createPlaylistArtwork() => _db.execute('''
    CREATE TABLE IF NOT EXISTS playlist_artwork (
      playlist_id TEXT PRIMARY KEY REFERENCES playlists(id) ON DELETE CASCADE,
      image BLOB NOT NULL
    );
    PRAGMA user_version=4;
  ''');

  void _addPlaylistAlbumFlag() => _db.execute('''
    ALTER TABLE playlists ADD COLUMN is_album INTEGER NOT NULL DEFAULT 0
      CHECK (is_album IN (0, 1));
    PRAGMA user_version=5;
  ''');

  PlaylistArtwork playlistArtwork(String id) {
    final image =
        _db.select('SELECT image FROM playlist_artwork WHERE playlist_id=?', [
              id,
            ]).firstOrNull?['image']
            as Uint8List?;
    if (image != null) return PlaylistArtwork(image: image);
    return PlaylistArtwork(
      trackCovers: [
        for (final row in _db.select(
          '''
        SELECT COALESCE(t.cover_key, e.cover_key) AS cover
        FROM playlist_entries e LEFT JOIN tracks t ON t.id=e.track_id
        WHERE e.playlist_id=? AND e.deleted_at IS NULL
        GROUP BY cover HAVING cover IS NOT NULL
        ORDER BY MIN(e.position), cover LIMIT 4
      ''',
          [id],
        ))
          row['cover'] as String,
      ],
    );
  }

  void setPlaylistArtwork(String id, int revision, Uint8List? image) {
    if (image != null && (image.isEmpty || image.length > 1024 * 1024)) {
      throw const FormatException('Обложка должна занимать не больше 1 МБ');
    }
    _changePlaylist(id, revision, (_) {
      if (image == null) {
        _db.execute('DELETE FROM playlist_artwork WHERE playlist_id=?', [id]);
      } else {
        _db.execute(
          '''
          INSERT INTO playlist_artwork (playlist_id,image) VALUES (?,?)
          ON CONFLICT (playlist_id) DO UPDATE SET image=excluded.image
        ''',
          [id, image],
        );
      }
    });
  }

  String _newPlaylistId() =>
      _db.select('SELECT lower(hex(randomblob(16))) id').single['id'] as String;
  int _playlistTime() => DateTime.now().millisecondsSinceEpoch;
  String _playlistName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.length > 200 || name.contains('\u0000')) {
      throw const FormatException('Название плейлиста: от 1 до 200 символов');
    }
    return name;
  }

  List<UserPlaylist> playlists({String? id}) => [
    for (final row in _db.select(
      '''
      SELECT p.*, COUNT(e.id) track_count,
        COALESCE(SUM(COALESCE(t.duration_ms,e.duration_ms)),0) duration_ms
      FROM playlists p LEFT JOIN playlist_entries e ON e.playlist_id=p.id AND e.deleted_at IS NULL
      LEFT JOIN tracks t ON t.id=e.track_id WHERE p.deleted_at IS NULL
        ${id == null ? '' : 'AND p.id = ?'}
      GROUP BY p.id ORDER BY p.updated_at DESC,p.id
    ''',
      [if (id != null) id],
    ))
      _playlist(row),
  ];

  UserPlaylist _playlist(Row row) => UserPlaylist(
    id: row['id'] as String,
    name: row['name'] as String,
    revision: row['revision'] as int,
    updatedMs: row['updated_at'] as int,
    trackCount: row['track_count'] as int,
    durationMs: row['duration_ms'] as int,
    isAlbum: row['is_album'] == 1,
  );

  UserPlaylist createPlaylist(String name) {
    name = _playlistName(name);
    final id = _newPlaylistId();
    final now = _playlistTime();
    _db.execute(
      'INSERT INTO playlists(id,name,revision,created_at,updated_at) VALUES (?,?,0,?,?)',
      [id, name, now, now],
    );
    return playlists(id: id).single;
  }

  T _changePlaylist<T>(String id, int revision, T Function(int now) change) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final row = _db.select(
        'SELECT revision,updated_at FROM playlists WHERE id=? AND deleted_at IS NULL',
        [id],
      ).firstOrNull;
      if (row == null)
        throw StateError('Плейлист удалён или больше недоступен');
      if (row['revision'] != revision)
        throw StateError(
          'Плейлист изменился. Обновите страницу и повторите действие.',
        );
      final now = _playlistTime().clamp(
        (row['updated_at'] as int) + 1,
        1 << 62,
      );
      final result = change(now);
      _db.execute(
        'UPDATE playlists SET revision=revision+1,updated_at=? WHERE id=?',
        [now, id],
      );
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void updatePlaylistProperties(
    String id,
    int revision,
    String name, {
    bool? isAlbum,
  }) {
    final valid = _playlistName(name);
    _changePlaylist(
      id,
      revision,
      (_) => _db.execute(
        'UPDATE playlists SET name=?,is_album=COALESCE(?,is_album) WHERE id=?',
        [valid, isAlbum == null ? null : (isAlbum ? 1 : 0), id],
      ),
    );
  }

  void deletePlaylist(String id, int revision) =>
      _changePlaylist(id, revision, (now) {
        _db.execute('UPDATE playlists SET deleted_at=? WHERE id=?', [now, id]);
        _db.execute('DELETE FROM playlist_artwork WHERE playlist_id=?', [id]);
        _db.execute(
          'UPDATE playlist_entries SET deleted_at=?,updated_at=? WHERE playlist_id=? AND deleted_at IS NULL',
          [now, now, id],
        );
      });

  PlaylistTrackRef _playlistRef(PlaylistTrackRef ref) {
    final catalog = trackByPath(ref.path);
    if (catalog != null) return PlaylistTrackRef.fromLibrary(catalog);
    // Directly opened files may not be in the library. Read their duration and
    // labels once in this worker; an existing missing reference keeps its snapshot.
    if (ref.durationMs == 0 && File(ref.path).existsSync()) {
      final metadata = TagLibMetadataReader().read(ref.path, coverDirectory);
      if (metadata.durationMs > 0)
        return PlaylistTrackRef(
          path: ref.path,
          title: metadata.title,
          artists: metadata.artists,
          durationMs: metadata.durationMs,
          coverKey: metadata.coverKey,
        );
    }
    return PlaylistTrackRef(
      path: ref.path,
      title: ref.title,
      artists: ref.artists,
      durationMs: ref.durationMs,
      coverKey: ref.coverKey,
    );
  }

  void addPlaylistTracks(String id, int revision, List<PlaylistTrackRef> refs) {
    if (refs.isEmpty) throw ArgumentError('Не выбраны треки');
    _changePlaylist(id, revision, (now) {
      var position = _count(
        'SELECT COALESCE(MAX(position),-1)+1 FROM playlist_entries WHERE playlist_id=? AND deleted_at IS NULL',
        [id],
      );
      for (final input in refs) {
        if (!p.isAbsolute(input.path) ||
            !LocalTracks.extensions.contains(
              p.extension(input.path).replaceFirst('.', '').toLowerCase(),
            )) {
          throw const FormatException(
            'Нужен локальный аудиофайл поддерживаемого формата',
          );
        }
        final ref = _playlistRef(input);
        _db.execute(
          '''
          INSERT INTO playlist_entries(id,playlist_id,track_id,path,title,artists,duration_ms,cover_key,position,created_at,updated_at)
          VALUES (?,?,?,?,?,?,?,?,?,?,?)
        ''',
          [
            _newPlaylistId(),
            id,
            ref.trackId,
            ref.path,
            ref.title,
            jsonEncode(ref.artists),
            ref.durationMs,
            ref.coverKey,
            position++,
            now,
            now,
          ],
        );
      }
    });
  }

  PlaylistDetail playlistDetail(String id) {
    final playlist = playlists(id: id).singleOrNull;
    if (playlist == null)
      throw StateError('Плейлист удалён или больше недоступен');
    final entries = <PlaylistEntry>[];
    final checkedFiles = <String, (PlaylistFileState, String?)>{};
    for (final row in _db.select(
      '''
      SELECT e.id, e.position, COALESCE(t.id,e.track_id) track_id,
        COALESCE(t.path,e.path) path, COALESCE(t.title,e.title) title,
        COALESCE(t.duration_ms,e.duration_ms) duration_ms,
        CASE WHEN t.id IS NULL THEN e.cover_key ELSE t.cover_key END cover_key,
        CASE WHEN t.id IS NULL THEN e.artists ELSE ${LibraryDatabase._trackArtistsJson} END artists
      FROM playlist_entries e
      LEFT JOIN tracks t ON t.id=COALESCE(e.track_id, (SELECT id FROM tracks WHERE path=e.path))
      WHERE e.playlist_id=? AND e.deleted_at IS NULL ORDER BY e.position,e.id
      ''',
      [id],
    )) {
      final ref = PlaylistTrackRef(
        path: row['path'] as String,
        title: row['title'] as String,
        artists: (jsonDecode(row['artists'] as String) as List<dynamic>)
            .cast<String>(),
        durationMs: row['duration_ms'] as int,
        coverKey: row['cover_key'] as String?,
        trackId: row['track_id'] as int?,
      );
      final (state, error) = checkedFiles.putIfAbsent(
        ref.path,
        () => _checkPlaylistFile(ref.path),
      );
      entries.add(
        PlaylistEntry(
          id: row['id'] as String,
          position: row['position'] as int,
          track: ref,
          fileState: state,
          error: error,
        ),
      );
    }
    final current = _db.select(
      'SELECT revision FROM playlists WHERE id=? AND deleted_at IS NULL',
      [id],
    ).firstOrNull;
    if (current == null || current['revision'] != playlist.revision) {
      throw StateError(
        'Плейлист изменился во время загрузки. Обновите страницу.',
      );
    }
    return PlaylistDetail(playlist, entries);
  }

  (PlaylistFileState, String?) _checkPlaylistFile(String path) {
    // This query and the file checks run in the repository worker.
    final file = File(path);
    try {
      if (!file.existsSync())
        return (
          PlaylistFileState.missing,
          'Файл перемещён или недоступен. Укажите его новое расположение.',
        );
      file.openSync(mode: FileMode.read).closeSync();
      return (PlaylistFileState.available, null);
    } on FileSystemException {
      return (
        PlaylistFileState.unreadable,
        'Нет доступа к файлу. Проверьте права или восстановите ссылку.',
      );
    }
  }

  List<String> _playlistEntryIds(String id) => [
    for (final row in _db.select(
      'SELECT id FROM playlist_entries WHERE playlist_id=? AND deleted_at IS NULL ORDER BY position,id',
      [id],
    ))
      row['id'] as String,
  ];

  void _orderPlaylist(String id, List<String> entries, int now) {
    for (var index = 0; index < entries.length; index++) {
      _db.execute(
        'UPDATE playlist_entries SET position=?,updated_at=? WHERE id=? AND playlist_id=? AND deleted_at IS NULL AND position<>?',
        [index, now, entries[index], id, index],
      );
    }
  }

  void reorderPlaylist(String id, int revision, List<String> entries) =>
      _changePlaylist(id, revision, (now) {
        final actual = _playlistEntryIds(id).toSet();
        if (entries.length != actual.length ||
            entries.toSet().length != entries.length ||
            !actual.containsAll(entries)) {
          throw StateError(
            'Порядок устарел или содержит неверные записи. Обновите плейлист.',
          );
        }
        _orderPlaylist(id, entries, now);
      });

  void removePlaylistEntry(String id, int revision, String entryId) =>
      _changePlaylist(id, revision, (now) {
        final ids = _playlistEntryIds(id);
        if (!ids.remove(entryId))
          throw StateError('Запись больше не находится в плейлисте');
        _db.execute(
          'UPDATE playlist_entries SET deleted_at=?,updated_at=? WHERE id=? AND playlist_id=?',
          [now, now, entryId, id],
        );
        _orderPlaylist(id, ids, now);
      });

  Future<void> relinkPlaylistEntry(
    String id,
    int revision,
    String entryId,
    String path,
  ) async {
    // Resolve and validate before opening a write transaction; no file is modified.
    final canonical = await File(path).resolveSymbolicLinks();
    if (!LocalTracks.extensions.contains(
      p.extension(canonical).replaceFirst('.', '').toLowerCase(),
    )) {
      throw const FormatException('Выберите поддерживаемый аудиофайл');
    }
    final handle = await File(canonical).open(mode: FileMode.read);
    await handle.close();
    final before = await File(canonical).stat();
    final metadata = TagLibMetadataReader().read(canonical, coverDirectory);
    final after = await File(canonical).stat();
    if (metadata.durationMs <= 0 || !_sameRevision(before, after)) {
      throw const FormatException(
        'Не удалось проверить аудиофайл. Выберите исправный доступный файл.',
      );
    }
    final catalog = trackByPath(canonical);
    _changePlaylist(id, revision, (now) {
      if (!_playlistEntryIds(id).contains(entryId))
        throw StateError('Запись больше не находится в плейлисте');
      _db.execute(
        '''
        UPDATE playlist_entries SET path=?,track_id=?,title=?,artists=?,duration_ms=?,cover_key=?,updated_at=?
        WHERE id=? AND playlist_id=? AND deleted_at IS NULL
      ''',
        [
          canonical,
          catalog?.id,
          metadata.title,
          jsonEncode(metadata.artists),
          metadata.durationMs,
          metadata.coverKey,
          now,
          entryId,
          id,
        ],
      );
    });
  }
}
