import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../library/library_controller.dart';
import '../library/models.dart';
import '../playlists/models.dart';
import '../playlists/playlist_repository.dart';
import '../settings/settings_controller.dart';
import 'album_artwork.dart';
import 'aurora_library_shell.dart';
import 'aurora_scene.dart';
import 'library_widgets.dart';
import 'library_workspace.dart';
import 'metadata_editor_dialog.dart';
import 'playlist_actions.dart';
import 'playlist_page.dart';
import 'playlists_view.dart';
import 'design_system.dart';
import 'library_navigation.dart';
import 'motion.dart';
import 'atmosphere.dart';

typedef FolderPicker = Future<String?> Function();

Future<String?> pickMusicFolder() =>
    getDirectoryPath(confirmButtonText: 'Добавить в библиотеку');

/// The nested navigator keeps the playback dock alive on playlist routes.
class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.controller,
    required this.onPlay,
    required this.onPlayQuery,
    this.folderPicker = pickMusicFolder,
    this.playlists,
    this.onPlayPlaylist,
    this.playlistLinkPicker = pickPlaylistLink,
    this.settings,
    this.window,
  });
  final LibraryController controller;
  final LibraryPlayback onPlay;
  final LibraryQueryPlayback onPlayQuery;
  final PlaylistRepository? playlists;
  final PlaylistPlayback? onPlayPlaylist;
  final PlaylistLinkPicker playlistLinkPicker;
  final FolderPicker folderPicker;
  final SettingsController? settings;
  final AuroraWindowControls? window;

  @override
  State<LibraryPage> createState() => LibraryPageState();
}

class LibraryPageState extends State<LibraryPage> {
  final _navigator = GlobalKey<NavigatorState>();
  final _browser = GlobalKey<_LibraryBrowserState>();

  void focusSearch() {
    _navigator.currentState?.popUntil((route) => route.isFirst);
    _browser.currentState?.focusSearch();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: _navigator,
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (_) => _LibraryBrowser(
        key: _browser,
        controller: widget.controller,
        onPlay: widget.onPlay,
        onPlayQuery: widget.onPlayQuery,
        folderPicker: widget.folderPicker,
        playlists:
            widget.playlists ??
            PlaylistRepository(widget.controller.repository.directory),
        onPlayPlaylist: widget.onPlayPlaylist,
        linkPicker: widget.playlistLinkPicker,
        settings: widget.settings,
        window: widget.window,
      ),
    ),
  );
}

class _LibraryBrowser extends StatefulWidget {
  const _LibraryBrowser({
    super.key,
    required this.controller,
    required this.onPlay,
    required this.onPlayQuery,
    required this.folderPicker,
    required this.playlists,
    this.onPlayPlaylist,
    required this.linkPicker,
    this.settings,
    this.window,
  });
  final LibraryController controller;
  final LibraryPlayback onPlay;
  final LibraryQueryPlayback onPlayQuery;
  final PlaylistRepository playlists;
  final PlaylistPlayback? onPlayPlaylist;
  final PlaylistLinkPicker linkPicker;
  final FolderPicker folderPicker;
  final SettingsController? settings;
  final AuroraWindowControls? window;
  @override
  State<_LibraryBrowser> createState() => _LibraryBrowserState();
}

class _LibraryBrowserState extends State<_LibraryBrowser>
    with SingleTickerProviderStateMixin {
  final _searches = <LibraryView, TextEditingController>{};
  final _searchFocus = FocusNode();
  final _workspace = GlobalKey<LibraryWorkspaceState>();
  final _catalogRoutes = GlobalKey<NavigatorState>();
  late final _tabMotion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    value: 1,
  );
  Timer? _debounce;
  bool _showPlaylists = false;
  bool _visitedPlaylists = false;
  final _selected = <int, LibraryTrack>{};
  List<LibrarySection> _localOrder = LibrarySection.values;
  LibraryController get library => widget.controller;
  int get _section => _showPlaylists ? 3 : library.query.view.index;
  List<LibrarySection> get _order =>
      widget.settings?.value.libraryOrder ?? _localOrder;

  TextEditingController _searchFor(LibraryView view) => _searches.putIfAbsent(
    view,
    () => TextEditingController(text: library.queryFor(view).search),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _tabMotion.value = 1;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabMotion.dispose();
    _searchFocus.dispose();
    for (final search in _searches.values) {
      search.dispose();
    }
    super.dispose();
  }

  void _query({
    LibraryView? view,
    LibrarySort? sort,
    bool? descending,
    bool restoreSection = false,
  }) {
    _debounce?.cancel();
    if (_selected.isNotEmpty) setState(() => _selected.clear());
    final target = library.queryFor(view ?? library.query.view);
    unawaited(
      library.search(
        LibraryQuery(
          view: target.view,
          search: _searchFor(target.view).text,
          sort: sort ?? target.sort,
          descending: descending ?? target.descending,
        ),
        restoreSection: restoreSection,
      ),
    );
  }

  void _selectSection(int index) {
    _catalogRoutes.currentState?.popUntil((route) => route.isFirst);
    _workspace.currentState?.showLibrary();
    if (index == _section) return;
    _debounce?.cancel();
    _searchFocus.unfocus();
    setState(() {
      _showPlaylists = index == 3;
      _visitedPlaylists |= _showPlaylists;
      _selected.clear();
    });
    if (index < 3)
      _query(view: LibraryView.values[index], restoreSection: true);
    if (!MediaQuery.disableAnimationsOf(context)) _tabMotion.forward(from: 0);
  }

  void focusSearch() {
    _catalogRoutes.currentState?.popUntil((route) => route.isFirst);
    _workspace.currentState?.showLibrary();
    if (_showPlaylists) _selectSection(library.query.view.index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _reorder(
    List<LibrarySection> visible,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) return;
    final reordered = visible.toList();
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    final visibleSections = visible.toSet();
    var index = 0;
    final next = [
      for (final section in _order)
        visibleSections.contains(section) ? reordered[index++] : section,
    ];
    final settings = widget.settings;
    if (settings == null) {
      setState(() => _localOrder = next);
    } else if (!await settings.update(
          settings.value.copyWith(libraryOrder: next),
        ) &&
        mounted) {
      showAppSnackBar(
        context,
        SnackBar(
          content: Text(settings.error ?? 'Дождитесь сохранения настроек.'),
        ),
      );
    }
  }

  Widget _navigation({required bool horizontal, AuroraAppearance? aurora}) {
    Widget build() {
      final showAlbums =
          aurora == null ||
          widget.settings?.value.showAlbumsInAtmosphere == true;
      final visible = showAlbums
          ? _order
          : _order
                .where((section) => section != LibrarySection.albums)
                .toList();
      return LibraryNavigation(
        horizontal: horizontal,
        selected: _section,
        onSelected: _selectSection,
        order: visible,
        onReorder: (from, to) => _reorder(visible, from, to),
        aurora: aurora,
      );
    }

    final settings = widget.settings;
    return settings == null
        ? build()
        : ListenableBuilder(listenable: settings, builder: (_, _) => build());
  }

  Widget _auroraStatus(AuroraAppearance appearance) {
    final report = library.lastReport;
    final error = library.error;
    if (!library.scanning && error == null && report == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        children: [
          if (library.scanning) const BusyIndicator.bar(minHeight: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  error ??
                      (library.scanning
                          ? 'Сканирование · ${library.progress?.visited ?? 0} файлов · ${p.basename(library.progress?.path ?? '')}'
                          : 'Обновлено ${report!.updated} · без изменений ${report.unchanged} · удалено ${report.removed}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: appearance.muted, fontSize: 12),
                ),
              ),
              if (error != null)
                TextButton(
                  onPressed: library.load,
                  child: const Text('Повторить'),
                ),
              if (!library.scanning && report?.warnings.isNotEmpty == true)
                IconButton(
                  tooltip: 'Предупреждения сканирования',
                  onPressed: _warnings,
                  icon: const Icon(Icons.warning_amber_rounded),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _auroraWorkspace(AuroraAppearance appearance, LibraryQuery query) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    return LibraryWorkspace(
      key: _workspace,
      library: library,
      playlists: widget.playlists,
      onPlay: widget.onPlay,
      onPlayQuery: widget.onPlayQuery,
      onReveal: widget.window?.revealContent,
      frame: (tabs, content, catalogActive, activeAlbumId) => LayoutBuilder(
        builder: (context, constraints) => AuroraLibraryShell(
          appearance: appearance,
          controls: widget.window,
          library: library,
          tabs: tabs,
          navigation: _navigation(
            horizontal:
                constraints.maxWidth < AuroraLibraryShell.sidebarBreakpoint,
            aurora: appearance,
          ),
          content: content,
          onSearch: focusSearch,
          onSources: _sources,
          onRefresh: library.mutating ? null : () => library.refresh(),
          onAddFolder: library.mutating ? null : _addFolder,
          onOpenAlbum: (album) => _workspace.currentState?.openAlbum(album),
          onViewAlbums: () => _selectSection(LibraryView.albums.index),
          albumsVisible:
              catalogActive &&
              !_showPlaylists &&
              query.view == LibraryView.albums,
          activeAlbumId: activeAlbumId,
        ),
      ),
      child: Navigator(
        key: _catalogRoutes,
        onDidRemovePage: (_) {},
        pages: [
          MaterialPage<void>(
            child: Column(
              children: [
                _auroraStatus(appearance),
                Expanded(
                  child: _sectionBody(
                    compact,
                    query,
                    GlassColors.of(context),
                    aurora: appearance,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addFolder() async {
    try {
      final path = await widget.folderPicker();
      if (mounted && path != null) await library.refresh(addRoot: path);
    } catch (error) {
      if (mounted) showAppSnackBar(context, SnackBar(content: Text('$error')));
    }
  }

  Future<void> _playAlbum(String id) async {
    try {
      final tracks = await library.repository.albumTracks(id);
      if (tracks.isEmpty)
        throw StateError(
          'Треки альбома больше недоступны. Обновите библиотеку.',
        );
      if (mounted) await widget.onPlay(tracks, 0);
    } catch (error) {
      if (mounted) showAppSnackBar(context, SnackBar(content: Text('$error')));
    }
  }

  void _warnings() {
    unawaited(
      showAppDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Предупреждения сканирования'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: SelectableText(library.lastReport!.warnings.join('\n\n')),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }

  void _sources() {
    unawaited(
      showAppDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Папки с музыкой'),
          content: SizedBox(
            width: 620,
            height: 300,
            child: AnimatedBuilder(
              animation: library,
              builder: (context, _) => library.status.roots.isEmpty
                  ? const Center(child: Text('Папки ещё не добавлены'))
                  : ListView(
                      children: [
                        for (final root in library.status.roots)
                          ListTile(
                            leading: Icon(
                              root.error == null
                                  ? Icons.folder_outlined
                                  : Icons.folder_off_outlined,
                            ),
                            title: Text(root.path),
                            subtitle: root.error == null
                                ? null
                                : Text(
                                    root.error!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                            trailing: IconButton(
                              tooltip: 'Убрать из библиотеки, сохранив файлы',
                              onPressed: library.mutating
                                  ? null
                                  : () => library.removeRoot(root.id),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: library,
    builder: (context, _) {
      final theme = Theme.of(context);
      final query = library.query;
      final aurora = AuroraAppearance.of(context);
      if (aurora != null) return _auroraWorkspace(aurora, query);
      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final glass = GlassColors.of(context);
          final compact = constraints.maxWidth < 560;
          return LibraryBackdrop(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 28,
                    12,
                    compact ? 12 : 24,
                    12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (glass != null && wide) ...[
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: glass.paneTint.withValues(alpha: .64),
                                border: Border.all(color: glass.controlEdge),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.library_music_outlined,
                                color: glass.accent,
                                size: 23,
                              ),
                            ),
                            const SizedBox(width: 14),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ваша музыка',
                                  style: glass == null
                                      ? theme.textTheme.headlineSmall
                                      : theme.textTheme.headlineSmall?.copyWith(
                                          fontSize: compact ? 24 : 32,
                                          height: 1.15,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -.7,
                                          color: glass.ink,
                                        ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${library.status.albumCount} альбомов · ${library.status.trackCount} треков',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        glass?.muted ??
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Папки библиотеки',
                            style: glass?.iconStyle(),
                            onPressed: _sources,
                            icon: Icon(
                              library.status.roots.any(
                                    (root) => root.error != null,
                                  )
                                  ? Icons.folder_off_outlined
                                  : Icons.folder_outlined,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Обновить библиотеку',
                            style: glass?.iconStyle(),
                            onPressed: library.mutating
                                ? null
                                : () => library.refresh(),
                            icon: const Icon(Icons.refresh),
                          ),
                          if (compact)
                            IconButton(
                              tooltip: 'Добавить папку',
                              style: glass?.iconStyle(active: true),
                              onPressed: library.mutating ? null : _addFolder,
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                              ),
                            )
                          else if (glass == null)
                            FilledButton.icon(
                              onPressed: library.mutating ? null : _addFolder,
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                              ),
                              label: const Text('Добавить папку'),
                            )
                          else
                            OutlinedButton.icon(
                              style:
                                  OutlinedButton.styleFrom(
                                    foregroundColor: glass.ink,
                                    backgroundColor: glass.paneTint.withValues(
                                      alpha: .72,
                                    ),
                                    side: BorderSide(color: glass.controlEdge),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 13,
                                      vertical: 10,
                                    ),
                                  ).copyWith(
                                    overlayColor:
                                        WidgetStateProperty.resolveWith(
                                          glass.controlOverlay,
                                        ),
                                  ),
                              onPressed: library.mutating ? null : _addFolder,
                              icon: Icon(
                                Icons.create_new_folder_outlined,
                                color: library.mutating ? null : glass.accent,
                                size: 18,
                              ),
                              label: const Text('Добавить папку'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (library.scanning) ...[
                  const BusyIndicator.bar(minHeight: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 6,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Сканирование · ${library.progress?.visited ?? 0} файлов · ${p.basename(library.progress?.path ?? '')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ] else if (library.lastReport case final report?)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Обновлено ${report.updated} · без изменений ${report.unchanged} · удалено ${report.removed}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (report.warnings.isNotEmpty)
                          IconButton(
                            tooltip: 'Предупреждения сканирования',
                            onPressed: _warnings,
                            icon: const Icon(Icons.warning_amber_rounded),
                          ),
                      ],
                    ),
                  ),
                if (library.error case final error?)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            error,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                        TextButton(
                          onPressed: library.load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                if (!wide) _navigation(horizontal: true),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide) _navigation(horizontal: false),
                      Expanded(
                        child: LibraryWorkspace(
                          key: _workspace,
                          library: library,
                          playlists: widget.playlists,
                          onPlay: widget.onPlay,
                          onPlayQuery: widget.onPlayQuery,
                          child: _sectionBody(compact, query, glass),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _searchField(
    LibraryQuery query,
    bool compact,
    GlassColors? glass, {
    AuroraAppearance? aurora,
  }) {
    final field = TextField(
      controller: _searchFor(query.view),
      focusNode: _searchFocus,
      key: const Key('library-search'),
      decoration: InputDecoration(
        hintText: compact ? 'Поиск музыки' : 'Альбом, исполнитель или трек',
        hintStyle: glass == null
            ? null
            : TextStyle(color: aurora?.muted ?? glass.muted),
        prefixIcon: const Icon(Icons.search),
        prefixIconColor: aurora?.muted ?? glass?.muted,
        filled: glass == null,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(glass == null ? 14 : 12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: glass == null
            ? null
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: (aurora?.accent ?? glass.accent).withValues(
                    alpha: .76,
                  ),
                ),
              ),
      ),
      onChanged: (_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), () => _query());
      },
    );
    if (aurora != null) {
      return ListenableBuilder(
        listenable: _searchFocus,
        child: field,
        builder: (context, child) => AuroraSurface(
          appearance: aurora,
          radius: 12,
          opacity: _searchFocus.hasFocus ? .62 : .36,
          highlight: _searchFocus.hasFocus ? .60 : .13,
          child: child!,
        ),
      );
    }
    return glass == null
        ? field
        : GlassSurface(glass: glass, radius: 12, frosted: true, child: field);
  }

  Widget _sectionBody(
    bool compact,
    LibraryQuery query,
    GlassColors? glass, {
    AuroraAppearance? aurora,
  }) => ClipRect(
    child: AnimatedBuilder(
      animation: _tabMotion,
      child: RepaintBoundary(
        child: IndexedStack(
          index: _showPlaylists ? 1 : 0,
          sizing: StackFit.expand,
          children: [
            ExcludeFocus(
              excluding: _showPlaylists,
              child: TickerMode(
                enabled: !_showPlaylists,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 12 : 20,
                        0,
                        compact ? 12 : 24,
                        8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _searchField(
                                  query,
                                  compact,
                                  glass,
                                  aurora: aurora,
                                ),
                              ),
                              const SizedBox(width: 8),
                              LibrarySortControls(
                                glass: glass,
                                aurora: aurora,
                                query: query,
                                onSort: (sort) => _query(sort: sort),
                                onReverse: () =>
                                    _query(descending: !query.descending),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_selected.isNotEmpty)
                      TrackSelectionBar(
                        glass: glass,
                        selected: _selected.values.toList(),
                        repository: widget.playlists,
                        onClear: () {
                          if (mounted) setState(() => _selected.clear());
                        },
                      ),
                    Expanded(child: _results(compact, glass, aurora: aurora)),
                  ],
                ),
              ),
            ),
            if (_visitedPlaylists)
              ExcludeFocus(
                excluding: !_showPlaylists,
                child: TickerMode(
                  enabled: _showPlaylists,
                  child: PlaylistsView(
                    repository: widget.playlists,
                    library: library,
                    onPlay: widget.onPlayPlaylist,
                    linkPicker: widget.linkPicker,
                    active: _showPlaylists,
                  ),
                ),
              ),
          ],
        ),
      ),
      builder: (context, child) {
        final remaining = 1 - Curves.easeOutCubic.transform(_tabMotion.value);
        return Transform.translate(
          key: const Key('library-tab-content'),
          offset: Offset(0, 4 * remaining),
          child: child,
        );
      },
    ),
  );

  Widget _results(
    bool compact,
    GlassColors? glass, {
    AuroraAppearance? aurora,
  }) {
    if (!library.initialized || library.loading && library.result.length == 0) {
      return const LibraryLoadingIndicator();
    }
    if (library.result.length == 0)
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  library.status.trackCount == 0
                      ? Icons.library_music_outlined
                      : Icons.search_off,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  library.scanning
                      ? 'Сканируем вашу музыку…'
                      : library.status.trackCount == 0
                      ? 'Музыка начинается с вашей папки'
                      : 'Ничего не найдено',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  library.status.trackCount == 0
                      ? 'MP3, FLAC, M4A, OGG и другие локальные аудиофайлы'
                      : 'Попробуйте другой запрос.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (library.status.trackCount == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: FilledButton.icon(
                      onPressed: library.mutating ? null : _addFolder,
                      icon: const Icon(Icons.add),
                      label: const Text('Выбрать папку с музыкой'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

    final result = library.result;
    final query = library.query;
    final pageKey = PageStorageKey(query.criteria);
    Widget content;
    switch (query.view) {
      case LibraryView.albums:
        content = LayoutBuilder(
          builder: (context, constraints) {
            final padding = EdgeInsets.fromLTRB(
              compact ? 12 : 20,
              8,
              compact ? 12 : 24,
              20,
            );
            const gap = 16.0;
            final width = constraints.maxWidth - padding.horizontal;
            final maxTileWidth = compact ? 180 : 228;
            final columns = math.max(1, (width / (maxTileWidth + gap)).ceil());
            final tileWidth = (width - gap * (columns - 1)) / columns;
            return GridView.builder(
              key: pageKey,
              padding: padding,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap,
                childAspectRatio: .72,
              ),
              itemCount: result.albums.length,
              itemBuilder: (context, index) {
                final album = result.albums[index];
                return LibraryAlbumCard(
                  album: album,
                  coverSize: tileWidth,
                  coverPath: album.coverKey == null
                      ? null
                      : library.repository.coverPath(album.coverKey!),
                  onOpen: () => _workspace.currentState?.openAlbum(album),
                  onPlay: () => _playAlbum(album.id),
                  aurora: aurora,
                );
              },
            );
          },
        );
      case LibraryView.artists:
        content = ListView.builder(
          key: pageKey,
          padding: const EdgeInsets.all(16),
          itemCount: result.artists.length,
          itemBuilder: (context, index) {
            final artist = result.artists[index];
            final path = artist.coverKey == null
                ? null
                : library.repository.coverPath(artist.coverKey!);
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              leading: aurora != null
                  ? AuroraArtwork(
                      appearance: aurora,
                      size: 52,
                      radius: 11,
                      path: path,
                    )
                  : SizedBox.square(
                      dimension: 52,
                      child: AlbumArtwork(
                        displaySize: 52,
                        radius: 26,
                        path: path,
                      ),
                    ),
              title: Text(artist.name),
              textColor: aurora?.ink,
              subtitle: Text(
                aurora == null
                    ? '${artist.albumCount} альбомов · ${artist.trackCount} треков'
                    : '${libraryAlbumCount(artist.albumCount)} · ${libraryTrackCount(artist.trackCount)}',
                style: aurora == null ? null : TextStyle(color: aurora.muted),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _workspace.currentState?.openArtist(artist),
            );
          },
        );
      case LibraryView.tracks:
        content = ListView.builder(
          key: pageKey,
          padding: const EdgeInsets.all(12),
          itemCount: result.tracks.length,
          itemBuilder: (context, index) {
            final track = result.tracks[index];
            final tile = LibraryTrackTile(
              glass: glass,
              aurora: aurora,
              track: track,
              coverPath: track.metadata.coverKey == null
                  ? null
                  : library.repository.coverPath(track.metadata.coverKey!),
              onTap: () => widget.onPlayQuery(query, startPath: track.path),
              onEdit: () => editTrackMetadata(this.context, track, library),
              onAddToPlaylist: () => addToPlaylist(
                this.context,
                widget.playlists,
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
            if (aurora != null) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: aurora.plate.withValues(
                    alpha: aurora.dark ? .26 : .45,
                  ),
                  borderRadius: BorderRadius.circular(11),
                  child: tile,
                ),
              );
            }
            return glass == null || index == result.tracks.length - 1
                ? tile
                : DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: glass.divider, width: .5),
                      ),
                    ),
                    child: tile,
                  );
          },
        );
        if (glass != null && aurora == null) {
          content = Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 20,
              4,
              compact ? 12 : 24,
              10,
            ),
            child: GlassSurface(
              glass: glass,
              radius: 16,
              child: Material(type: MaterialType.transparency, child: content),
            ),
          );
        }
    }
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 600)
              unawaited(library.loadMore());
            return false;
          },
          child: content,
        ),
        if (library.loading)
          const Align(
            alignment: Alignment.bottomCenter,
            child: BusyIndicator.bar(minHeight: 2),
          ),
      ],
    );
  }
}
