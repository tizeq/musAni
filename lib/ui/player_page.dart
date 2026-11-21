import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:path/path.dart' as p;

import '../files/local_tracks.dart';
import '../library/library_controller.dart';
import '../library/models.dart';
import '../metadata/playback_tags.dart';
import '../playlists/models.dart';
import '../playlists/playlist_repository.dart';
import '../playback/playback_engine.dart';
import 'library_page.dart';
import 'library_widgets.dart' show libraryTime;
import 'metadata_editor_dialog.dart';

import 'playlist_actions.dart';
import 'playlist_page.dart';
import '../settings/settings_controller.dart';
import '../settings/shortcuts.dart';
import 'playback_dock.dart';
import 'current_track_details.dart';
import 'motion.dart';
import 'settings_window.dart';
import 'atmosphere.dart';
import 'aurora_library_shell.dart';
import 'aurora_scene.dart';

typedef TrackPicker = Future<List<String>> Function();

Future<List<String>> pickTracks() async => [
  for (final file in await openFiles(
    acceptedTypeGroups: [
      const XTypeGroup(label: 'Аудио', extensions: LocalTracks.extensions),
    ],
  ))
    file.path,
];

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.engine,
    this.picker = pickTracks,
    this.library,
    this.folderPicker = pickMusicFolder,
    this.playlistLinkPicker = pickPlaylistLink,
    this.settings,
  });
  final PlaybackEngine engine;
  final TrackPicker picker;
  final LibraryController? library;
  final FolderPicker folderPicker;
  final PlaylistLinkPicker playlistLinkPicker;
  final SettingsController? settings;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late PlaybackState _state;
  final _accent = ArtworkAccent();
  late final _collection = ValueNotifier(
    widget.settings?.value.collectionPanel ??
        AppSettings.defaultCollectionPanel,
  );
  final _queueRevision = ValueNotifier(0);
  final _queueMetadata = <String, Future<LibraryTrack?>>{};
  final _windowBody = GlobalKey();
  late final StreamSubscription<PlaybackState> _subscription;
  bool _busy = false;
  bool _settingsOpen = false;
  bool _inlineCollection = false;
  double _lastAudibleVolume = 80;
  String? _error;
  late bool _showLibrary;
  Widget? _libraryPage;
  final _libraryKey = GlobalKey<LibraryPageState>();
  final _shortcutFocus = FocusNode(debugLabel: 'musAni shortcuts');
  late final _window = AuroraWindowControls(
    collection: _collection,
    toggleCollection: _toggleCollection,
    selectPanelMode: (mode) => _updatePanel(mode: mode),
    resizePanel: (width) => _updatePanel(width: width),
    revealContent: _revealContent,
    onOpenFiles: _open,
    onSettings: widget.settings == null ? null : _openSettings,
    queue: ListenableBuilder(
      listenable: _queueRevision,
      builder: (context, _) =>
          _queueList(context, AuroraAppearance.of(context)),
    ),
    currentTrack: ListenableBuilder(
      listenable: _queueRevision,
      builder: (context, _) {
        final queue = _state.queue;
        if (queue.isEmpty)
          return const Center(child: Text('Выберите трек для воспроизведения'));
        return LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CurrentTrackDetails(
              track: queue[_state.index.clamp(0, queue.length - 1)],
              library: widget.library,
              coverSize: (box.maxWidth - 32).clamp(48.0, 280.0),
              stacked: true,
            ),
          ),
        );
      },
    ),
  );

  @override
  void initState() {
    super.initState();
    _state = widget.engine.state;
    if (_state.volume > 0) _lastAudibleVolume = _state.volume;
    _showLibrary = widget.library != null;
    if (widget.library case final library?) {
      final settings = widget.settings?.value;
      if (settings != null &&
          settings.style == MusaniTheme.atmosphere &&
          !settings.showAlbumsInAtmosphere &&
          library.query.view == LibraryView.albums) {
        library.query = library.queryFor(LibraryView.tracks);
      }
      _libraryPage = RepaintBoundary(
        child: LibraryPage(
          key: _libraryKey,
          settings: widget.settings,
          window: _window,
          controller: library,
          onPlay: _playLibrary,
          onPlayQuery: _playLibraryQuery,
          onPlayPlaylist: _playPlaylist,
          playlistLinkPicker: widget.playlistLinkPicker,
          folderPicker: widget.folderPicker,
        ),
      );
      library.addListener(_catalogChanged);
      unawaited(library.load());
    }
    _subscription = widget.engine.changes.listen((state) {
      final previous = _state;
      _state = state;
      if (!identical(previous.queue, state.queue)) _queueMetadata.clear();
      if (!identical(previous.queue, state.queue) ||
          previous.index != state.index ||
          previous.playing != state.playing) {
        _queueRevision.value++;
      }
      if (previous.queue.isNotEmpty && state.queue.isEmpty)
        _accent.select(null);
      if (state.volume > 0) _lastAudibleVolume = state.volume;
      // Position ticks belong only to the progress strip. The cached library
      // widget already avoids builds; do not relayout/repaint its ancestors.
      if (mounted &&
          (!identical(previous.queue, state.queue) ||
              previous.index != state.index ||
              previous.playing != state.playing ||
              previous.duration != state.duration ||
              previous.volume != state.volume ||
              previous.repeatMode != state.repeatMode ||
              previous.shuffle != state.shuffle ||
              previous.error != state.error)) {
        setState(() {});
      }
    });
  }

  int _catalogRevision = -1;
  void _catalogChanged() {
    final revision = widget.library!.catalogRevision;
    if (_catalogRevision != revision && mounted) {
      _catalogRevision = revision;
      _queueMetadata.clear();
      _queueRevision.value++;
      setState(() {});
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() => _run(() async {
    final paths = await widget.picker();
    if (!mounted || paths.isEmpty) return;
    final tracks = await LocalTracks().resolve(paths);
    if (mounted) {
      final tagged = await readPlaybackTags(tracks);
      if (mounted) await widget.engine.open(tagged);
    }
    if (mounted) _showQueue();
  });

  Future<void> _openSettings() async {
    final settings = widget.settings;
    if (settings == null || _settingsOpen) return;
    _settingsOpen = true;
    try {
      await showAppDialog<void>(
        context: context,
        builder: (_) =>
            SettingsWindow(settings: settings, engine: widget.engine),
      );
    } finally {
      _settingsOpen = false;
    }
  }

  void _focusSearch() {
    if (_libraryPage != null && AuroraAppearance.of(context) != null) {
      _revealContent();
      _libraryKey.currentState?.focusSearch();
      return;
    }
    if (_showLibrary) {
      _libraryKey.currentState?.focusSearch();
      return;
    }
    setState(() => _showLibrary = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _libraryKey.currentState?.focusSearch();
    });
  }

  void _showQueue() {
    _shortcutFocus.requestFocus();
    if (_libraryPage != null && AuroraAppearance.of(context) != null) {
      _updatePanel(open: true, mode: CollectionPanelMode.queue);
      return;
    }
    setState(() => _showLibrary = false);
  }

  void _toggleCollection() {
    _shortcutFocus.requestFocus();
    _updatePanel(
      open: !panelIsOpen(_collection.value, wide: _inlineCollection),
    );
  }

  void _togglePanelQueue() {
    _shortcutFocus.requestFocus();
    final panel = _collection.value;
    final queueVisible =
        panel.mode == CollectionPanelMode.queue &&
        panelIsOpen(panel, wide: _inlineCollection);
    _updatePanel(open: !queueVisible, mode: CollectionPanelMode.queue);
  }

  void _revealContent() {
    if (!_inlineCollection && _collection.value.compactOpen)
      _updatePanel(open: false);
  }

  void _updatePanel({bool? open, double? width, CollectionPanelMode? mode}) {
    final previous = _collection.value;
    final preferences = (
      open: _inlineCollection ? open ?? previous.open : previous.open,
      width: width ?? previous.width,
      mode: mode ?? previous.mode,
      compactOpen: _inlineCollection
          ? previous.compactOpen
          : open ?? previous.compactOpen,
    );
    _collection.value = preferences;
    if (preferences != previous && widget.settings != null) {
      unawaited(_savePanel(preferences));
    }
  }

  Future<void> _savePanel(CollectionPanelSettings preferences) async {
    final stored = await widget.settings!.updateCollectionPanel(preferences);
    if (!stored && mounted && _collection.value == preferences) {
      showAppSnackBar(
        context,
        const SnackBar(
          content: Text('Не удалось сохранить настройки коллекции'),
        ),
      );
    }
  }

  Future<void> _toggleMute() => _run(
    () => widget.engine.setVolume(
      widget.engine.state.volume > 0 ? 0 : _lastAudibleVolume,
    ),
  );

  KeyEventResult _handleShortcut(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || event.synthesized || _settingsOpen)
      return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        (focused.findAncestorWidgetOfExactType<EditableText>() != null ||
            ModalRoute.of(focused) is PopupRoute)) {
      return KeyEventResult.ignored;
    }
    if (_collection.value.compactOpen &&
        !_inlineCollection &&
        _libraryPage != null &&
        AuroraAppearance.of(context) != null &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _revealContent();
      return KeyEventResult.handled;
    }
    final chord = KeyChord.fromEvent(event);
    final preferences = widget.settings?.value;
    final action =
        preferences?.actionFor(chord) ??
        (preferences == null
            ? PlayerShortcut.values
                  .where((action) => action.defaultChord == chord)
                  .firstOrNull
            : null);
    if (action == null ||
        action == PlayerShortcut.search && _libraryPage == null ||
        action == PlayerShortcut.settings && widget.settings == null)
      return KeyEventResult.ignored;
    if (event is KeyRepeatEvent && !action.repeats)
      return KeyEventResult.handled;

    switch (action) {
      case PlayerShortcut.playPause:
        if (_state.queue.isNotEmpty) unawaited(_run(widget.engine.toggle));
      case PlayerShortcut.previous || PlayerShortcut.next:
        final index = _state.indexAtOffset(
          action == PlayerShortcut.next ? 1 : -1,
        );
        if (index != null) unawaited(_run(() => widget.engine.jump(index)));
      case PlayerShortcut.volumeUp || PlayerShortcut.volumeDown:
        final step = preferences?.volumeStep ?? 5;
        final delta = action == PlayerShortcut.volumeUp ? step : -step;
        final volume = (widget.engine.state.volume + delta).clamp(0.0, 100.0);
        unawaited(_run(() => widget.engine.setVolume(volume)));
      case PlayerShortcut.mute:
        unawaited(_toggleMute());
      case PlayerShortcut.search:
        _focusSearch();
      case PlayerShortcut.settings:
        unawaited(_openSettings());
    }
    return KeyEventResult.handled;
  }

  Future<void> _playLibrary(List<LibraryTrack> tracks, int index) => _run(
    () => _openQueue([for (final track in tracks) track.playable], index),
  );

  Future<void> _playLibraryQuery(LibraryQuery query, {String? startPath}) =>
      _run(() async {
        final tracks = await widget.library!.repository.playbackTracks(query);
        final index = startPath == null
            ? 0
            : tracks.indexWhere((track) => track.uri.toFilePath() == startPath);
        if (index < 0 || tracks.isEmpty)
          throw StateError('Трек больше недоступен. Обновите библиотеку.');
        if (mounted) await _openQueue(tracks, index);
      });

  Future<void> _playPlaylist(List<LocalTrack> tracks, int index) =>
      _run(() => _openQueue(tracks, index));

  Future<void> _openQueue(List<LocalTrack> tracks, int index) async {
    await LocalTracks().validate([
      for (final track in tracks) track.uri.toFilePath(),
    ]);
    if (mounted) await widget.engine.open(tracks, index: index);
  }

  @override
  void dispose() {
    _shortcutFocus.dispose();
    _accent.dispose();
    _collection.dispose();
    _queueRevision.dispose();
    unawaited(_subscription.cancel());
    unawaited(widget.engine.dispose());
    widget.library?.removeListener(_catalogChanged);
    widget.library?.dispose();
    super.dispose();
  }

  Widget _queueList(BuildContext context, [AuroraAppearance? appearance]) {
    if (_state.queue.isEmpty) {
      return Center(
        child: FilledButton.icon(
          onPressed: _busy ? null : _open,
          icon: const Icon(Icons.library_music),
          label: const Text('Выбрать музыку'),
        ),
      );
    }
    return ListView.builder(
      key: appearance == null ? null : const Key('aurora-queue'),
      padding: appearance == null
          ? null
          : const EdgeInsets.fromLTRB(10, 4, 10, 10),
      itemCount: _state.queue.length,
      itemBuilder: (context, index) {
        final queued = _state.queue[index];
        final track = widget.library?.labelsFor(queued) ?? queued;
        final selected = index == _state.index;
        final playing = selected ? _state.playing : null;
        Widget tile({TrackMetadata? metadata}) => ListTile(
          selected: selected,
          selectedTileColor: currentTrackTint(appearance, playing),
          shape: appearance == null
              ? null
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textColor: appearance?.ink,
          selectedColor: appearance?.accent,
          iconColor: appearance?.muted,
          contentPadding: appearance == null
              ? null
              : const EdgeInsets.symmetric(horizontal: 10),
          leading: appearance == null
              ? Icon(selected ? Icons.music_note : Icons.audiotrack)
              : AuroraArtwork(
                  appearance: appearance,
                  size: 39,
                  radius: 8,
                  path: metadata?.coverKey == null
                      ? null
                      : widget.library!.repository.coverPath(
                          metadata!.coverKey!,
                        ),
                ),
          title: trackTitle(
            Text(
              track.name,
              maxLines: appearance == null ? null : 1,
              overflow: appearance == null ? null : TextOverflow.ellipsis,
            ),
            indicatorKey: ValueKey('queue-current-track-$index'),
            playing: playing,
            appearance: appearance,
          ),
          trailing: widget.library == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (appearance != null && metadata != null)
                      Text(
                        libraryTime(metadata.durationMs),
                        style: TextStyle(color: appearance.muted, fontSize: 11),
                      ),
                    PopupMenuButton<String>(
                      popUpAnimationStyle: reducedAnimationStyle(context),
                      tooltip: 'Действия трека очереди',
                      style: appearance?.iconButton(context),
                      onSelected: (action) {
                        final path = track.uri.toFilePath();
                        if (action == 'edit') {
                          editTrackMetadataPath(context, path, widget.library!);
                          return;
                        }
                        addToPlaylist(
                          context,
                          PlaylistRepository(
                            widget.library!.repository.directory,
                          ),
                          [
                            PlaylistTrackRef(
                              path: path,
                              title: track.name,
                              artists: track.artists,
                              durationMs: selected
                                  ? _state.duration.inMilliseconds
                                  : 0,
                            ),
                          ],
                        );
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          enabled:
                              !widget.library!.mutating &&
                              ['.mp3', '.flac'].contains(
                                p
                                    .extension(track.uri.toFilePath())
                                    .toLowerCase(),
                              ),
                          child: const Text('Редактировать метаданные'),
                        ),
                        const PopupMenuItem(
                          value: 'playlist',
                          child: Text('Добавить в плейлист'),
                        ),
                      ],
                    ),
                  ],
                ),
          subtitle: Text(
            track.artists.isEmpty
                ? 'Неизвестный исполнитель'
                : track.artists.join(' / '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appearance == null
                ? null
                : TextStyle(color: appearance.muted, fontSize: 12),
          ),
          onTap: _busy ? null : () => _run(() => widget.engine.jump(index)),
        );
        if (appearance == null) return tile();
        final path = track.uri.toFilePath();
        final found = _queueMetadata.putIfAbsent(
          path,
          () => widget.library!.repository.trackByPath(path),
        );
        if (_queueMetadata.length > 48)
          _queueMetadata.remove(_queueMetadata.keys.first);
        final child = FutureBuilder<LibraryTrack?>(
          key: ValueKey(path),
          future: found,
          builder: (context, snapshot) =>
              tile(metadata: snapshot.data?.metadata),
        );
        return Padding(padding: const EdgeInsets.only(bottom: 4), child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _inlineCollection =
          constraints.maxWidth >= AuroraLibraryShell.panelBreakpoint;
      return _buildWindow(context);
    },
  );

  Widget _buildWindow(BuildContext context) {
    final appearance = AuroraAppearance.of(context);
    final unified = appearance != null && _libraryPage != null;
    final showLibrary = unified || _showLibrary;
    final error = _error ?? _state.error;

    Widget dock({required bool visible, required bool inline}) => PlaybackDock(
      engine: widget.engine,
      state: _state,
      busy: _busy,
      run: _run,
      library: widget.library,
      onToggleMute: _toggleMute,
      onShowQueue: _libraryPage == null
          ? null
          : unified
          ? _togglePanelQueue
          : () {
              if (_showLibrary) {
                _showQueue();
              } else {
                setState(() => _showLibrary = true);
              }
            },
      queueVisible: visible,
      queueInCollection: inline,
    );

    final content = Column(
      key: _windowBody,
      children: [
        if (_busy) const BusyIndicator.bar(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Ошибка: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          key: const Key('player-content'),
          child: IndexedStack(
            index: _libraryPage == null || showLibrary ? 0 : 1,
            children: [
              if (_libraryPage != null)
                ExcludeFocus(
                  excluding: !showLibrary,
                  child: TickerMode(enabled: showLibrary, child: _libraryPage!),
                ),
              if (!unified) _queueList(context),
            ],
          ),
        ),
        if (unified)
          ValueListenableBuilder(
            valueListenable: _collection,
            builder: (context, panel, _) => dock(
              visible:
                  panel.mode == CollectionPanelMode.queue &&
                  panelIsOpen(panel, wide: _inlineCollection),
              inline: _inlineCollection,
            ),
          )
        else
          dock(visible: !_showLibrary, inline: false),
      ],
    );

    return CurrentTrackScope(
      path: _state.currentTrack?.uri.toFilePath(),
      playlistEntry: _state.currentTrack?.playlistEntry,
      playing: _state.playing,
      child: AccentScope(
        accent: _accent,
        child: Focus(
          focusNode: _shortcutFocus,
          autofocus: true,
          skipTraversal: true,
          onKeyEvent: _handleShortcut,
          child: Scaffold(
            appBar: unified ? null : _classicAppBar(context),
            body: unified
                ? AuroraBackdrop(
                    key: const Key('aurora-window'),
                    appearance: appearance,
                    child: Material(
                      type: MaterialType.transparency,
                      child: content,
                    ),
                  )
                : content,
          ),
        ),
      ),
    );
  }

  AppBar _classicAppBar(BuildContext context) {
    final glass = GlassColors.of(context);
    return AppBar(
      backgroundColor: glass?.base,
      foregroundColor: glass?.ink,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.graphic_eq,
            color: glass?.accent ?? Theme.of(context).colorScheme.primary,
            size: 22,
          ),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              'musAni',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -.7,
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.settings != null)
          IconButton(
            tooltip: 'Настройки',
            style: _showLibrary ? glass?.iconStyle() : null,
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        if (_libraryPage != null) ...[
          IconButton(
            tooltip: 'Библиотека',
            style: _showLibrary ? glass?.iconStyle(active: true) : null,
            isSelected: _showLibrary,
            onPressed: () => setState(() => _showLibrary = true),
            icon: const Icon(Icons.library_music_outlined),
          ),
          IconButton(
            tooltip: 'Очередь воспроизведения',
            style: _showLibrary ? glass?.iconStyle() : null,
            isSelected: !_showLibrary,
            onPressed: _showQueue,
            icon: const Icon(Icons.queue_music),
          ),
        ],
        IconButton(
          tooltip: 'Открыть файлы',
          style: _showLibrary ? glass?.iconStyle() : null,
          onPressed: _busy ? null : _open,
          icon: const Icon(Icons.file_open),
        ),
      ],
    );
  }
}
