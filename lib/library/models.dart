import '../files/local_tracks.dart';

/// Catalog snapshot. Display labels are separate from the original tag values
/// used for explicit editor patches and revision checks.
class TrackMetadata {
  const TrackMetadata({
    required this.title,
    required this.artists,
    required this.album,
    required this.albumArtist,
    this.year = 0,
    this.genre = '',
    this.trackNumber = 0,
    this.discNumber = 0,
    this.durationMs = 0,
    this.properties = const {},
    this.coverKey,
    this.warning,
    this.albumTagged = true,
  });

  final String title;
  final List<String> artists;
  final String album;
  final String albumArtist;
  final int year;
  final String genre;
  final int trackNumber;
  final int discNumber;
  final int durationMs;
  final Map<String, List<String>> properties;
  final String? coverKey;
  final String? warning;
  final bool albumTagged;
  String get artist => artists.join(' / ');
}

class LibraryTrack {
  const LibraryTrack({
    required this.id,
    required this.path,
    required this.albumId,
    required this.metadata,
    required this.size,
    required this.modifiedUs,
    required this.changedUs,
  });
  final int id;
  final String path;

  /// Null when the source has no album tag; such tracks have no album group.
  final String? albumId;
  final TrackMetadata metadata;
  final int size;
  final int modifiedUs;
  final int changedUs;
  LocalTrack get playable => LocalTrack(
    Uri.file(path),
    metadata.title,
    artists: List.unmodifiable(metadata.artists),
  );
}

class LibraryAlbum {
  const LibraryAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.trackCount,
    required this.durationMs,
    this.coverKey,
  });
  final String id;
  final String title;
  final String artist;
  final int year;
  final int trackCount;
  final int durationMs;
  final String? coverKey;
}

class LibraryArtist {
  const LibraryArtist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.albumCount,
    this.coverKey,
  });
  final String id;
  final String name;
  final int trackCount;
  final int albumCount;
  final String? coverKey;
}

class LibraryRoot {
  const LibraryRoot(this.id, this.path, this.lastScan, this.error);
  final int id;
  final String path;
  final int? lastScan;
  final String? error;
}

class LibraryStatus {
  const LibraryStatus({
    this.roots = const [],
    this.trackCount = 0,
    this.albumCount = 0,
    this.artistCount = 0,
  });
  final List<LibraryRoot> roots;
  final int trackCount;
  final int albumCount;
  final int artistCount;
}

enum LibraryView { albums, artists, tracks }

enum LibrarySort { title, artist, year, added }

class LibraryQuery {
  const LibraryQuery({
    this.view = LibraryView.albums,
    this.search = '',
    this.sort = LibrarySort.title,
    this.descending = false,
    this.artistId,
    this.albumId,
    this.offset = 0,
    this.limit = 60,
  });
  final LibraryView view;
  final String search;
  final LibrarySort sort;
  final bool descending;
  final String? artistId;

  /// Optional album filter; null includes tracks both with and without albums.
  final String? albumId;
  final int offset;
  final int limit;

  /// Identifies the result and its scroll position across paginated requests.
  Object get criteria =>
      (view, search, sort, descending, artistId, albumId, limit);

  LibraryQuery page(int offset) => LibraryQuery(
    view: view,
    search: search,
    sort: sort,
    descending: descending,
    artistId: artistId,
    albumId: albumId,
    offset: offset,
    limit: limit,
  );
}

class LibraryResult {
  const LibraryResult({
    this.albums = const [],
    this.artists = const [],
    this.tracks = const [],
    required this.total,
  });
  final List<LibraryAlbum> albums;
  final List<LibraryArtist> artists;
  final List<LibraryTrack> tracks;
  final int total;
  int get length => albums.length + artists.length + tracks.length;
}

class ScanProgress {
  const ScanProgress(this.visited, this.updated, this.unchanged, this.path);
  final int visited;
  final int updated;
  final int unchanged;
  final String path;
}

class ScanReport {
  const ScanReport({
    required this.visited,
    required this.updated,
    required this.unchanged,
    required this.removed,
    required this.warnings,
  });
  final int visited;
  final int updated;
  final int unchanged;
  final int removed;
  final List<String> warnings;
}
