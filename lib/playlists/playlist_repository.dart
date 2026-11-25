import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../library/library_database.dart';
import '../library/library_repository.dart';
import 'models.dart';

typedef _ArtworkRead = ({
  int revision,
  int? catalogRevision,
  Future<PlaylistArtwork> result,
});

/// Uses the same catalog database; only DTOs cross the isolate boundary.
class PlaylistRepository {
  const PlaylistRepository(this.directory);
  final String directory;
  static final _artwork = Expando<Map<String, _ArtworkRead>>();

  Future<T> _work<T>(Future<T> Function(LibraryDatabase db) operation) async {
    final root = directory;
    final (result, changed) = await Isolate.run(() async {
      Directory(root).createSync(recursive: true);
      final db = LibraryDatabase(
        p.join(root, 'library.sqlite'),
        p.join(root, 'covers'),
      );
      try {
        return (await operation(db), db.albumChanged);
      } finally {
        db.close();
      }
    });
    if (changed) LibraryRepository.publishAlbumChange(root);
    return result;
  }

  Future<List<UserPlaylist>> list() => _work((db) async => db.playlists());
  Future<UserPlaylist> create(String name) =>
      _work((db) async => db.createPlaylist(name));
  Future<void> rename(String id, int revision, String name) =>
      _work((db) async => db.updatePlaylistProperties(id, revision, name));
  Future<void> updateProperties(
    String id,
    int revision, {
    required String name,
    required bool isAlbum,
  }) => _work(
    (db) async =>
        db.updatePlaylistProperties(id, revision, name, isAlbum: isAlbum),
  );
  Future<void> updateAlbum(
    String id,
    int revision,
    String name,
    UserAlbumMetadata metadata,
  ) => _work((db) async => db.updateUserAlbum(id, revision, name, metadata));
  Future<void> setAlbumDisc(
    String id,
    int revision,
    String entryId,
    int? disc,
  ) => _work((db) async => db.setUserAlbumDisc(id, revision, entryId, disc));
  Future<AlbumWriteReport> writeAlbumTags(String id, int revision) {
    final backups = p.join(directory, '.musani-edit-backups');
    return _work((db) => db.writeUserAlbumTags(id, revision, backups));
  }

  Future<void> delete(String id, int revision) =>
      _work((db) async => db.deletePlaylist(id, revision));
  Future<void> add(String id, int revision, List<PlaylistTrackRef> tracks) =>
      _work((db) async => db.addPlaylistTracks(id, revision, tracks));
  Future<PlaylistDetail> detail(String id) =>
      _work((db) async => db.playlistDetail(id));
  Future<PlaylistArtwork> artwork(
    String id, {
    int? revision,
    int? catalogRevision,
  }) async {
    if (revision == null) return _work((db) async => db.playlistArtwork(id));
    final cache = _artwork[this] ??= {};
    final previous = cache.remove(id);
    if (previous != null &&
        previous.revision == revision &&
        previous.catalogRevision == catalogRevision) {
      cache[id] = previous;
      return previous.result;
    }
    final result = _work((db) async => db.playlistArtwork(id));
    cache[id] = (
      revision: revision,
      catalogRevision: catalogRevision,
      result: result,
    );
    if (cache.length > 12) cache.remove(cache.keys.first);
    try {
      return await result;
    } catch (_) {
      if (identical(cache[id]?.result, result)) cache.remove(id);
      rethrow;
    }
  }

  Future<void> setArtwork(String id, int revision, Uint8List? image) =>
      _work((db) async => db.setPlaylistArtwork(id, revision, image));

  String trackCoverPath(String key) => p.join(directory, 'covers', '$key.art');
  Future<void> reorder(String id, int revision, List<String> entries) =>
      _work((db) async => db.reorderPlaylist(id, revision, entries));
  Future<void> remove(String id, int revision, String entryId) =>
      _work((db) async => db.removePlaylistEntry(id, revision, entryId));
  Future<void> relink(String id, int revision, String entryId, String path) =>
      _work((db) => db.relinkPlaylistEntry(id, revision, entryId, path));
}
