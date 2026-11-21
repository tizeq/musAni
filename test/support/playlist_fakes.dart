import 'dart:async';

import 'package:musani/playlists/models.dart';
import 'package:musani/playlists/playlist_repository.dart';

class MemoryPlaylistRepository extends PlaylistRepository {
  MemoryPlaylistRepository() : super('/tmp/unused-playlist-widget-catalog');
  final items = <String, PlaylistDetail>{};
  int sequence = 0;
  int additions = 0;
  int reorders = 0;
  Object? failure;
  Completer<void>? gate;
  @override
  Future<List<UserPlaylist>> list() async =>
      items.values.map((detail) => detail.playlist).toList();
  @override
  Future<UserPlaylist> create(String name) async {
    final playlist = UserPlaylist(
      id: '${++sequence}',
      name: name,
      revision: 0,
      updatedMs: 0,
    );
    items[playlist.id] = PlaylistDetail(playlist, []);
    return playlist;
  }

  void update(String id, {List<PlaylistEntry>? entries, String? name}) {
    final old = items[id]!;
    entries ??= old.entries;
    items[id] = PlaylistDetail(
      UserPlaylist(
        id: id,
        name: name ?? old.playlist.name,
        revision: old.playlist.revision + 1,
        updatedMs: old.playlist.updatedMs + 1,
        trackCount: entries.length,
        durationMs: entries.fold(
          0,
          (sum, entry) => sum + entry.track.durationMs,
        ),
      ),
      entries,
    );
  }

  @override
  Future<PlaylistDetail> detail(String id) async => items[id]!;
  @override
  Future<void> rename(String id, int revision, String name) async =>
      update(id, name: name);
  @override
  Future<void> delete(String id, int revision) async {
    items.remove(id);
  }

  @override
  Future<void> add(
    String id,
    int revision,
    List<PlaylistTrackRef> tracks,
  ) async {
    additions++;
    await gate?.future;
    if (failure case final error?) throw error;
    final entries = [...items[id]!.entries];
    for (final track in tracks) {
      entries.add(
        PlaylistEntry(
          id: 'entry-${++sequence}',
          position: entries.length,
          track: track,
          fileState: PlaylistFileState.available,
        ),
      );
    }
    update(id, entries: entries);
  }

  @override
  Future<void> reorder(String id, int revision, List<String> entries) async {
    reorders++;
    update(
      id,
      entries: [
        for (final entry in entries)
          items[id]!.entries.singleWhere((item) => item.id == entry),
      ],
    );
  }

  @override
  Future<void> remove(String id, int revision, String entryId) async => update(
    id,
    entries: items[id]!.entries.where((entry) => entry.id != entryId).toList(),
  );
  @override
  Future<void> relink(
    String id,
    int revision,
    String entryId,
    String path,
  ) async {
    if (failure case final error?) throw error;
    update(
      id,
      entries: [
        for (final entry in items[id]!.entries)
          entry.id != entryId
              ? entry
              : PlaylistEntry(
                  id: entry.id,
                  position: entry.position,
                  fileState: PlaylistFileState.available,
                  track: PlaylistTrackRef(
                    path: path,
                    title: entry.track.title,
                    artists: entry.track.artists,
                    durationMs: entry.track.durationMs,
                  ),
                ),
      ],
    );
  }
}
