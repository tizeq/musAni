import 'package:material_ui/material_ui.dart';

import 'aurora_scene.dart';

import '../library/library_controller.dart';
import '../library/models.dart';
import '../playlists/models.dart';
import '../playlists/playlist_repository.dart';
import 'album_artwork.dart';
import 'library_widgets.dart';
import 'metadata_editor_dialog.dart';
import 'playlist_actions.dart';
import 'motion.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({
    super.key,
    required this.album,
    required this.controller,
    required this.onPlay,
    this.playlists,
    this.onBack,
    this.onAlbumRemoved,
    this.onAlbumChanged,
  });
  final LibraryAlbum album;
  final LibraryController controller;
  final LibraryPlayback onPlay;
  final PlaylistRepository? playlists;
  final VoidCallback? onBack;
  final VoidCallback? onAlbumRemoved;
  final ValueChanged<LibraryAlbum>? onAlbumChanged;
  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  late Future<List<LibraryTrack>> _tracks;
  late LibraryAlbum _album;
  int _catalogRevision = -1;
  int _request = 0;
  bool _active = true;
  late final _playlists =
      widget.playlists ??
      PlaylistRepository(widget.controller.repository.directory);
  final _selected = <int, LibraryTrack>{};
  @override
  void initState() {
    super.initState();
    _catalogRevision = widget.controller.catalogRevision;
    widget.controller.addListener(_catalogChanged);
    _album = widget.album;
    _tracks = widget.controller.repository.albumTracks(_album.id);
  }

  Future<void> _edit(LibraryTrack track) async {
    if (!await editTrackMetadata(context, track, widget.controller) || !mounted)
      return;
    await _reload(trackId: track.id);
  }

  void _catalogChanged() {
    if (!_active || _catalogRevision == widget.controller.catalogRevision)
      return;
    _catalogRevision = widget.controller.catalogRevision;
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = TickerMode.valuesOf(context).enabled;
    _catalogChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_catalogChanged);
    super.dispose();
  }

  Future<void> _reload({int? trackId}) async {
    final request = ++_request;
    try {
      var albumId = _album.id;
      if (trackId != null) {
        final updated = await widget.controller.repository.track(trackId);
        if (!mounted || request != _request) return;
        if (updated?.albumId == null) {
          if (widget.onAlbumRemoved case final close?) {
            close();
          } else {
            Navigator.of(context).maybePop();
          }
          return;
        }
        albumId = updated!.albumId!;
      }
      final albums = await widget.controller.repository.query(
        LibraryQuery(albumId: albumId),
      );
      final tracks = await widget.controller.repository.albumTracks(albumId);
      if (mounted && request == _request) {
        final album = albums.albums.firstOrNull;
        setState(() {
          _selected.clear();
          if (album != null) _album = album;
          _tracks = Future.value(tracks);
        });
        if (album != null) widget.onAlbumChanged?.call(album);
      }
    } catch (error) {
      if (mounted && request == _request)
        showAppSnackBar(
          context,
          SnackBar(content: Text('Обновите библиотеку: $error')),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AuroraAppearance.of(context) == null
        ? null
        : Colors.transparent,
    appBar: AppBar(
      leading: widget.onBack == null
          ? null
          : BackButton(onPressed: widget.onBack),
      title: const Text('Альбом'),
      backgroundColor: Colors.transparent,
    ),
    body: FutureBuilder(
      future: _tracks,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${snapshot.error}'),
                TextButton(
                  onPressed: () => setState(() {
                    _tracks = widget.controller.repository.albumTracks(
                      _album.id,
                    );
                  }),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          );
        final tracks = snapshot.data;
        if (tracks == null) return const Center(child: BusyIndicator());
        if (tracks.isEmpty)
          return const Center(
            child: Text('Альбом больше недоступен. Обновите библиотеку.'),
          );
        final album = _album;
        final genres = tracks
            .map((track) => track.metadata.genre)
            .where((genre) => genre.isNotEmpty)
            .toSet()
            .join(' · ');
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 600;
                  final info = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'АЛЬБОМ',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(letterSpacing: 2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.title,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        album.artist.isEmpty
                            ? 'Исполнитель альбома не указан'
                            : album.artist,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${album.year > 0 ? '${album.year} · ' : ''}${tracks.length} треков · ${libraryTime(album.durationMs)}',
                      ),
                      if (genres.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(genres),
                        ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => widget.onPlay(tracks, 0),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Воспроизвести альбом'),
                      ),
                    ],
                  );
                  final coverSize = compact ? 160.0 : 210.0;
                  final artwork = SizedBox.square(
                    dimension: coverSize,
                    child: AlbumArtwork(
                      displaySize: coverSize,
                      path: album.coverKey == null
                          ? null
                          : widget.controller.repository.coverPath(
                              album.coverKey!,
                            ),
                    ),
                  );
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              artwork,
                              const SizedBox(height: 20),
                              info,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              artwork,
                              const SizedBox(width: 28),
                              Expanded(child: info),
                            ],
                          ),
                  );
                },
              ),
            ),
            if (_selected.isNotEmpty)
              SliverToBoxAdapter(
                child: TrackSelectionBar(
                  selected: _selected.values.toList(),
                  repository: _playlists,
                  onClear: () {
                    if (mounted) setState(() => _selected.clear());
                  },
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return LibraryTrackTile(
                    track: track,
                    coverPath: track.metadata.coverKey == null
                        ? null
                        : widget.controller.repository.coverPath(
                            track.metadata.coverKey!,
                          ),
                    onTap: () => widget.onPlay(tracks, index),
                    onEdit: () => _edit(track),
                    onAddToPlaylist: () => addToPlaylist(
                      this.context,
                      _playlists,
                      [PlaylistTrackRef.fromLibrary(track)],
                    ),
                    selected: _selected.containsKey(track.id),
                    onToggleSelection: () => setState(() {
                      if (_selected.containsKey(track.id)) {
                        _selected.remove(track.id);
                      } else {
                        _selected[track.id] = track;
                      }
                    }),
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
