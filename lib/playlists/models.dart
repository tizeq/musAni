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

class UserAlbumMetadata {
  const UserAlbumMetadata({
    this.artist = '',
    this.year = 0,
    this.genre = '',
    this.disc = 1,
  });
  final String artist;
  final int year;
  final String genre;
  final int disc;
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
    this.albumMetadata = const UserAlbumMetadata(),
    this.albumCoverKey,
  });
  final String id;
  final String name;
  final int revision;
  final int updatedMs;
  final int trackCount;
  final int durationMs;
  final bool isAlbum;
  final UserAlbumMetadata albumMetadata;
  final String? albumCoverKey;
}

enum PlaylistFileState { available, missing, unreadable }

class PlaylistEntry {
  const PlaylistEntry({
    required this.id,
    required this.position,
    required this.track,
    required this.fileState,
    this.error,
    this.albumTrackNumber,
    this.albumDisc,
    this.albumConflict,
  });
  final String id;
  final int position;
  final PlaylistTrackRef track;
  final PlaylistFileState fileState;
  final String? error;
  final int? albumTrackNumber;
  final int? albumDisc;
  final String? albumConflict;
  bool get available => fileState == PlaylistFileState.available;
}

class PlaylistDetail {
  const PlaylistDetail(this.playlist, this.entries);
  final UserPlaylist playlist;
  final List<PlaylistEntry> entries;
  int get unavailableCount => entries
      .where((entry) => !entry.available && entry.albumConflict == null)
      .length;
}

class PlaylistArtwork {
  const PlaylistArtwork({this.image, this.trackCovers = const []});

  final Uint8List? image;
  final List<String> trackCovers;
}

enum AlbumWriteStatus { saved, unsupported, conflict, failed }

class AlbumWriteItem {
  const AlbumWriteItem(this.path, this.status, {this.message, this.backupPath});
  final String path;
  final AlbumWriteStatus status;
  final String? message;
  final String? backupPath;
}

class AlbumWriteReport {
  const AlbumWriteReport(this.items, {this.catalogWarning});
  final List<AlbumWriteItem> items;
  final String? catalogWarning;
}
