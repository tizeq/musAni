import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../library/library_controller.dart';
import '../library/models.dart';
import '../playlists/models.dart';
import '../playlists/playlist_repository.dart';
import 'album_artwork.dart';
import 'atmosphere.dart';
import 'aurora_scene.dart';
import 'library_widgets.dart';
import 'metadata_editor_dialog.dart';
import 'motion.dart';
import 'playlist_actions.dart';

class ArtistPage extends StatefulWidget {
  const ArtistPage({
    super.key,
    required this.artist,
    required this.library,
    required this.playlists,
    required this.onPlayQuery,
    required this.onOpenAlbum,
    required this.onBack,
  });

  final LibraryArtist artist;
  final LibraryController library;
  final PlaylistRepository playlists;
  final LibraryQueryPlayback onPlayQuery;
  final ValueChanged<LibraryAlbum> onOpenAlbum;
  final VoidCallback onBack;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  late final _results = LibraryController(widget.library.repository);
  final _searches = {
    LibraryView.tracks: TextEditingController(),
    LibraryView.albums: TextEditingController(),
  };
  final _selected = <int, LibraryTrack>{};
  Timer? _debounce;
  bool _active = false;
  bool _openingArtist = false;
  int? _revision;

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = TickerMode.valuesOf(context).enabled;
    _refresh();
  }

  void _refresh() {
    final revision = widget.library.catalogRevision;
    if (!_active || _revision == revision) return;
    final view = _revision == null ? LibraryView.tracks : _results.query.view;
    _revision = revision;
    _results.catalogRevision = revision;
    _query(view);
  }

  void _query(
    LibraryView view, {
    LibrarySort? sort,
    bool? descending,
    bool restore = false,
  }) {
    _debounce?.cancel();
    _selected.clear();
    final saved = _results.queryFor(view);
    unawaited(
      _results.search(
        LibraryQuery(
          view: view,
          artistId: widget.artist.id,
          search: _searches[view]!.text,
          sort: sort ?? saved.sort,
          descending: descending ?? saved.descending,
        ),
        restoreSection: restore,
      ),
    );
  }

  @override
  void dispose() {
    widget.library.removeListener(_refresh);
    _debounce?.cancel();
    for (final search in _searches.values) {
      search.dispose();
    }
    _results.dispose();
    super.dispose();
  }

  Future<void> _playArtist() async {
    if (_openingArtist) return;
    setState(() => _openingArtist = true);
    try {
      final saved = _results.queryFor(LibraryView.tracks);
      await widget.onPlayQuery(
        LibraryQuery(
          view: LibraryView.tracks,
          artistId: widget.artist.id,
          sort: saved.sort,
          descending: saved.descending,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingArtist = false);
    }
  }

  Widget _track(
    LibraryTrack track, {
    GlassColors? glass,
    AuroraAppearance? aurora,
  }) {
    final tile = LibraryTrackTile(
      glass: glass,
      aurora: aurora,
      track: track,
      currentTrackKey: ValueKey('artist-current-track-${track.id}'),
      coverPath: track.metadata.coverKey == null
          ? null
          : widget.library.repository.coverPath(track.metadata.coverKey!),
      onTap: () => widget.onPlayQuery(_results.query, startPath: track.path),
      onEdit: () => editTrackMetadata(context, track, widget.library),
      onAddToPlaylist: () => addToPlaylist(context, widget.playlists, [
        PlaylistTrackRef.fromLibrary(track),
      ]),
      selected: _selected.containsKey(track.id),
      onToggleSelection: () => setState(() {
        if (_selected.remove(track.id) == null) _selected[track.id] = track;
      }),
    );
    if (aurora == null) return tile;
    return AuroraTrackSurface(appearance: aurora, child: tile);
  }

  Widget _album(LibraryAlbum album) => ListTile(
    leading: SizedBox.square(
      dimension: 44,
      child: AlbumArtwork(
        displaySize: 44,
        path: album.coverKey == null
            ? null
            : widget.library.repository.coverPath(album.coverKey!),
      ),
    ),
    title: Text(album.title),
    subtitle: Text(
      '${album.trackCount} треков · ${libraryTime(album.durationMs)}',
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => widget.onOpenAlbum(album),
  );

  Widget _list(
    LibraryQuery query, {
    Widget? header,
    GlassColors? glass,
    AuroraAppearance? aurora,
  }) {
    final result = _results.result;
    if (_results.error case final error?) {
      if (header == null)
        return Center(
          child: TextButton(
            onPressed: () => _query(query.view),
            child: Text(error),
          ),
        );
    }
    if (header == null && result.length == 0) {
      return Center(
        child: _results.loading
            ? const LibraryLoadingIndicator()
            : const Text('Ничего не найдено'),
      );
    }
    final populated = _results.error == null && result.length > 0;
    final offset = header == null ? 0 : 1;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (populated && notification.metrics.extentAfter < 600)
          unawaited(_results.loadMore());
        return false;
      },
      child: ListView.builder(
        key: PageStorageKey((widget.artist.id, query.criteria)),
        padding: header == null
            ? const EdgeInsets.symmetric(horizontal: 12)
            : const EdgeInsets.fromLTRB(17, 10, 17, 14),
        itemCount:
            offset +
            (populated ? result.length + (_results.loading ? 1 : 0) : 1),
        itemBuilder: (context, index) {
          if (header != null && index == 0) return header;
          if (!populated) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _results.error != null
                    ? TextButton(
                        onPressed: () => _query(query.view),
                        child: Text(_results.error!),
                      )
                    : _results.loading
                    ? const SizedBox(
                        height: 40,
                        child: LibraryLoadingIndicator(),
                      )
                    : Text(
                        'Ничего не найдено',
                        style: TextStyle(color: aurora?.muted),
                      ),
              ),
            );
          }
          final item = index - offset;
          if (item == result.length)
            return const BusyIndicator.bar(minHeight: 2);
          return query.view == LibraryView.tracks
              ? _track(result.tracks[item], glass: glass, aurora: aurora)
              : _album(result.albums[item]);
        },
      ),
    );
  }

  Widget _search(LibraryQuery query, {AuroraAppearance? aurora}) => TextField(
    key: const Key('artist-search'),
    controller: _searches[query.view],
    style: aurora == null ? null : TextStyle(color: aurora.ink, fontSize: 13),
    decoration: InputDecoration(
      hintText: 'Поиск у исполнителя',
      prefixIcon: const Icon(Icons.search),
      isDense: true,
      hintStyle: aurora == null ? null : TextStyle(color: aurora.muted),
      prefixIconColor: aurora?.muted,
      fillColor: aurora?.plate.withValues(alpha: .52),
    ),
    onChanged: (_) {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 250),
        () => _query(query.view),
      );
    },
  );

  Widget _sort(
    LibraryQuery query, {
    GlassColors? glass,
    AuroraAppearance? aurora,
  }) => LibrarySortControls(
    query: query,
    glass: glass,
    aurora: aurora,
    onSort: (sort) => _query(query.view, sort: sort),
    onReverse: () => _query(query.view, descending: !query.descending),
  );

  Widget _selection({GlassColors? glass}) => TrackSelectionBar(
    selected: _selected.values.toList(),
    repository: widget.playlists,
    glass: glass,
    onClear: () {
      if (mounted) setState(_selected.clear);
    },
  );

  Widget _auroraHeader(
    LibraryQuery query,
    AuroraAppearance aurora,
    GlassColors? glass,
  ) {
    final artist = widget.artist;
    final compact = MediaQuery.sizeOf(context).height < 680;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          style: aurora.iconButton(context),
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            final coverSize = (box.maxWidth * .40).clamp(
              62.0,
              compact ? 112.0 : 206.0,
            );
            return Row(
              children: [
                AuroraArtwork(
                  key: const Key('artist-aurora-cover'),
                  appearance: aurora,
                  size: coverSize,
                  radius: box.maxWidth >= 520 ? 23 : 15,
                  path: artist.coverKey == null
                      ? null
                      : widget.library.repository.coverPath(artist.coverKey!),
                ),
                SizedBox(width: box.maxWidth >= 520 ? 24 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ИСПОЛНИТЕЛЬ',
                        style: TextStyle(
                          color: aurora.muted,
                          fontSize: 10,
                          letterSpacing: 2.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        artist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: aurora.ink,
                          fontSize: compact || box.maxWidth < 440 ? 27 : 41,
                          fontWeight: FontWeight.w700,
                          height: 1.08,
                          letterSpacing: -.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${libraryAlbumCount(artist.albumCount)} · ${libraryTrackCount(artist.trackCount)}',
                        style: TextStyle(color: aurora.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('artist-play-all'),
                        style: FilledButton.styleFrom(
                          backgroundColor: aurora.accent,
                          foregroundColor: aurora.dark
                              ? const Color(0xff112739)
                              : Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: box.maxWidth >= 520 ? 14 : 8,
                            vertical: 9,
                          ),
                        ),
                        onPressed: _openingArtist || artist.trackCount == 0
                            ? null
                            : _playArtist,
                        icon: const Icon(Icons.play_arrow_rounded, size: 17),
                        label: const Text(
                          'Воспроизвести',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final view in [LibraryView.tracks, LibraryView.albums])
              Semantics(
                selected: query.view == view,
                child: TextButton(
                  style:
                      TextButton.styleFrom(
                        foregroundColor: query.view == view
                            ? aurora.accent
                            : aurora.muted,
                      ).copyWith(
                        overlayColor: WidgetStateProperty.resolveWith(
                          aurora.interaction,
                        ),
                      ),
                  onPressed: query.view == view
                      ? null
                      : () => _query(view, restore: true),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        view == LibraryView.tracks ? 'Треки' : 'Альбомы',
                        style: TextStyle(
                          color: query.view == view
                              ? aurora.accent
                              : aurora.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 30,
                        height: 2,
                        child: ColoredBox(
                          color: query.view == view
                              ? aurora.accent
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Divider(color: aurora.frame, height: 1),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _search(query, aurora: aurora)),
            _sort(query, glass: glass, aurora: aurora),
          ],
        ),
        if (_selected.isNotEmpty) _selection(glass: glass),
        const SizedBox(height: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final aurora = AuroraAppearance.of(context);
    if (aurora != null) {
      final glass = GlassColors.of(context);
      return Material(
        key: const Key('artist-aurora'),
        type: MaterialType.transparency,
        child: ListenableBuilder(
          listenable: _results,
          builder: (context, _) => _list(
            _results.query,
            header: _auroraHeader(_results.query, aurora, glass),
            glass: glass,
            aurora: aurora,
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: Text(widget.artist.name),
        backgroundColor: Colors.transparent,
      ),
      body: ListenableBuilder(
        listenable: _results,
        builder: (context, _) {
          final query = _results.query;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final view in [LibraryView.tracks, LibraryView.albums])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            view == LibraryView.tracks ? 'Треки' : 'Альбомы',
                          ),
                          selected: query.view == view,
                          chipAnimationStyle: reducedChipStyle(context),
                          onSelected: (selected) {
                            if (selected) _query(view, restore: true);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(child: _search(query)),
                    _sort(query),
                  ],
                ),
              ),
              if (_selected.isNotEmpty) _selection(),
              Expanded(child: _list(query)),
            ],
          );
        },
      ),
    );
  }
}
