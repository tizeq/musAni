import 'dart:async';

import 'package:musani/library/library_repository.dart';
import 'package:musani/library/models.dart';

class FakeLibraryRepository extends LibraryRepository {
  FakeLibraryRepository(this.tracks, {this.empty = false})
    : super('/tmp/musani-widget-catalog');
  final List<LibraryTrack> tracks;
  bool empty;
  final queries = <LibraryQuery>[];
  String? addedRoot;
  int scans = 0;
  int labelReads = 0;
  int albumReads = 0;
  Completer<void>? scanGate;

  LibraryAlbum get album => LibraryAlbum(
    id: 'album',
    title: 'Север',
    artist: 'Группа',
    year: 2026,
    trackCount: tracks.length,
    durationMs: 60000,
  );

  @override
  Future<LibraryStatus> status() async => LibraryStatus(
    trackCount: empty ? 0 : tracks.length,
    albumCount: empty ? 0 : 1,
    artistCount: empty ? 0 : 1,
  );

  @override
  Future<LibraryResult> query(LibraryQuery query) async {
    queries.add(query);
    if (empty || query.search == 'не найдено')
      return const LibraryResult(total: 0);
    return switch (query.view) {
      LibraryView.albums => LibraryResult(total: 1, albums: [album]),
      LibraryView.artists => const LibraryResult(
        total: 1,
        artists: [
          LibraryArtist(
            id: 'artist',
            name: 'Исполнитель',
            trackCount: 2,
            albumCount: 1,
          ),
        ],
      ),
      LibraryView.tracks => LibraryResult(total: tracks.length, tracks: tracks),
    };
  }

  @override
  Future<List<LibraryTrack>> albumTracks(String albumId) async {
    albumReads++;
    return tracks;
  }

  @override
  Future<LibraryTrack?> trackByPath(String path) async {
    labelReads++;
    return tracks.where((track) => track.path == path).firstOrNull;
  }

  @override
  Future<TrackMetadata> reindexTrack(String path) async =>
      tracks.singleWhere((track) => track.path == path).metadata;

  @override
  Future<ScanReport> scan({
    String? addRoot,
    void Function(ScanProgress)? onProgress,
  }) async {
    scans++;
    addedRoot = addRoot;
    onProgress?.call(const ScanProgress(10, 2, 8, '/music/example.mp3'));
    await scanGate?.future;
    empty = false;
    return const ScanReport(
      visited: 10,
      updated: 2,
      unchanged: 8,
      removed: 0,
      warnings: [],
    );
  }
}

List<LibraryTrack> sampleLibraryTracks(String directory) => [
  for (var i = 0; i < 2; i++)
    LibraryTrack(
      id: i + 1,
      path: '$directory/$i.mp3',
      albumId: 'album',
      metadata: TrackMetadata(
        title: i == 0 ? 'Первый трек' : 'Второй трек',
        artists: const ['Исполнитель'],
        album: 'Север',
        albumArtist: 'Группа',
        trackNumber: i + 1,
        durationMs: 30000,
      ),
      size: 1,
      modifiedUs: 1,
      changedUs: 1,
    ),
];
