import 'dart:io';
import 'dart:isolate';

class LocalTrack {
  const LocalTrack(
    this.uri,
    this.name, {
    this.artists = const [],
    this.playlistEntry,
  });
  final Uri uri;
  final String name;
  final List<String> artists;
  final (String playlistId, String entryId)? playlistEntry;
}

/// Desktop file access. Android SAF will use a separate URI/descriptor adapter.
class LocalTracks {
  static const extensions = ['mp3', 'flac', 'm4a', 'ogg', 'wav', 'opus'];

  /// Checks a queue before handing it to the player, without changing order,
  /// collapsing entries, or doing one filesystem round trip per row on the UI.
  Future<void> validate(List<String> paths) => Isolate.run(() {
    for (final path in paths.toSet()) {
      final file = File(path);
      _checkExtension(file.uri.pathSegments.last);
      file.openSync().closeSync();
    }
  });

  static void _checkExtension(String name) {
    if (!extensions.contains(name.split('.').last.toLowerCase())) {
      throw FormatException('Неподдерживаемый формат: $name');
    }
  }

  Future<List<LocalTrack>> resolve(Iterable<String> paths) async {
    final result = <LocalTrack>[];
    final seen = <String>{};
    for (final path in paths) {
      final file = File(path).absolute;
      final name = file.uri.pathSegments.last;
      _checkExtension(name);
      // Fail before replacing the current queue; do not silently omit files.
      final canonical = await file.resolveSymbolicLinks();
      final handle = await File(canonical).open();
      await handle.close();
      if (seen.add(canonical)) {
        result.add(LocalTrack(File(canonical).uri, name));
      }
    }
    return List.unmodifiable(result);
  }
}
