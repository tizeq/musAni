import 'package:material_ui/material_ui.dart';

import '../library/library_controller.dart';
import '../library/models.dart';
import '../playlists/playlist_repository.dart';
import 'album_page.dart';
import 'artist_page.dart';
import 'aurora_scene.dart';
import 'library_widgets.dart';

enum _PageKind { album, artist }

class _LibraryTab {
  _LibraryTab(this.kind, this.id, this.title);
  final _PageKind kind;
  String id;
  String title;
  final key = GlobalKey();
  late final Widget page;

  IconData get icon => switch (kind) {
    _PageKind.album => Icons.album_outlined,
    _PageKind.artist => Icons.person_outline,
  };
}

class LibraryWorkspace extends StatefulWidget {
  const LibraryWorkspace({
    super.key,
    required this.library,
    required this.playlists,
    required this.onPlay,
    required this.onPlayQuery,
    required this.child,
    this.frame,
    this.onReveal,
  });

  final LibraryController library;
  final PlaylistRepository playlists;
  final LibraryPlayback onPlay;
  final LibraryQueryPlayback onPlayQuery;
  final Widget child;
  final Widget Function(
    Widget tabs,
    Widget content,
    bool catalogActive,
    String? activeAlbumId,
  )?
  frame;
  final VoidCallback? onReveal;

  @override
  State<LibraryWorkspace> createState() => LibraryWorkspaceState();
}

class LibraryWorkspaceState extends State<LibraryWorkspace> {
  static const _tabBarHeight = 42.0;
  final _tabs = <_LibraryTab>[];
  final _tabScroll = ScrollController();
  final _panes = GlobalKey();
  _LibraryTab? _active;
  double _catalogTop = 0;

  @override
  void dispose() {
    _tabScroll.dispose();
    super.dispose();
  }

  void showLibrary() => _activate(null);

  void openAlbum(LibraryAlbum album) => _open(
    _PageKind.album,
    album.id,
    album.title,
    (tab) => AlbumPage(
      album: album,
      controller: widget.library,
      onPlay: widget.onPlay,
      playlists: widget.playlists,
      onBack: showLibrary,
      onAlbumRemoved: () => _close(tab),
      onAlbumChanged: (updated) => _updateAlbum(tab, updated),
    ),
  );

  void openArtist(LibraryArtist artist) => _open(
    _PageKind.artist,
    artist.id,
    artist.name,
    (_) => ArtistPage(
      artist: artist,
      library: widget.library,
      playlists: widget.playlists,
      onPlayQuery: widget.onPlayQuery,
      onOpenAlbum: openAlbum,
      onBack: showLibrary,
    ),
  );

  void _open(
    _PageKind kind,
    String id,
    String title,
    Widget Function(_LibraryTab) buildPage,
  ) {
    final existing = _tabs.where((tab) => tab.kind == kind && tab.id == id);
    final tab = existing.firstOrNull;
    if (tab != null) {
      _activate(tab);
      _reveal(tab);
      return;
    }
    widget.onReveal?.call();
    final created = _LibraryTab(kind, id, title);
    created.page = buildPage(created);
    setState(() {
      _tabs.add(created);
      _active = created;
    });
    _reveal(created);
  }

  void _reveal(_LibraryTab tab) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = tab.key.currentContext;
      if (context != null) Scrollable.ensureVisible(context);
    });
  }

  void _activate(_LibraryTab? tab) {
    widget.onReveal?.call();
    if (_active == tab) return;
    setState(() {
      _active = tab;
      _updateCatalogInset();
    });
  }

  void _updateCatalogInset() {
    // Keep the hidden catalog at its last visible size while opening a tab.
    if (_active == null) _catalogTop = _tabs.isEmpty ? 0 : _tabBarHeight;
  }

  void _close(_LibraryTab tab) {
    setState(() {
      _tabs.remove(tab);
      if (_active == tab) _active = null;
      _updateCatalogInset();
    });
  }

  void _updateAlbum(_LibraryTab tab, LibraryAlbum album) {
    if (tab.id == album.id && tab.title == album.title) return;
    final duplicate = _tabs
        .where(
          (other) =>
              other != tab &&
              other.kind == _PageKind.album &&
              other.id == album.id,
        )
        .firstOrNull;
    if (duplicate != null) {
      if (_active == tab) {
        _activate(duplicate);
        _reveal(duplicate);
      }
      _close(tab);
    } else {
      setState(() {
        tab.id = album.id;
        tab.title = album.title;
      });
    }
  }

  Widget _pane(Widget child, bool active, Key key, {required double top}) =>
      Positioned.fill(
        key: key,
        top: top,
        child: Offstage(
          offstage: !active,
          child: ExcludeFocus(
            excluding: !active,
            child: TickerMode(enabled: active, child: child),
          ),
        ),
      );

  Widget _tabButton({
    Key? key,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    AuroraAppearance? aurora,
  }) => Semantics(
    key: key,
    selected: selected,
    child: TextButton.icon(
      onPressed: onTap,
      style: aurora != null
          ? TextButton.styleFrom(
              foregroundColor: selected ? aurora.ink : aurora.muted,
              backgroundColor: selected
                  ? aurora.accent.withValues(alpha: .15)
                  : aurora.plate.withValues(alpha: .21),
              side: BorderSide(
                color: selected
                    ? aurora.accent.withValues(alpha: .60)
                    : aurora.frame,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              animationDuration: Duration.zero,
              minimumSize: const Size(38, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith(aurora.interaction),
            )
          : selected
          ? TextButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              animationDuration: Duration.zero,
            )
          : null,
      icon: Icon(icon, size: 16),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 136),
        child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
      ),
    ),
  );

  Widget _auroraTabs(AuroraAppearance appearance) => SingleChildScrollView(
    controller: _tabScroll,
    scrollDirection: Axis.horizontal,
    child: Row(
      spacing: 8,
      children: [
        _tabButton(
          key: const Key('workspace-library'),
          label: 'Библиотека',
          icon: Icons.home_outlined,
          selected: _active == null,
          onTap: showLibrary,
          aurora: appearance,
        ),
        for (final tab in _tabs)
          Row(
            key: tab.key,
            children: [
              Tooltip(
                message: tab.title,
                child: _tabButton(
                  key: ValueKey('tab-${tab.kind.name}-${tab.id}'),
                  label: tab.title,
                  icon: tab.icon,
                  selected: _active == tab,
                  onTap: () => _activate(tab),
                  aurora: appearance,
                ),
              ),
              IconButton(
                key: ValueKey('close-${tab.kind.name}-${tab.id}'),
                tooltip: 'Закрыть вкладку «${tab.title}»',
                style: appearance.iconButton(context),
                onPressed: () => _close(tab),
                icon: const Icon(Icons.close_rounded, size: 15),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _tabBar() => SizedBox(
    height: _tabBarHeight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _tabButton(
            key: const Key('workspace-library'),
            label: 'Библиотека',
            icon: Icons.library_music_outlined,
            selected: _active == null,
            onTap: showLibrary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Scrollbar(
              controller: _tabScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _tabScroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tab in _tabs)
                      Row(
                        key: tab.key,
                        children: [
                          Tooltip(
                            message: tab.title,
                            child: _tabButton(
                              key: ValueKey('tab-${tab.kind.name}-${tab.id}'),
                              label: tab.title,
                              icon: tab.icon,
                              selected: _active == tab,
                              onTap: () => _activate(tab),
                            ),
                          ),
                          IconButton(
                            key: ValueKey('close-${tab.kind.name}-${tab.id}'),
                            tooltip: 'Закрыть вкладку «${tab.title}»',
                            onPressed: () => _close(tab),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final appearance = AuroraAppearance.of(context);
    final frame = appearance == null ? null : widget.frame;
    final panes = Stack(
      key: _panes,
      fit: StackFit.expand,
      children: [
        _pane(
          widget.child,
          _active == null,
          const ValueKey('catalog'),
          top: frame == null ? _catalogTop : 0,
        ),
        for (final tab in _tabs)
          _pane(
            tab.page,
            _active == tab,
            ObjectKey(tab),
            top: frame == null ? _tabBarHeight : 0,
          ),
        if (frame == null && _tabs.isNotEmpty)
          Positioned(top: 0, left: 0, right: 0, child: _tabBar()),
      ],
    );
    return frame == null
        ? panes
        : frame(
            _auroraTabs(appearance!),
            panes,
            _active == null,
            _active?.kind == _PageKind.album ? _active?.id : null,
          );
  }
}
