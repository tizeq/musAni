import 'dart:async';
import 'dart:collection';

import 'package:media_kit/media_kit.dart';

import '../files/local_tracks.dart';
import '../settings/repeat_mode_store.dart';
import 'playback_engine.dart';

class MediaKitEngine implements PlaybackEngine {
  MediaKitEngine(this._player, {required RepeatModeStore repeatModeStore})
    : _repeatModeStore = repeatModeStore {
    _subscriptions.addAll([
      _player.stream.playlist.listen((_) => _emit()),
      _player.stream.playing.listen((_) => _emit()),
      _player.stream.position.listen((_) => _emit()),
      _player.stream.duration.listen((_) => _emit()),
      _player.stream.volume.listen((_) => _emit()),
      _player.stream.playlistMode.listen((_) => _emit()),
      _player.stream.error.listen((message) {
        _error = message;
        _emit();
      }),
    ]);
  }

  final Player _player;
  final RepeatModeStore _repeatModeStore;
  final _changes = StreamController<PlaybackState>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  List<LocalTrack> _queue = const [];
  List<LocalTrack> _originalQueue = const [];
  PlaybackState? _beforeQueueChange;
  int _fallbackIndex = 0;
  String? _error;

  @override
  PlaybackState get state {
    if (_beforeQueueChange case final previous?) return previous;
    final player = _player.state;
    final playlist = player.playlist;
    final validIndex =
        playlist.medias.length == _queue.length &&
        playlist.index >= 0 &&
        playlist.index < _queue.length;
    return PlaybackState(
      queue: _queue,
      index: validIndex ? playlist.index : _fallbackIndex,
      playing: player.playing,
      position: player.position,
      duration: player.duration,
      volume: player.volume,
      shuffle: player.shuffle,
      repeatMode: switch (player.playlistMode) {
        PlaylistMode.none => RepeatMode.off,
        PlaylistMode.loop => RepeatMode.all,
        PlaylistMode.single => RepeatMode.one,
      },
      error: _error,
    );
  }

  @override
  Stream<PlaybackState> get changes => _changes.stream;
  void _emit() {
    if (_beforeQueueChange == null) _changes.add(state);
  }

  /// Restore before showing the UI or opening the first queue.
  Future<void> restoreRepeatMode() async {
    var mode = RepeatMode.off;
    try {
      mode = await _repeatModeStore.load();
    } catch (error) {
      _error = 'Не удалось восстановить режим повтора: $error';
    }
    await _player.setPlaylistMode(_playlistMode(mode));
    _emit();
  }

  PlaylistMode _playlistMode(RepeatMode mode) => switch (mode) {
    RepeatMode.off => PlaylistMode.none,
    RepeatMode.all => PlaylistMode.loop,
    RepeatMode.one => PlaylistMode.single,
  };

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    await _player.setPlaylistMode(_playlistMode(mode));
    _error = null;
    _emit();
    try {
      await _repeatModeStore.save(mode);
    } catch (error) {
      // Playback keeps the selected mode; the UI reports that it was not saved.
      throw StateError('Не удалось сохранить режим повтора: $error');
    }
  }

  @override
  Future<void> open(List<LocalTrack> tracks, {int index = 0}) async {
    if (tracks.isEmpty) return;
    RangeError.checkValidIndex(index, tracks);
    if (_beforeQueueChange != null) throw StateError('Очередь уже обновляется');
    final before = state;
    final queue = List<LocalTrack>.unmodifiable(tracks);
    _beforeQueueChange = before;
    _error = null;
    try {
      // media_kit resets the native playlist while opening it. Set the initial
      // position while paused and publish the new queue only once it is ready.
      await _player.open(
        Playlist([
          for (final track in queue) Media(track.uri.toString()),
        ], index: index),
        play: false,
      );
      _queue = _originalQueue = queue;
      _fallbackIndex = index;
      if (before.shuffle) {
        await _player.setShuffle(true);
        _queue = _shuffledQueue(queue[index]);
      }
      await _player.play();
    } finally {
      _beforeQueueChange = null;
      _emit();
    }
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    final before = state;
    if (_beforeQueueChange != null ||
        before.shuffle == enabled ||
        _queue.length < 2)
      return;
    _beforeQueueChange = before;
    try {
      await _player.setShuffle(enabled);
      _queue = enabled
          ? _shuffledQueue(before.queue[before.index])
          : _originalQueue;
    } finally {
      _beforeQueueChange = null;
      _emit();
    }
  }

  List<LocalTrack> _shuffledQueue(LocalTrack current) {
    final entries = <String, Queue<LocalTrack>>{};
    for (final track in _originalQueue) {
      final uri = Media.normalizeURI(track.uri.toString());
      (entries[uri] ??= Queue()).addLast(track);
    }
    // mpv returns the new order and the index of the still-playing item.
    // Preserve that exact entry, including when its URI occurs more than once.
    entries[Media.normalizeURI(current.uri.toString())]!.remove(current);
    final playlist = _player.state.playlist;
    return List.unmodifiable([
      for (var i = 0; i < playlist.medias.length; i++)
        if (i == playlist.index)
          current
        else
          entries[playlist.medias[i].uri]!.removeFirst(),
    ]);
  }

  @override
  Future<void> toggle() => _player.playOrPause();
  @override
  Future<void> jump(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _error = null;
    await _player.jump(index);
    await _player.play();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0, 100).toDouble());
  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _changes.close();
  }
}
