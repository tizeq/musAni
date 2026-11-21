import '../files/local_tracks.dart';

enum RepeatMode {
  off,
  all,
  one;

  RepeatMode get next => values[(index + 1) % values.length];
}

class PlaybackState {
  const PlaybackState({
    this.queue = const [],
    this.index = 0,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 80,
    this.repeatMode = RepeatMode.off,
    this.shuffle = false,
    this.error,
  });
  final List<LocalTrack> queue;
  final int index;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume;
  final RepeatMode repeatMode;
  final bool shuffle;
  final String? error;

  LocalTrack? get currentTrack =>
      index >= 0 && index < queue.length ? queue[index] : null;

  int? indexAtOffset(int offset) {
    if (queue.isEmpty) return null;
    final target = index + offset;
    if (repeatMode == RepeatMode.all) return target % queue.length;
    return target >= 0 && target < queue.length ? target : null;
  }
}

abstract interface class PlaybackEngine {
  PlaybackState get state;
  Stream<PlaybackState> get changes;
  Future<void> open(List<LocalTrack> tracks, {int index = 0});
  Future<void> toggle();
  Future<void> jump(int index);
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setRepeatMode(RepeatMode mode);
  Future<void> setShuffle(bool enabled);
  Future<void> dispose();
}
