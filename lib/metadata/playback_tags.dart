import 'dart:isolate';

import 'package:flutter_taglib/flutter_taglib.dart';

import '../files/local_tracks.dart';
import 'tag_values.dart';

/// Lightweight labels for files opened outside the catalog. Never save tags or
/// read artwork on this path; unsupported/broken files retain their filename.
Future<List<LocalTrack>> readPlaybackTags(List<LocalTrack> tracks) =>
    Isolate.run(() => [for (final track in tracks) _read(track)]);

LocalTrack _read(LocalTrack track) {
  TagLibFile? file;
  try {
    file = TagLibFile.open(track.uri.toFilePath());
    if (file == null) return track;
    return LocalTrack(
      track.uri,
      file.title.trim().isEmpty ? track.name : file.title.trim(),
      artists: List.unmodifiable(
        trackArtistValues(file.properties, fallback: file.artist),
      ),
    );
  } catch (_) {
    return track;
  } finally {
    file?.close();
  }
}
