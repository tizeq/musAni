import 'dart:typed_data';

import '../files/local_tracks.dart';
import '../library/models.dart';

class PlaylistTrackRef {
  const PlaylistTrackRef({
    required this.path,
    required this.title,
    this.artists = const [],
    this.durationMs = 0,
    this.trackId,
    this.coverKey,
  });
  factory PlaylistTrackRef.fromLibrary(LibraryTrack track) => PlaylistTrackRef(
    path: track.path,
    title: track.metadata.title,
    artists: track.metadata.artists,
    durationMs: track.metadata.durationMs,
    trackId: track.id,
    coverKey: track.metadata.coverKey,
  );
  final String path;
  final String title;
  final List<String> artists;
  final int durationMs;
  final int? trackId;
  final String? coverKey;
  LocalTrack get playable => toPlayable();

  LocalTrack toPlayable({(String, String)? playlistEntry}) => LocalTrack(
    Uri.file(path),
    title,
    artists: List.unmodifiable(artists),
    playlistEntry: playlistEntry,
  );
}

class UserPlaylist {
  const UserPlaylist({
    required this.id,
    required this.name,
    required this.revision,
    required this.updatedMs,
    this.trackCount = 0,
    this.durationMs = 0,
    this.isAlbum = false,
  });
  final String id;
  final String name;
  final int revision;
  final int updatedMs;
  final int trackCount;
  final int durationMs;
  final bool isAlbum;
}

enum PlaylistFileState { available, missing, unreadable }

class PlaylistEntry {
  const PlaylistEntry({
    required this.id,
    required this.position,
    required this.track,
    required this.fileState,
    this.error,
  });
  final String id;
  final int position;
  final PlaylistTrackRef track;
  final PlaylistFileState fileState;
  final String? error;
  bool get available => fileState == PlaylistFileState.available;
}

class PlaylistDetail {
  const PlaylistDetail(this.playlist, this.entries);
  final UserPlaylist playlist;
  final List<PlaylistEntry> entries;
  int get unavailableCount => entries.where((entry) => !entry.available).length;
}

class PlaylistArtwork {
  const PlaylistArtwork({this.image, this.trackCovers = const []});

  final Uint8List? image;
  final List<String> trackCovers;
}
