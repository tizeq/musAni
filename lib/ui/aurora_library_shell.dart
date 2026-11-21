import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../library/library_controller.dart';
import '../library/models.dart';
import '../settings/settings_controller.dart';
import 'aurora_scene.dart';
import 'library_widgets.dart';
import 'motion.dart';

bool panelIsOpen(CollectionPanelSettings panel, {required bool wide}) =>
    wide ? panel.open ?? true : panel.compactOpen;

class AuroraWindowControls {
  const AuroraWindowControls({
    required this.collection,
    required this.toggleCollection,
    required this.selectPanelMode,
    required this.resizePanel,
    required this.revealContent,
    required this.onOpenFiles,
    required this.queue,
    required this.currentTrack,
    this.onSettings,
  });

  final ValueListenable<CollectionPanelSettings> collection;
  final VoidCallback toggleCollection;
  final ValueChanged<CollectionPanelMode> selectPanelMode;
  final ValueChanged<double> resizePanel;
  final VoidCallback revealContent;
  final VoidCallback onOpenFiles;
  final VoidCallback? onSettings;
  final Widget queue;
  final Widget currentTrack;
}

class AuroraLibraryShell extends StatelessWidget {
  const AuroraLibraryShell({
    super.key,
    required this.appearance,
    required this.controls,
    required this.library,
    required this.tabs,
    required this.navigation,
    required this.content,
    required this.onSearch,
    required this.onSources,
    required this.onRefresh,
    required this.onAddFolder,
    required this.onOpenAlbum,
    required this.onViewAlbums,
    required this.albumsVisible,
    this.activeAlbumId,
  });

  static const panelBreakpoint = 1220.0;
  static const sidebarBreakpoint = 900.0;

  final AuroraAppearance appearance;
  final AuroraWindowControls? controls;
  final LibraryController library;
  final Widget tabs;
  final Widget navigation;
  final Widget content;
  final VoidCallback onSearch;
  final VoidCallback onSources;
  final VoidCallback? onRefresh;
  final VoidCallback? onAddFolder;
  final ValueChanged<LibraryAlbum> onOpenAlbum;
  final VoidCallback onViewAlbums;
  final bool albumsVisible;
  final String? activeAlbumId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final sidebar = box.maxWidth >= sidebarBreakpoint;
        final wide = box.maxWidth >= panelBreakpoint;
        final compact = box.maxWidth < 560;
        final window = controls;
        final sideWidth = wide ? 228.0 : 176.0;
        Widget frame(CollectionPanelSettings? state) {
          final collection = state != null && panelIsOpen(state, wide: wide);
          final center = window == null || state == null
              ? content
              : _CollectionViewport(
                  wide: wide,
                  open: collection,
                  reduceMotion: MediaQuery.disableAnimationsOf(context),
                  preferredWidth: state.width ?? box.maxWidth * .465,
                  bottomInset: wide && box.maxHeight >= 700 ? 30 : 0,
                  onResize: window.resizePanel,
                  onDismiss: window.toggleCollection,
                  child: content,
                  panel: RepaintBoundary(
                    child: AuroraCollection(
                      appearance: appearance,
                      library: library,
                      mode: state.mode,
                      queue: window.queue,
                      currentTrack: window.currentTrack,
                      albumsVisible: albumsVisible,
                      activeAlbumId: activeAlbumId,
                      compact: !wide,
                      onOpenAlbum: onOpenAlbum,
                      onViewAlbums: onViewAlbums,
                      onClose: window.toggleCollection,
                      onMode: window.selectPanelMode,
                    ),
                  ),
                );
          return Padding(
            padding: EdgeInsets.fromLTRB(
              sidebar ? 12 : 8,
              10,
              sidebar ? 12 : 8,
              4,
            ),
            child: Column(
              children: [
                SizedBox(
                  key: const Key('aurora-window-header'),
                  height: 56,
                  child: Row(
                    children: [
                      SizedBox(
                        width: sidebar
                            ? sideWidth + 12
                            : compact
                            ? 32
                            : 122,
                        child: Padding(
                          padding: EdgeInsets.only(left: sidebar ? 17 : 0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.graphic_eq_rounded,
                                size: sidebar ? 30 : 24,
                                color: appearance.dark
                                    ? const Color(0xfff1bbff)
                                    : appearance.accent,
                                semanticLabel: compact ? 'musAni' : null,
                              ),
                              if (!compact) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'musAni',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: appearance.ink,
                                      fontSize: sidebar ? 24 : 19,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Expanded(child: tabs),
                      _action(context, 'Поиск', Icons.search_rounded, onSearch),
                      if (!compact)
                        _action(
                          context,
                          'Добавить папку',
                          Icons.create_new_folder_outlined,
                          onAddFolder,
                        ),
                      if (window != null)
                        _action(
                          context,
                          'Коллекция и очередь',
                          Icons.queue_music_rounded,
                          window.toggleCollection,
                          selected: collection,
                        ),
                      if (!compact && window?.onSettings != null)
                        _action(
                          context,
                          'Настройки',
                          Icons.settings_outlined,
                          window!.onSettings,
                        ),
                      PopupMenuButton<VoidCallback>(
                        tooltip: 'Действия библиотеки',
                        icon: const Icon(Icons.more_horiz_rounded),
                        style: appearance.iconButton(context),
                        popUpAnimationStyle: reducedAnimationStyle(context),
                        onSelected: (action) => action(),
                        itemBuilder: (_) => [
                          if (compact) _menuItem('Добавить папку', onAddFolder),
                          _menuItem('Папки библиотеки', onSources),
                          _menuItem('Обновить библиотеку', onRefresh),
                          if (window != null)
                            _menuItem('Открыть файлы', window.onOpenFiles),
                          if (compact && window?.onSettings != null)
                            _menuItem('Настройки', window!.onSettings),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (!sidebar) navigation,
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (sidebar) ...[
                        SizedBox(width: sideWidth, child: navigation),
                        SizedBox(width: wide ? 20 : 12),
                      ],
                      Expanded(child: center),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return window == null
            ? frame(null)
            : ValueListenableBuilder(
                valueListenable: window.collection,
                builder: (context, value, _) => frame(value),
              );
      },
    );
  }

  Widget _action(
    BuildContext context,
    String tooltip,
    IconData icon,
    VoidCallback? action, {
    bool selected = false,
  }) => IconButton(
    tooltip: tooltip,
    isSelected: selected,
    style: appearance.iconButton(context),
    icon: Icon(icon, color: selected ? appearance.accent : null),
    onPressed: action,
  );

  PopupMenuItem<VoidCallback> _menuItem(String label, VoidCallback? action) =>
      PopupMenuItem(value: action, enabled: action != null, child: Text(label));
}

class _CollectionViewport extends StatefulWidget {
  const _CollectionViewport({
    required this.wide,
    required this.open,
    required this.reduceMotion,
    required this.preferredWidth,
    required this.bottomInset,
    required this.onResize,
    required this.onDismiss,
    required this.child,
    required this.panel,
  });

  final bool wide;
  final bool open;
  final bool reduceMotion;
  final double preferredWidth;
  final double bottomInset;
  final ValueChanged<double> onResize;
  final VoidCallback onDismiss;
  final Widget child;
  final Widget panel;

  @override
  State<_CollectionViewport> createState() => _CollectionViewportState();
}

class _CollectionViewportState extends State<_CollectionViewport>
    with SingleTickerProviderStateMixin {
  static const _grip = 18.0;
  static const _minWidth = 286.0;
  static const _drawerWidth = 420.0;
  double? _dragWidth;
  late final _reveal =
      AnimationController(
        duration: const Duration(milliseconds: 140),
        value: widget.open ? 1 : 0,
        vsync: this,
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed && !widget.open)
          setState(() {});
      });

  @override
  void didUpdateWidget(_CollectionViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wide != widget.wide) _dragWidth = null;
    if (widget.reduceMotion || oldWidget.wide != widget.wide) {
      if (_reveal.isAnimating || _reveal.value != (widget.open ? 1 : 0)) {
        _reveal.value = widget.open ? 1 : 0;
      }
    } else if (oldWidget.open != widget.open) {
      if (widget.open) {
        _reveal.forward();
      } else {
        _reveal.reverse();
      }
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.wide && !widget.open && _reveal.isDismissed) return widget.child;
    return LayoutBuilder(
      builder: (context, box) {
        final maxWidth = widget.wide
            ? (box.maxWidth - 360 - _grip).clamp(_minWidth, box.maxWidth)
            : box.maxWidth;
        double bound(double width) => width.clamp(_minWidth, maxWidth);
        final width = widget.wide
            ? bound(_dragWidth ?? widget.preferredWidth)
            : (box.maxWidth - 52).clamp(0.0, _drawerWidth);
        final drawerOpen = widget.open && !widget.wide;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              right: widget.wide && widget.open ? width + _grip : 0,
              child: ExcludeFocus(
                excluding: drawerOpen,
                child: ExcludeSemantics(
                  excluding: drawerOpen,
                  child: widget.child,
                ),
              ),
            ),
            if (drawerOpen)
              Positioned.fill(
                child: ModalBarrier(
                  key: const Key('collection-drawer-barrier'),
                  color: Theme.of(context).colorScheme.scrim
                      .withValues(alpha: .28),
                  semanticsLabel: 'Закрыть панель коллекции',
                  onDismiss: widget.onDismiss,
                ),
              ),
            Positioned(
              top: 0,
              bottom: widget.bottomInset,
              right: 0,
              width: width,
              child: AnimatedBuilder(
                animation: _reveal,
                child: widget.panel,
                builder: (context, panel) {
                  if (!widget.open && _reveal.isDismissed)
                    return const SizedBox.shrink();
                  return IgnorePointer(
                    ignoring: !widget.open,
                    child: ExcludeSemantics(
                      excluding: !widget.open,
                      child: ExcludeFocus(
                        excluding: !widget.open,
                        child: ClipRect(
                          clipBehavior: _reveal.isCompleted
                              ? Clip.none
                              : Clip.hardEdge,
                          clipper: _CollectionReveal(_reveal),
                          child: panel,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.wide && widget.open)
              Positioned(
                top: 0,
                bottom: widget.bottomInset,
                right: width,
                width: _grip,
                child: Semantics(
                  label: 'Ширина панели коллекции',
                  value: '${width.round()} px',
                  increasedValue: width < maxWidth
                      ? '${bound(width + 24).round()} px'
                      : null,
                  decreasedValue: width > _minWidth
                      ? '${bound(width - 24).round()} px'
                      : null,
                  onIncrease: width < maxWidth
                      ? () => widget.onResize(bound(width + 24))
                      : null,
                  onDecrease: width > _minWidth
                      ? () => widget.onResize(bound(width - 24))
                      : null,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      key: const Key('collection-resize-handle'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (_) {
                        if (_reveal.isAnimating) _reveal.value = 1;
                        setState(() => _dragWidth = width);
                      },
                      onHorizontalDragUpdate: (event) => setState(
                        () => _dragWidth = bound(
                          (_dragWidth ?? width) - event.delta.dx,
                        ),
                      ),
                      onHorizontalDragEnd: (_) {
                        final width = _dragWidth;
                        if (width != null) widget.onResize(width);
                        setState(() => _dragWidth = null);
                      },
                      onHorizontalDragCancel: () =>
                          setState(() => _dragWidth = null),
                      child: Center(
                        child: Container(
                          width: 1,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AuroraAppearance.of(context)?.frame,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CollectionReveal extends CustomClipper<Rect> {
  _CollectionReveal(this.animation) : super(reclip: animation);

  final Animation<double> animation;

  @override
  Rect getClip(Size size) {
    final width = size.width * Curves.easeOutCubic.transform(animation.value);
    return Rect.fromLTWH(size.width - width, 0, width, size.height);
  }

  @override
  bool shouldReclip(_CollectionReveal oldClipper) =>
      oldClipper.animation != animation;
}

class AuroraCollection extends StatelessWidget {
  const AuroraCollection({
    super.key,
    required this.appearance,
    required this.library,
    required this.mode,
    required this.queue,
    required this.currentTrack,
    required this.albumsVisible,
    required this.onOpenAlbum,
    required this.onViewAlbums,
    required this.onClose,
    required this.onMode,
    required this.compact,
    this.activeAlbumId,
  });

  final AuroraAppearance appearance;
  final LibraryController library;
  final CollectionPanelMode mode;
  final Widget queue;
  final Widget currentTrack;
  final bool albumsVisible;
  final String? activeAlbumId;
  final ValueChanged<LibraryAlbum> onOpenAlbum;
  final VoidCallback onViewAlbums;
  final VoidCallback onClose;
  final ValueChanged<CollectionPanelMode> onMode;
  final bool compact;

  @override
  Widget build(BuildContext context) => AuroraSurface(
    key: const Key('aurora-collection'),
    appearance: appearance,
    radius: 26,
    opacity: compact
        ? (appearance.dark ? .94 : .96)
        : (appearance.dark ? .40 : .58),
    highlight: 1.08,
    child: Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.library_music_outlined, color: appearance.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Коллекция',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: appearance.ink,
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть панель коллекции',
                  style: appearance.iconButton(context),
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final tab in CollectionPanelMode.values)
                  Expanded(
                    child: Semantics(
                      selected: mode == tab,
                      child: TextButton(
                        key: ValueKey('collection-mode-${tab.name}'),
                        onPressed: () => onMode(tab),
                        style:
                            TextButton.styleFrom(
                              foregroundColor: mode == tab
                                  ? appearance.accent
                                  : appearance.ink,
                              backgroundColor: mode == tab
                                  ? appearance.accent.withValues(alpha: .12)
                                  : null,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 6,
                              ),
                              animationDuration: Duration.zero,
                            ).copyWith(
                              overlayColor: WidgetStateProperty.resolveWith(
                                appearance.interaction,
                              ),
                            ),
                        child: Text(switch (tab) {
                          CollectionPanelMode.collection => 'Коллекция',
                          CollectionPanelMode.queue => 'Очередь',
                          CollectionPanelMode.currentTrack => 'Текущий трек',
                        }, textAlign: TextAlign.center),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: switch (mode) {
                CollectionPanelMode.queue => AuroraSurface(
                  appearance: appearance,
                  radius: 18,
                  opacity: appearance.dark ? .32 : .50,
                  highlight: .17,
                  child: queue,
                ),
                CollectionPanelMode.currentTrack => currentTrack,
                CollectionPanelMode.collection => ListView(
                  padding: const EdgeInsets.only(top: 4),
                  children: [
                    _CollectionAlbums(
                      library: library,
                      appearance: appearance,
                      hidden: albumsVisible,
                      omittedAlbumId: activeAlbumId,
                      onOpenAlbum: onOpenAlbum,
                    ),
                    if (!albumsVisible) const SizedBox(height: 6),
                    if (albumsVisible)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          '${libraryAlbumCount(library.status.albumCount)} · ${libraryTrackCount(library.status.trackCount)}',
                          style: TextStyle(color: appearance.muted),
                        ),
                      )
                    else
                      TextButton.icon(
                        onPressed: onViewAlbums,
                        icon: const Icon(Icons.album_outlined),
                        label: const Text('Все альбомы'),
                      ),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _CollectionAlbums extends StatefulWidget {
  const _CollectionAlbums({
    required this.library,
    required this.appearance,
    required this.onOpenAlbum,
    required this.omittedAlbumId,
    required this.hidden,
  });
  final LibraryController library;
  final AuroraAppearance appearance;
  final ValueChanged<LibraryAlbum> onOpenAlbum;
  final String? omittedAlbumId;
  final bool hidden;

  @override
  State<_CollectionAlbums> createState() => _CollectionAlbumsState();
}

class _CollectionAlbumsState extends State<_CollectionAlbums> {
  int _revision = -1;
  List<LibraryAlbum> _albums = const [];

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_refresh);
    _refresh();
  }

  @override
  void didUpdateWidget(_CollectionAlbums oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hidden && !widget.hidden) _refresh();
  }

  @override
  void dispose() {
    widget.library.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    final library = widget.library;
    if (widget.hidden ||
        !library.initialized ||
        _revision == library.catalogRevision)
      return;
    final revision = _revision = library.catalogRevision;
    unawaited(_load(revision));
  }

  Future<void> _load(int revision) async {
    try {
      final result = await widget.library.repository.query(
        const LibraryQuery(limit: 4),
      );
      if (mounted && revision == _revision)
        setState(() => _albums = result.albums);
    } catch (_) {
      // The preview is supplementary to the existing catalog and queue.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hidden) return const SizedBox.shrink();
    final albums = _albums
        .where((album) => album.id != widget.omittedAlbumId)
        .take(3)
        .toList();
    if (albums.isEmpty) return const SizedBox.shrink();
    final appearance = widget.appearance;
    return AuroraSurface(
      appearance: appearance,
      radius: 18,
      opacity: appearance.dark ? .32 : .50,
      highlight: .28,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Альбомы',
              style: TextStyle(
                color: appearance.ink,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < 3; index++) ...[
                  if (index != 0) const SizedBox(width: 10),
                  Expanded(
                    child: index < albums.length
                        ? _album(albums[index], appearance)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _album(LibraryAlbum album, AuroraAppearance appearance) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => widget.onOpenAlbum(album),
    child: LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: box.maxWidth,
            height: (box.maxWidth * .84).clamp(50, 185),
            child: AuroraArtwork(
              appearance: appearance,
              size: box.maxWidth,
              radius: 12,
              path: album.coverKey == null
                  ? null
                  : widget.library.repository.coverPath(album.coverKey!),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: appearance.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            album.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: appearance.muted, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}
