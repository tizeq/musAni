import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../library/models.dart';
import 'album_artwork.dart';
import 'design_system.dart';
import 'motion.dart';
import 'atmosphere.dart';
import 'aurora_scene.dart';
import 'current_track_details.dart';

/// A short request should not flash a spinner between two sets of results.
class LibraryLoadingIndicator extends StatefulWidget {
  const LibraryLoadingIndicator({super.key});

  @override
  State<LibraryLoadingIndicator> createState() =>
      _LibraryLoadingIndicatorState();
}

class _LibraryLoadingIndicatorState extends State<LibraryLoadingIndicator> {
  late final Timer _delay;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _delay = Timer(
      const Duration(milliseconds: 150),
      () => setState(() => _visible = true),
    );
  }

  @override
  void dispose() {
    _delay.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _visible ? const Center(child: BusyIndicator()) : const SizedBox.expand();
}

typedef LibraryPlayback = Future<void> Function(
  List<LibraryTrack> tracks,
  int index,
);
typedef LibraryQueryPlayback = Future<void> Function(
  LibraryQuery query, {
  String? startPath,
});

class LibrarySortControls extends StatelessWidget {
  const LibrarySortControls({
    super.key,
    required this.query,
    required this.onSort,
    required this.onReverse,
    this.glass,
    this.aurora,
  });

  final LibraryQuery query;
  final ValueChanged<LibrarySort> onSort;
  final VoidCallback onReverse;
  final GlassColors? glass;
  final AuroraAppearance? aurora;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PopupMenuButton<LibrarySort>(
        style: aurora?.iconButton(context) ?? glass?.iconStyle(),
        color: glass?.menuColor,
        shape: glass?.menuShape,
        surfaceTintColor: glass == null ? null : Colors.transparent,
        popUpAnimationStyle: reducedAnimationStyle(context),
        tooltip: 'Сортировка',
        initialValue: query.sort,
        onSelected: onSort,
        icon: const Icon(Icons.sort),
        itemBuilder: (_) => [
          for (final sort in LibrarySort.values)
            CheckedPopupMenuItem(
              value: sort,
              checked: sort == query.sort,
              child: Text(switch (sort) {
                LibrarySort.title => 'По названию',
                LibrarySort.artist => 'По исполнителю',
                LibrarySort.year => 'По году',
                LibrarySort.added => 'По добавлению',
              }),
            ),
        ],
      ),
      IconButton(
        style: aurora?.iconButton(context) ?? glass?.iconStyle(),
        tooltip: query.descending ? 'По возрастанию' : 'По убыванию',
        onPressed: onReverse,
        icon: Icon(query.descending ? Icons.south : Icons.north),
      ),
    ],
  );
}

String libraryTime(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String libraryTrackCount(int count) =>
    _libraryCount(count, 'трек', 'трека', 'треков');

String libraryAlbumCount(int count) =>
    _libraryCount(count, 'альбом', 'альбома', 'альбомов');

String _libraryCount(int count, String one, String few, String many) {
  final last = count % 10;
  final teen = count % 100 >= 11 && count % 100 <= 14;
  final suffix = !teen && last == 1
      ? one
      : !teen && last >= 2 && last <= 4
      ? few
      : many;
  return '$count $suffix';
}

class LibraryAlbumCard extends StatelessWidget {
  const LibraryAlbumCard({
    required this.album,
    required this.coverSize,
    required this.onOpen,
    required this.onPlay,
    this.coverPath,
    this.aurora,
  });
  final LibraryAlbum album;
  final double coverSize;
  final String? coverPath;
  final VoidCallback onOpen;
  final VoidCallback onPlay;
  final AuroraAppearance? aurora;

  @override
  Widget build(BuildContext context) {
    if (aurora case final appearance?) return _auroraCard(context, appearance);
    final glass = GlassColors.of(context);
    if (glass != null) return _GlassAlbum(card: this, glass: glass);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(MusaniDesign.space * 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AlbumArtwork(path: coverPath, displaySize: coverSize),
                    if (album.year > 0)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface
                                .withValues(alpha: .9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            child: Text(
                              '${album.year}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(letterSpacing: .4),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 7,
                      bottom: 7,
                      child: IconButton.filled(
                        tooltip: 'Воспроизвести альбом ${album.title}',
                        onPressed: onPlay,
                        icon: const Icon(Icons.play_arrow),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                album.artist.isEmpty
                    ? 'Исполнитель альбома не указан'
                    : album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${libraryTrackCount(album.trackCount)} · ${libraryTime(album.durationMs)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _auroraCard(
    BuildContext context,
    AuroraAppearance appearance,
  ) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      overlayColor: WidgetStateProperty.resolveWith(appearance.interaction),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AuroraArtwork(
                    appearance: appearance,
                    size: coverSize,
                    radius: 14,
                    path: coverPath,
                  ),
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: IconButton(
                      tooltip: 'Воспроизвести альбом ${album.title}',
                      style: appearance
                          .iconButton(context)
                          .copyWith(
                            foregroundColor: const WidgetStatePropertyAll(
                              Colors.white,
                            ),
                            backgroundColor: const WidgetStatePropertyAll(
                              Color(0xcc152339),
                            ),
                          ),
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: appearance.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              album.artist.isEmpty
                  ? 'Исполнитель альбома не указан'
                  : album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: appearance.muted, fontSize: 12),
            ),
            Text(
              '${album.year > 0 ? '${album.year} · ' : ''}${libraryTrackCount(album.trackCount)} · ${libraryTime(album.durationMs)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: appearance.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GlassAlbum extends StatefulWidget {
  const _GlassAlbum({required this.card, required this.glass});
  final LibraryAlbumCard card;
  final GlassColors glass;
  @override
  State<_GlassAlbum> createState() => _GlassAlbumState();
}

class _GlassAlbumState extends State<_GlassAlbum> {
  bool hover = false;
  bool pressed = false;
  @override
  Widget build(BuildContext context) {
    final card = widget.card, g = widget.glass, album = card.album;
    final reduced = MediaQuery.disableAnimationsOf(context) || g.lite;
    return AnimatedScale(
      scale: pressed
          ? 0.977
          : hover
          ? 1.012
          : 1,
      duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        color: g.base,
        child: InkWell(
          onTap: card.onOpen,
          onHover: (v) => setState(() => hover = v),
          onHighlightChanged: (v) => setState(() => pressed = v),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AlbumArtwork(
                path: card.coverPath,
                displaySize: card.coverSize,
                radius: 0,
              ),
              const CustomPaint(painter: SleeveShade()),
              Positioned(
                left: 14,
                right: 14,
                bottom: 13,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      album.artist.isEmpty
                          ? 'Исполнитель альбома не указан'
                          : album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xffd7e1e9),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      '${libraryTrackCount(album.trackCount)} · ${libraryTime(album.durationMs)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xffbdcbd6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (album.year > 0)
                Positioned(
                  top: 12,
                  left: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xa5151b26),
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      child: Text(
                        '${album.year}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 9,
                top: 7,
                child: IconButton.filled(
                  tooltip: 'Воспроизвести альбом ${album.title}',
                  onPressed: card.onPlay,
                  style:
                      IconButton.styleFrom(
                        backgroundColor: const Color(0xc91c2736),
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                      ).copyWith(
                        overlayColor: WidgetStateProperty.resolveWith(
                          g.controlOverlay,
                        ),
                      ),
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: hover ? g.controlEdge : Colors.white24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LibraryTrackTile extends StatelessWidget {
  const LibraryTrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.coverPath,
    this.onEdit,
    this.onAddToPlaylist,
    this.onToggleSelection,
    this.selected = false,
    this.glass,
    this.aurora,
    this.currentTrackKey,
  });
  final LibraryTrack track;
  final VoidCallback onTap;
  final String? coverPath;
  final VoidCallback? onEdit;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onToggleSelection;
  final bool selected;
  final GlassColors? glass;
  final AuroraAppearance? aurora;
  final Key? currentTrackKey;

  bool get _editable =>
      onEdit != null &&
      ['.mp3', '.flac'].contains(p.extension(track.path).toLowerCase());

  List<PopupMenuEntry<String>> _menuItems() => [
    if (onEdit != null)
      PopupMenuItem(
        value: 'edit',
        enabled: _editable,
        child: const Text('Редактировать метаданные'),
      ),
    if (onAddToPlaylist != null)
      const PopupMenuItem(
        value: 'playlist',
        child: Text('Добавить в плейлист'),
      ),
  ];
  void _action(String? action) {
    if (action == 'edit') onEdit?.call();
    if (action == 'playlist') onAddToPlaylist?.call();
  }

  Future<void> _contextMenu(BuildContext context, Offset global) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final point = overlay.globalToLocal(global);
    final selected = await showMenu<String>(
      color: glass?.menuColor,
      shape: glass?.menuShape,
      surfaceTintColor: glass == null ? null : Colors.transparent,
      popUpAnimationStyle: reducedAnimationStyle(context),
      context: context,
      position: RelativeRect.fromSize(
        Rect.fromLTWH(point.dx, point.dy, 0, 0),
        overlay.size,
      ),
      items: _menuItems(),
    );
    if (context.mounted) _action(selected);
  }

  @override
  Widget build(BuildContext context) => _tile(
    context,
    CurrentTrackScope.playingOf(context, track.path),
    aurora ?? AuroraAppearance.of(context),
  );

  Widget _tile(
    BuildContext context,
    bool? playing,
    AuroraAppearance? appearance,
  ) => GestureDetector(
    onSecondaryTapDown: onEdit == null && onAddToPlaylist == null
        ? null
        : (details) => _contextMenu(context, details.globalPosition),
    child: ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      selected: selected,
      tileColor: currentTrackTint(appearance, playing),
      selectedTileColor:
          currentTrackTint(appearance, playing) ?? glass?.selection,
      textColor: aurora?.ink ?? glass?.ink,
      selectedColor: aurora?.ink ?? glass?.ink,
      hoverColor:
          aurora?.interaction({WidgetState.hovered}) ??
          glass?.controlOverlay({WidgetState.hovered}),
      focusColor:
          aurora?.interaction({WidgetState.focused}) ??
          glass?.controlOverlay({WidgetState.focused}),
      splashColor:
          aurora?.interaction({WidgetState.pressed}) ??
          glass?.controlOverlay({WidgetState.pressed}),
      shape: glass == null
          ? null
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggleSelection != null)
            Checkbox(
              key: Key('select-track-${track.id}'),
              value: selected,
              activeColor: aurora?.accent ?? glass?.accent,
              checkColor: glass?.onAccent,
              onChanged: (_) => onToggleSelection!(),
            ),
          aurora != null
              ? AuroraArtwork(
                  appearance: aurora!,
                  size: 40,
                  radius: 8,
                  path: coverPath,
                )
              : SizedBox.square(
                  dimension: 40,
                  child: AlbumArtwork(
                    path: coverPath,
                    displaySize: 40,
                    radius: 8,
                  ),
                ),
        ],
      ),
      title: trackTitle(
        Text(
          track.metadata.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        indicatorKey:
            currentTrackKey ?? ValueKey('library-current-track-${track.id}'),
        playing: playing,
        appearance: appearance,
      ),
      subtitle: Text(
        track.metadata.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: glass == null
            ? null
            : TextStyle(color: aurora?.muted ?? glass?.muted, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onEdit != null || onAddToPlaylist != null)
            PopupMenuButton<String>(
              style: aurora?.iconButton(context) ?? glass?.iconStyle(),
              color: glass?.menuColor,
              shape: glass?.menuShape,
              surfaceTintColor: glass == null ? null : Colors.transparent,
              popUpAnimationStyle: reducedAnimationStyle(context),
              key: Key('track-menu-${track.id}'),
              tooltip: 'Действия трека',
              icon: Icon(
                glass == null ? Icons.more_vert : Icons.more_horiz_rounded,
              ),
              onSelected: _action,
              itemBuilder: (_) => _menuItems(),
            ),
          if (track.metadata.warning != null)
            Tooltip(
              message: track.metadata.warning!,
              child: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.warning_amber_rounded, size: 18),
              ),
            ),
          Text(
            libraryTime(track.metadata.durationMs),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: aurora?.muted),
          ),
        ],
      ),
      onTap: onTap,
    ),
  );
}
