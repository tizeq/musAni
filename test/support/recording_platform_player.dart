import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Records commands to the real adapter without loading libmpv in unit tests.
class RecordingPlatformPlayer extends PlatformPlayer {
  RecordingPlatformPlayer() : super(configuration: const PlayerConfiguration());

  final modes = <PlaylistMode>[];
  Object? modeError;
  Completer<void>? openGate;
  bool opening = false;

  @override
  Future<void> setPlaylistMode(PlaylistMode mode) async {
    if (modeError case final error?) throw error;
    modes.add(mode);
    state = state.copyWith(playlistMode: mode);
    playlistModeController.add(mode);
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opening = true;
    await openGate?.future;
    state = state.copyWith(playlist: playable as Playlist, playing: play);
    playlistController.add(state.playlist);
  }

  @override
  Future<void> jump(int index) async {
    state = state.copyWith(
      playlist: state.playlist.copyWith(index: index),
      playing: true,
      position: Duration.zero,
    );
    playlistController.add(state.playlist);
  }

  @override
  Future<void> play() async {
    state = state.copyWith(playing: true);
    playingController.add(true);
  }

  @override
  Future<void> playOrPause() async {
    state = state.copyWith(playing: !state.playing);
    playingController.add(state.playing);
  }

  @override
  Future<void> seek(Duration position) async {
    state = state.copyWith(position: position);
    positionController.add(position);
  }
}
