import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../files/local_tracks.dart';
import 'library_database.dart';
import 'models.dart';
import 'metadata_reader.dart';

/// Only immutable DTOs and paths cross the isolate boundary, never DB/FFI handles.
class LibraryRepository {
  LibraryRepository(this.directory);
  final String directory;
  final _queries = <String, LibraryResult>{};
  final _albums = <String, List<LibraryTrack>>{};
  int _generation = 0;

  void _invalidate() {
    _generation++;
    _queries.clear();
    _albums.clear();
  }

  void _remember<T>(Map<String, T> cache, String key, T value) {
    cache.remove(key);
    cache[key] = value;
    if (cache.length > 16) cache.remove(cache.keys.first);
  }

  String get databasePath => p.join(directory, 'library.sqlite');
  String get coverDirectory => p.join(directory, 'covers');
  String coverPath(String key) => p.join(coverDirectory, '$key.art');

  Future<LibraryStatus> status() {
    final root = directory;
    return Isolate.run(() {
      final db = _open(root);
      try {
        return db.status();
      } finally {
        db.close();
      }
    });
  }

  Future<LibraryResult> query(LibraryQuery query) async {
    final key = jsonEncode([
      query.view.index,
      query.search,
      query.sort.index,
      query.descending,
      query.artistId,
      query.albumId,
      query.offset,
      query.limit,
    ]);
    final cached = _queries.remove(key);
    if (cached != null) {
      _queries[key] = cached;
      return cached;
    }
    final generation = _generation;
    final root = directory;
    final result = await Isolate.run(() {
      final db = _open(root);
      try {
        return db.query(query);
      } finally {
        db.close();
      }
    });
    if (generation == _generation) _remember(_queries, key, result);
    return result;
  }

  Future<List<LocalTrack>> playbackTracks(LibraryQuery query) {
    final root = directory;
    return Isolate.run(() {
      final db = _open(root);
      try {
        return db.playbackTracks(query);
      } finally {
        db.close();
      }
    });
  }

  Future<List<LibraryTrack>> albumTracks(String albumId) async {
    final cached = _albums.remove(albumId);
    if (cached != null) {
      _albums[albumId] = cached;
      return cached;
    }
    final generation = _generation;
    final root = directory;
    final result = await Isolate.run(() {
      final db = _open(root);
      try {
        return db.albumTracks(albumId);
      } finally {
        db.close();
      }
    });
    if (generation == _generation && result.length <= 500)
      _remember(_albums, albumId, result);
    return result;
  }

  Future<LibraryTrack?> track(int id) {
    final root = directory;
    return Isolate.run(() {
      final db = _open(root);
      try {
        return db.track(id);
      } finally {
        db.close();
      }
    });
  }

  Future<LibraryTrack?> trackByPath(String path) {
    final root = directory;
    return Isolate.run(() {
      final db = _open(root);
      try {
        return db.trackByPath(path);
      } finally {
        db.close();
      }
    });
  }

  /// Artwork for directly opened files, without enrolling them in the catalog.
  /// TagLib and cache extraction stay off the UI isolate.
  Future<TrackMetadata> readPlaybackMetadata(String path) {
    final covers = coverDirectory;
    return Isolate.run(() => TagLibMetadataReader().read(path, covers));
  }

  Future<TrackMetadata> reindexTrack(String path) async {
    _invalidate();
    final root = directory;
    try {
      return await Isolate.run(() {
        final db = _open(root);
        try {
          return db.reindexTrack(path);
        } finally {
          db.close();
        }
      });
    } finally {
      _invalidate();
    }
  }

  Future<void> removeRoot(int id) async {
    _invalidate();
    final root = directory;
    try {
      await Isolate.run(() {
        final db = _open(root);
        try {
          db.removeRoot(id);
        } finally {
          db.close();
        }
      });
    } finally {
      _invalidate();
    }
  }

  Future<ScanReport> scan({
    String? addRoot,
    void Function(ScanProgress)? onProgress,
  }) async {
    _invalidate();
    final port = ReceivePort();
    Isolate? worker;
    try {
      worker = await Isolate.spawn(
        _scanWorker,
        (directory, addRoot, port.sendPort),
        onError: port.sendPort,
        onExit: port.sendPort,
      );
      await for (final message in port) {
        if (message is ScanProgress)
          onProgress?.call(message);
        else if (message is ScanReport)
          return message;
        else if (message is _WorkerError)
          throw StateError(message.message);
        else if (message is List)
          throw StateError(message.first.toString());
        else if (message == null)
          throw StateError('Процесс сканирования завершился без результата');
      }
      throw StateError('Нет результата сканирования');
    } finally {
      _invalidate();
      port.close();
      worker?.kill();
    }
  }
}

LibraryDatabase _open(String directory) {
  Directory(directory).createSync(recursive: true);
  return LibraryDatabase(
    p.join(directory, 'library.sqlite'),
    p.join(directory, 'covers'),
  );
}

class _WorkerError {
  const _WorkerError(this.message);
  final String message;
}

Future<void> _scanWorker((String, String?, SendPort) arguments) async {
  final (directory, addRoot, port) = arguments;
  LibraryDatabase? db;
  try {
    db = _open(directory);
    port.send(await db.scan(addRoot: addRoot, onProgress: port.send));
  } catch (error) {
    port.send(_WorkerError(error.toString()));
  } finally {
    db?.close();
  }
}
