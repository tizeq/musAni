import 'dart:async';

import 'package:flutter/foundation.dart';

import '../files/local_tracks.dart';
import 'library_repository.dart';
import 'models.dart';

class LibraryController extends ChangeNotifier {
  LibraryController(this.repository) {
    _albumChanges = repository.albumChanges.listen((_) {
      if (_disposed) return;
      catalogRevision++;
      unawaited(load());
    });
  }
  late final StreamSubscription<String> _albumChanges;
  final LibraryRepository repository;
  LibraryStatus status = const LibraryStatus();
  LibraryQuery query = const LibraryQuery();
  LibraryResult result = const LibraryResult(total: 0);
  bool loading = false;
  bool scanning = false;
  bool editing = false;
  bool get mutating => scanning || editing;
  bool initialized = false;
  int catalogRevision = 0;
  // Refresh queue labels without reopening audio, including non-catalog files.
  final _editedLabels = <String, LocalTrack>{};

  LocalTrack labelsFor(LocalTrack track) =>
      _editedLabels[track.uri.toFilePath()] ?? track;
  final _scanProgress = ValueNotifier<ScanProgress?>(null);
  ValueListenable<ScanProgress?> get scanProgress => _scanProgress;
  ScanProgress? get progress => _scanProgress.value;
  set progress(ScanProgress? value) => _scanProgress.value = value;
  ScanReport? lastReport;
  String? error;
  int _request = 0;
  bool _disposed = false;
  final _sections =
      <
        LibraryView,
        ({LibraryQuery query, LibraryResult? result, int revision})
      >{};

  LibraryQuery queryFor(LibraryView view) => view == query.view
      ? query
      : _sections[view]?.query ?? LibraryQuery(view: view);

  void _rememberSection(LibraryResult? result) {
    _sections[query.view] = (
      query: query,
      result: result,
      revision: catalogRevision,
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      status = await repository.status();
      initialized = true;
      await search(query);
    } catch (failure) {
      error = failure.toString();
      initialized = true;
      _notify();
    }
  }

  Future<void> search(LibraryQuery next, {bool restoreSection = false}) async {
    final request = ++_request;
    query = next.page(0);
    error = null;
    final saved = _sections[query.view];
    final cached = saved?.result;
    if (restoreSection &&
        cached != null &&
        saved!.revision == catalogRevision &&
        saved.query.criteria == query.criteria) {
      result = cached;
      loading = false;
      _notify();
      return;
    }
    loading = true;
    result = const LibraryResult(total: 0);
    _rememberSection(null);
    _notify();
    try {
      final page = await repository.query(query);
      if (request == _request && !_disposed) {
        result = page;
        _rememberSection(result);
      }
    } catch (failure) {
      if (request == _request) error = failure.toString();
    } finally {
      if (request == _request) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    if (loading || result.length >= result.total) return;
    final request = _request;
    loading = true;
    _notify();
    try {
      final page = await repository.query(query.page(result.length));
      if (request == _request && !_disposed) {
        result = LibraryResult(
          total: page.total,
          albums: [...result.albums, ...page.albums],
          artists: [...result.artists, ...page.artists],
          tracks: [...result.tracks, ...page.tracks],
        );
        _rememberSection(result);
      }
    } catch (failure) {
      if (request == _request) error = failure.toString();
    } finally {
      if (request == _request) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> refresh({String? addRoot}) async {
    if (mutating || _disposed) return;
    scanning = true;
    progress = null;
    error = null;
    _notify();
    try {
      lastReport = await repository.scan(
        addRoot: addRoot,
        onProgress: (value) {
          if (!_disposed) progress = value;
        },
      );
      catalogRevision++;
      if (!_disposed) await load();
    } catch (failure) {
      error = failure.toString();
    } finally {
      scanning = false;
      _notify();
    }
  }

  Future<void> removeRoot(int id) async {
    if (mutating) return;
    try {
      await repository.removeRoot(id);
      catalogRevision++;
      await load();
    } catch (failure) {
      error = failure.toString();
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    unawaited(_albumChanges.cancel());
    _scanProgress.dispose();
    super.dispose();
  }

  Future<T> writeMetadata<T>(Future<T> Function() operation) async {
    if (mutating || _disposed)
      throw StateError('Дождитесь завершения обновления библиотеки');
    editing = true;
    _notify();
    try {
      return await operation();
    } finally {
      editing = false;
      _notify();
    }
  }

  Future<void> metadataChanged(String path) async {
    final metadata = await repository.reindexTrack(path);
    _editedLabels[path] = LocalTrack(
      Uri.file(path),
      metadata.title,
      artists: List.unmodifiable(metadata.artists),
    );
    catalogRevision++;
    await load();
    if (error != null) throw StateError(error!);
  }
}
