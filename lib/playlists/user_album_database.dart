part of '../library/library_database.dart';

extension UserAlbumDatabase on LibraryDatabase {
  int get _userAlbumCount => _count(
    'SELECT COUNT(*) FROM playlists WHERE is_album=1 AND deleted_at IS NULL',
  );

  void _createUserAlbums() {
    _db.execute('''
      ALTER TABLE playlists ADD COLUMN album_artist TEXT NOT NULL DEFAULT '';
      ALTER TABLE playlists ADD COLUMN album_year INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE playlists ADD COLUMN album_genre TEXT NOT NULL DEFAULT '';
      ALTER TABLE playlists ADD COLUMN album_disc INTEGER NOT NULL DEFAULT 1;
      ALTER TABLE playlists ADD COLUMN album_sort TEXT NOT NULL DEFAULT '';
      ALTER TABLE playlists ADD COLUMN album_artist_sort TEXT NOT NULL DEFAULT '';
      ALTER TABLE playlists ADD COLUMN album_search TEXT NOT NULL DEFAULT '';
      ALTER TABLE playlists ADD COLUMN album_cover_key TEXT;
      ALTER TABLE playlist_entries ADD COLUMN album_disc INTEGER;
      CREATE INDEX playlists_user_albums ON playlists(id) WHERE is_album=1 AND deleted_at IS NULL;
      CREATE TABLE user_album_members (
        path TEXT PRIMARY KEY,
        playlist_id TEXT NOT NULL REFERENCES playlists(id),
        entry_id TEXT NOT NULL REFERENCES playlist_entries(id),
        disc INTEGER NOT NULL,
        number INTEGER NOT NULL
      );
      CREATE INDEX user_album_members_album ON user_album_members(playlist_id);
      CREATE VIEW user_album_indexed_tracks AS
      SELECT t.id,t.path,t.size,t.modified_us,t.changed_us,t.title,t.artist,
        COALESCE(a.name,t.album) album, COALESCE(a.album_artist,t.album_artist) album_artist,
        CASE WHEN a.id IS NULL THEN t.album_id ELSE 'playlist:'||a.id END album_id,
        COALESCE(a.album_year,t.year) year, COALESCE(a.album_genre,t.genre) genre,
        COALESCE(m.number,t.track_number) track_number, COALESCE(m.disc,t.disc_number) disc_number,
        t.duration_ms, COALESCE(a.album_cover_key,t.cover_key) cover_key,t.warning,t.properties,
        CASE WHEN a.id IS NULL THEN t.album_tagged ELSE 1 END album_tagged,
        CASE WHEN a.id IS NULL THEN t.search_text ELSE
          t.title_sort||' '||t.artist_sort||' '||a.album_search END search_text,
        t.title_sort,t.artist_sort,COALESCE(a.album_sort,t.album_sort) album_sort,
        COALESCE(a.album_artist_sort,t.album_artist_sort) album_artist_sort,t.added_at
      FROM tracks t LEFT JOIN user_album_members m ON m.path=t.path
      LEFT JOIN playlists a ON a.id=m.playlist_id;
      CREATE VIEW user_album_tracks AS
      SELECT * FROM user_album_indexed_tracks
      UNION ALL
      SELECT -e.rowid,e.path,0,0,0,e.title,
        (SELECT group_concat(value,' / ') FROM json_each(e.artists)),
        a.name,a.album_artist,'playlist:'||a.id,a.album_year,a.album_genre,
        m.number,m.disc,e.duration_ms,COALESCE(a.album_cover_key,e.cover_key),NULL,'{}',1,
        musani_lower(e.title||' '||e.artists)||' '||a.album_search,
        musani_lower(e.title),musani_lower(e.artists),a.album_sort,a.album_artist_sort,e.created_at*1000
      FROM user_album_members m JOIN playlists a ON a.id=m.playlist_id
      JOIN playlist_entries e ON e.id=m.entry_id
      WHERE NOT EXISTS (SELECT 1 FROM tracks t WHERE t.path=m.path);
      CREATE VIEW user_album_artists AS
      SELECT track_id,artist_key,name FROM track_artists
      UNION ALL
      SELECT -e.rowid,musani_lower(j.value),j.value
      FROM user_album_members m JOIN playlist_entries e ON e.id=m.entry_id
      JOIN json_each(e.artists) j
      WHERE NOT EXISTS (SELECT 1 FROM tracks t WHERE t.path=m.path);
      PRAGMA user_version=6;
    ''');
    for (final row in _db.select('''
      SELECT p.id,p.name FROM playlists p
      WHERE p.is_album=1 AND p.deleted_at IS NULL
    ''')) {
      final id = row['id'] as String;
      _normalizeUserAlbumPaths(id);
      final art = _playlistImage(id);
      _storeAlbumFields(id, row['name'] as String, const UserAlbumMetadata());
      if (art != null) _setAlbumCoverKey(id, art);
    }
    _rebuildAlbumMembers();
  }

  void _storeAlbumFields(String id, String name, UserAlbumMetadata metadata) {
    final artist = metadata.artist.trim();
    final genre = metadata.genre.trim();
    if ([
          artist,
          genre,
        ].any((value) => value.length > 8192 || value.contains('\u0000')) ||
        metadata.year < 0 ||
        metadata.year > 9999 ||
        metadata.disc < 1 ||
        metadata.disc > 9999) {
      throw const FormatException(
        'Проверьте исполнителя, жанр, год и номер диска',
      );
    }
    _db.execute(
      '''
      UPDATE playlists SET album_artist=?,album_year=?,album_genre=?,album_disc=?,
        album_sort=?,album_artist_sort=?,album_search=? WHERE id=?
    ''',
      [
        artist,
        metadata.year,
        genre,
        metadata.disc,
        name.toLowerCase(),
        artist.toLowerCase(),
        '$name $artist $genre ${metadata.year}'.toLowerCase(),
        id,
      ],
    );
  }

  void _setAlbumCoverKey(String id, Uint8List? bytes) {
    String? key;
    if (bytes != null) {
      key = sha256.convert(bytes).toString();
      final destination = File(p.join(coverDirectory, '$key.art'));
      if (!destination.existsSync()) {
        final directory = Directory(coverDirectory)
          ..createSync(recursive: true);
        final temp = directory.createTempSync('.album-cover-');
        try {
          final staged = File(p.join(temp.path, 'cover'))
            ..writeAsBytesSync(bytes);
          staged.renameSync(destination.path);
        } finally {
          temp.deleteSync(recursive: true);
        }
      }
    }
    _db.execute('UPDATE playlists SET album_cover_key=? WHERE id=?', [key, id]);
  }

  // Legacy overlapping albums retain their entries. The earliest album owns the
  // path until its membership is removed; the rest are visible as conflicts.
  void _rebuildAlbumMembers() => _db.execute('''
    DELETE FROM user_album_members;
    INSERT INTO user_album_members(path,playlist_id,entry_id,disc,number)
    WITH candidates AS (
      SELECT e.path,p.id album,e.id entry,e.position,COALESCE(e.album_disc,p.album_disc) disc,
        ROW_NUMBER() OVER(PARTITION BY e.path ORDER BY p.created_at,p.id,e.position,e.id) priority
      FROM playlist_entries e JOIN playlists p ON p.id=e.playlist_id
      WHERE e.deleted_at IS NULL AND p.deleted_at IS NULL AND p.is_album=1
    )
    SELECT path,album,entry,disc,
      ROW_NUMBER() OVER(PARTITION BY album,disc ORDER BY position,entry)
    FROM candidates WHERE priority=1;
  ''');

  void _checkAlbumEntry(String id, String path, {String? exceptEntry}) {
    final conflict = _db
        .select(
          '''
      SELECT p.name FROM playlist_entries e JOIN playlists p ON p.id=e.playlist_id
      WHERE e.path=? AND p.is_album=1 AND p.deleted_at IS NULL AND e.deleted_at IS NULL
        AND (e.playlist_id<>? OR e.id IS NOT ?)
      ORDER BY p.created_at,p.id LIMIT 1
    ''',
          [path, id, exceptEntry],
        )
        .firstOrNull;
    if (conflict != null) {
      throw StateError(
        'Трек уже входит в альбом «${conflict['name']}». '
        'Удалите прежнюю запись перед добавлением.',
      );
    }
  }

  void updateUserAlbum(
    String id,
    int revision,
    String name,
    UserAlbumMetadata metadata,
  ) {
    final valid = _playlistName(name);
    _changePlaylist(id, revision, (_) {
      if (!_isPlaylistAlbum(id)) _enableUserAlbum(id);
      _db.execute('UPDATE playlists SET name=? WHERE id=?', [valid, id]);
      _storeAlbumFields(id, valid, metadata);
    }, refreshMembers: true);
  }

  void setUserAlbumDisc(String id, int revision, String entryId, int? disc) {
    if (disc != null && (disc < 1 || disc > 9999)) {
      throw const FormatException('Номер диска должен быть от 1 до 9999');
    }
    _changePlaylist(id, revision, (now) {
      if (!_isPlaylistAlbum(id))
        throw StateError('Плейлист больше не является альбомом');
      _db.execute(
        '''
        UPDATE playlist_entries SET album_disc=?,updated_at=?
        WHERE playlist_id=? AND id=? AND deleted_at IS NULL
      ''',
        [disc, now, id, entryId],
      );
      if (_db.updatedRows != 1)
        throw StateError('Трек больше не находится в альбоме');
    }, refreshMembers: true);
  }

  void _verifyAlbumExport(String id, int revision) {
    if (_count(
          '''
      SELECT COUNT(*) FROM playlists WHERE id=? AND revision=?
      AND deleted_at IS NULL AND is_album=1
    ''',
          [id, revision],
        ) !=
        1) {
      throw StateError(
        'Альбом изменился. Откройте его и подтвердите запись заново.',
      );
    }
  }

  Future<AlbumWriteReport> writeUserAlbumTags(
    String id,
    int revision,
    String backups,
  ) async {
    _verifyAlbumExport(id, revision);
    final album = playlists(id: id).single;
    final settings = album.albumMetadata;
    final entries = _db.select(
      '''
      SELECT e.id,e.path,m.disc,m.number,m.entry_id=e.id owned,p.album_cover_key
      FROM playlist_entries e JOIN playlists p ON p.id=e.playlist_id
      LEFT JOIN user_album_members m ON m.path=e.path
      WHERE e.playlist_id=? AND e.deleted_at IS NULL AND p.revision=?
      ORDER BY e.position,e.id
    ''',
      [id, revision],
    );
    _verifyAlbumExport(id, revision);
    if (entries.isEmpty) return const AlbumWriteReport([]);
    final coverKey = entries.first['album_cover_key'] as String?;
    final cover = coverKey == null
        ? null
        : await readMetadataCover(p.join(coverDirectory, '$coverKey.art'));
    final outcomes = <AlbumWriteItem>[];
    final reindex = <(String, FileStat, TrackMetadata)>[];
    final reader = TagLibMetadataReader();
    for (final entry in entries) {
      final path = entry['path'] as String;
      if (entry['owned'] != 1) {
        outcomes.add(
          AlbumWriteItem(
            path,
            AlbumWriteStatus.conflict,
            message: 'Трек уже закреплён за другой записью альбома',
          ),
        );
        continue;
      }
      if (!['.mp3', '.flac'].contains(p.extension(path).toLowerCase())) {
        outcomes.add(
          AlbumWriteItem(
            path,
            AlbumWriteStatus.unsupported,
            message: 'Формат не поддерживает массовую запись',
          ),
        );
        continue;
      }
      try {
        _verifyAlbumExport(id, revision);
        final snapshot = await readEditSnapshot(path);
        final result = await saveTrackMetadata(
          snapshot,
          MetadataPatch({
            'ALBUM': album.name,
            'ALBUMARTIST': settings.artist,
            'DATE': settings.year == 0 ? '' : settings.year.toString(),
            'GENRE': settings.genre,
            'TRACKNUMBER': '${entry['number']}',
            'DISCNUMBER': '${entry['disc']}',
          }),
          backups,
          preparedCover: cover,
          beforeCommit: () async {
            _verifyAlbumExport(id, revision);
            final owned = _count(
              'SELECT COUNT(*) FROM user_album_members WHERE path=? AND playlist_id=? AND entry_id=? AND disc=? AND number=?',
              [path, id, entry['id'], entry['disc'], entry['number']],
            );
            if (owned != 1)
              throw StateError('Трек больше не принадлежит альбому');
          },
        );
        outcomes.add(
          AlbumWriteItem(
            path,
            AlbumWriteStatus.saved,
            backupPath: result.backupPath,
            message: result.warning,
          ),
        );
      } catch (error) {
        outcomes.add(
          AlbumWriteItem(path, AlbumWriteStatus.failed, message: '$error'),
        );
        continue;
      }
      final before = File(path).statSync();
      final metadata = reader.read(path, coverDirectory);
      if (_sameRevision(before, File(path).statSync()) &&
          (metadata.warning == null || metadata.durationMs > 0)) {
        reindex.add((path, before, metadata));
      }
    }
    String? warning;
    if (outcomes
            .where((item) => item.status == AlbumWriteStatus.saved)
            .length !=
        reindex.length) {
      warning =
          'Некоторые сохранённые файлы не удалось перечитать для каталога.';
    }
    if (reindex.isNotEmpty) {
      try {
        _db.execute('BEGIN IMMEDIATE');
        try {
          for (final (path, stat, metadata) in reindex) {
            if (!_sameRevision(stat, File(path).statSync())) {
              warning = 'Некоторые файлы изменились до обновления каталога.';
              continue;
            }
            if (_count('SELECT COUNT(*) FROM tracks WHERE path=?', [path]) !=
                0) {
              _upsert(path, metadata, stat);
            } else {
              _updatePlaylistSnapshots(path, metadata, null);
            }
          }
          _db.execute('COMMIT');
        } catch (_) {
          _db.execute('ROLLBACK');
          rethrow;
        }
      } catch (error) {
        warning = 'Файлы сохранены, но каталог не удалось обновить. $error';
      }
    }
    albumChanged = outcomes.any(
      (item) => item.status == AlbumWriteStatus.saved,
    );
    return AlbumWriteReport(
      List.unmodifiable(outcomes),
      catalogWarning: warning,
    );
  }

  bool _isPlaylistAlbum(String id) =>
      _count(
        'SELECT COUNT(*) FROM playlists WHERE id=? AND is_album=1 AND deleted_at IS NULL',
        [id],
      ) !=
      0;
}

const _emptyUserAlbums = '''
  FROM playlists p WHERE p.is_album=1 AND p.deleted_at IS NULL
  AND NOT EXISTS (SELECT 1 FROM user_album_members m WHERE m.playlist_id=p.id)
''';
