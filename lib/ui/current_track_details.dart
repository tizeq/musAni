import 'package:material_ui/material_ui.dart';

import '../files/local_tracks.dart';
import '../library/library_controller.dart';
import 'album_artwork.dart';
import 'atmosphere.dart';
import 'aurora_scene.dart';

typedef _TrackRow = ({String path, (String, String)? entry, bool matchPath});

/// Updates only rows whose current-track indicator changed.
class CurrentTrackScope extends InheritedModel<_TrackRow> {
  const CurrentTrackScope({
    super.key,
    required this.path,
    required this.playlistEntry,
    required this.playing,
    required super.child,
  });

  final String? path;
  final (String, String)? playlistEntry;
  final bool playing;

  static bool? playingOf(
    BuildContext context,
    String path, {
    (String, String)? entry,
    bool matchPath = true,
  }) {
    final row = (path: path, entry: entry, matchPath: matchPath);
    return InheritedModel.inheritFrom<CurrentTrackScope>(
      context,
      aspect: row,
    )?._rowState(row);
  }

  bool? _rowState(_TrackRow row) {
    if (row.path != path) return null;
    if (row.entry != null && row.entry!.$1 == playlistEntry?.$1) {
      return row.entry == playlistEntry ? playing : null;
    }
    return row.matchPath ? playing : null;
  }

  @override
  bool updateShouldNotify(CurrentTrackScope oldWidget) =>
      path != oldWidget.path ||
      playlistEntry != oldWidget.playlistEntry ||
      playing != oldWidget.playing;

  @override
  bool updateShouldNotifyDependent(
    CurrentTrackScope oldWidget,
    Set<_TrackRow> rows,
  ) => rows.any((row) => _rowState(row) != oldWidget._rowState(row));
}

class TrackPlaybackIndicator extends StatelessWidget {
  const TrackPlaybackIndicator({
    super.key,
    required this.playing,
    this.appearance,
  });

  final bool playing;
  final AuroraAppearance? appearance;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Icon(
      playing ? Icons.play_arrow_rounded : Icons.pause_rounded,
      semanticLabel: playing ? 'Сейчас воспроизводится' : 'На паузе',
      color: appearance?.accent ?? Theme.of(context).colorScheme.primary,
      size: 17,
    ),
  );
}

Color? currentTrackTint(AuroraAppearance? appearance, bool? playing) =>
    playing == null ? null : appearance?.accent.withValues(alpha: .14);

Widget trackTitle(
  Widget title, {
  required bool? playing,
  required Key indicatorKey,
  AuroraAppearance? appearance,
}) => playing == null
    ? title
    : Row(
        children: [
          TrackPlaybackIndicator(
            key: indicatorKey,
            playing: playing,
            appearance: appearance,
          ),
          Expanded(child: title),
        ],
      );

/// Labels can refresh after an edit without reopening the audio or changing its
/// queue. Catalog lookups run only on track/catalog changes, never position ticks.
class CurrentTrackDetails extends StatefulWidget {
  const CurrentTrackDetails({
    super.key,
    required this.track,
    this.library,
    this.coverSize = 44,
    this.stacked = false,
  });
  final LocalTrack track;
  final LibraryController? library;
  final double coverSize;
  final bool stacked;
  @override
  State<CurrentTrackDetails> createState() => _CurrentTrackDetailsState();
}

class _CurrentTrackDetailsState extends State<CurrentTrackDetails> {
  LocalTrack? _catalogTrack;
  String? _coverPath;
  int _revision = -1;
  int _request = 0;
  bool _glass = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _glass = Theme.of(context).extension<GlassFinish>() != null;
    if (_glass) _publish();
  }

  void _publish() {
    if (!_glass || widget.stacked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _glass) {
        context.getInheritedWidgetOfExactType<AccentScope>()?.notifier?.select(
          _coverPath,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.library?.addListener(_catalogChanged);
    _reload();
  }

  @override
  void didUpdateWidget(CurrentTrackDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != widget.library) {
      oldWidget.library?.removeListener(_catalogChanged);
      widget.library?.addListener(_catalogChanged);
    }
    if (oldWidget.track != widget.track ||
        oldWidget.library != widget.library) {
      _catalogTrack = null;
      _coverPath = null;
      _reload();
    }
  }

  void _catalogChanged() {
    if (_revision != widget.library?.catalogRevision) _reload();
  }

  Future<void> _reload() async {
    final request = ++_request;
    final library = widget.library;
    _revision = library?.catalogRevision ?? -1;
    if (library == null) return;
    try {
      final track = await library.repository.trackByPath(
        widget.track.uri.toFilePath(),
      );
      if (!mounted || request != _request) return;
      final metadata =
          track?.metadata ??
          await library.repository.readPlaybackMetadata(
            widget.track.uri.toFilePath(),
          );
      if (mounted && request == _request)
        setState(() {
          _catalogTrack = track?.playable;
          _coverPath = metadata.coverKey == null
              ? null
              : library.repository.coverPath(metadata.coverKey!);
        });
    } catch (_) {
      // A catalog failure must never interrupt playback. Queue labels remain.
      if (mounted && request == _request)
        setState(() {
          _catalogTrack = null;
          _coverPath = null;
        });
    }
    if (mounted && request == _request) _publish();
  }

  @override
  void dispose() {
    widget.library?.removeListener(_catalogChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aurora = AuroraAppearance.of(context);
    final track =
        _catalogTrack ??
        widget.library?.labelsFor(widget.track) ??
        widget.track;
    if (widget.stacked && aurora != null) {
      final artist = track.artists.isEmpty
          ? 'Неизвестный исполнитель'
          : track.artists.join(' / ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuroraArtwork(
            appearance: aurora,
            size: widget.coverSize,
            radius: 16,
            path: _coverPath,
          ),
          const SizedBox(height: 14),
          Text(
            track.name,
            key: const Key('panel-track-title'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: aurora.ink,
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            artist,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: aurora.muted),
          ),
        ],
      );
    }
    return Row(
      children: [
        if (aurora != null)
          AuroraArtwork(
            artworkKey: const Key('now-playing-artwork'),
            appearance: aurora,
            size: widget.coverSize,
            radius: 15,
            path: _coverPath,
          )
        else
          SizedBox.square(
            dimension: widget.coverSize,
            child: AlbumArtwork(
              key: const Key('now-playing-artwork'),
              displaySize: widget.coverSize,
              path: _coverPath,
              radius: 10,
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.name,
                key: const Key('now-playing-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: aurora != null
                    ? Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: aurora.ink,
                        fontWeight: FontWeight.w600,
                      )
                    : Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                track.artists.isEmpty
                    ? 'Неизвестный исполнитель'
                    : track.artists.join(' / '),
                key: const Key('now-playing-artists'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: aurora?.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
