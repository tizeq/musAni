import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../files/local_tracks.dart';
import '../library/library_controller.dart';
import '../playlists/models.dart';
import '../playlists/playlist_repository.dart';
import 'library_widgets.dart';
import 'playlist_actions.dart';
import 'metadata_editor_dialog.dart';
import 'motion.dart';
import 'aurora_scene.dart';
import 'playlist_cover.dart';
import 'album_artwork.dart';
import 'current_track_details.dart';

typedef PlaylistPlayback = Future<void> Function(
  List<LocalTrack> tracks,
  int index,
);
typedef PlaylistLinkPicker = Future<String?> Function();
Future<String?> pickPlaylistLink() async => (await openFile(
  acceptedTypeGroups: const [
    XTypeGroup(label: 'Аудиофайл', extensions: LocalTracks.extensions),
  ],
))?.path;

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({
    super.key,
    required this.id,
    required this.repository,
    this.onPlay,
    this.library,
    this.linkPicker = pickPlaylistLink,
    this.coverPicker = pickPlaylistCover,
    this.onBack,
    this.onAlbumChanged,
  });
  final String id;
  final PlaylistRepository repository;
  final PlaylistPlayback? onPlay;
  final LibraryController? library;
  final PlaylistLinkPicker linkPicker;
  final PlaylistCoverPicker coverPicker;
  final VoidCallback? onBack;
  final ValueChanged<UserPlaylist>? onAlbumChanged;
  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  PlaylistDetail? _detail;
  Set<String> _firstEntries = const {};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _request = 0;
  int _catalogRevision = -1;
  @override
  void initState() {
    super.initState();
    widget.library?.addListener(_catalogChanged);
    _load();
  }

  void _catalogChanged() {
    if (!_busy && _catalogRevision != widget.library?.catalogRevision) _load();
  }

  @override
  void dispose() {
    widget.library?.removeListener(_catalogChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    _catalogRevision = widget.library?.catalogRevision ?? -1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.detail(widget.id);
      if (mounted && request == _request) {
        final previous = _detail?.playlist;
        final paths = <String>{};
        setState(() {
          _detail = detail;
          _firstEntries = {
            for (final entry in detail.entries)
              if (paths.add(entry.track.path)) entry.id,
          };
        });
        if (previous != null &&
            (previous.name != detail.playlist.name ||
                previous.isAlbum != detail.playlist.isAlbum)) {
          widget.onAlbumChanged?.call(detail.playlist);
        }
      }
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = '$error');
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function(UserPlaylist playlist) action) async {
    if (_busy || _loading || _detail == null) return;
    final playlist = _detail!.playlist;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(playlist);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        await _load();
        if (mounted) setState(() => _error = '$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    final name = await playlistNameDialog(
      context,
      initial: _detail!.playlist.name,
    );
    if (name != null && mounted)
      await _run(
        (playlist) =>
            widget.repository.rename(playlist.id, playlist.revision, name),
      );
  }

  Future<void> _properties() async {
    final playlist = _detail!.playlist;
    final properties = await playlistPropertiesDialog(context, playlist);
    if (properties != null && mounted)
      await _run(
        (_) => savePlaylistProperties(widget.repository, playlist, properties),
      );
  }

  Future<void> _chooseCover() async {
    try {
      final file = await widget.coverPicker();
      if (file == null || !mounted) return;
      await _run((playlist) async {
        final image = await preparePlaylistCover(file);
        await widget.repository.setArtwork(
          playlist.id,
          playlist.revision,
          image,
        );
      });
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Не удалось открыть изображение. $error');
    }
  }

  Future<void> _resetCover() => _run(
    (playlist) =>
        widget.repository.setArtwork(playlist.id, playlist.revision, null),
  );

  Future<void> _delete() async {
    final playlist = _detail!.playlist;
    if (!await confirmPlaylistDelete(context, playlist.name) || !mounted)
      return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.delete(playlist.id, playlist.revision);
      if (mounted) (widget.onBack ?? () => Navigator.pop(context))();
    } catch (error) {
      if (mounted) {
        await _load();
        if (mounted) setState(() => _error = '$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _overview(
    PlaylistDetail detail,
    bool enabled,
    AuroraAppearance? aurora,
  ) {
    final album = detail.playlist.isAlbum;
    final metadata = detail.playlist.albumMetadata;
    final credits = [
      if (metadata.artist.isNotEmpty) metadata.artist,
      if (metadata.year != 0) '${metadata.year}',
      if (metadata.genre.isNotEmpty) metadata.genre,
    ].join(' · ');
    final summary = Text(
      credits,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: aurora == null ? null : TextStyle(color: aurora.muted),
    );
    final duration = Text(
      '${aurora == null ? '${detail.entries.length} треков' : libraryTrackCount(detail.entries.length)} · ${libraryTime(detail.playlist.durationMs)}',
      key: const Key('playlist-duration'),
      style: aurora == null ? null : TextStyle(color: aurora.muted),
    );
    final play = FilledButton.icon(
      style: aurora?.accentButton(),
      onPressed:
          enabled &&
              detail.entries.any((entry) => entry.albumConflict == null) &&
              detail.unavailableCount == 0 &&
              widget.onPlay != null
          ? _play
          : null,
      icon: const Icon(Icons.play_arrow),
      label: Text(
        album ? 'Воспроизвести альбом' : 'Воспроизвести плейлист',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (aurora == null)
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 20,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (album)
              SizedBox.square(
                dimension: 72,
                child: AlbumArtwork(
                  displaySize: 72,
                  path: switch (detail.playlist.albumCoverKey ??
                      detail.entries
                          .map((entry) => entry.track.coverKey)
                          .nonNulls
                          .firstOrNull) {
                    final key? => widget.repository.trackCoverPath(key),
                    null => null,
                  },
                ),
              ),
            if (album && credits.isNotEmpty) summary,
            duration,
            play,
          ],
        ),
      );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: LayoutBuilder(
        builder: (context, box) {
          final coverSize = box.maxWidth >= 500 ? 118.0 : 80.0;
          return Row(
            children: [
              Stack(
                children: [
                  PlaylistCover(
                    repository: widget.repository,
                    playlist: detail.playlist,
                    appearance: aurora,
                    size: coverSize,
                    catalogRevision: widget.library?.catalogRevision,
                  ),
                  Positioned(
                    bottom: 3,
                    right: 3,
                    child: IconButton.filledTonal(
                      tooltip: 'Выбрать обложку плейлиста',
                      onPressed: enabled ? _chooseCover : null,
                      style: aurora
                          .iconButton(context)
                          .copyWith(
                            backgroundColor: WidgetStatePropertyAll(
                              aurora.base.withValues(alpha: .90),
                            ),
                          ),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (album)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.album_outlined,
                              size: 17,
                              color: aurora.accent,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Пользовательский альбом',
                                style: TextStyle(color: aurora.muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      detail.playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: box.maxWidth >= 500 ? 32 : 23,
                        fontWeight: FontWeight.w700,
                        color: aurora.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (album && credits.isNotEmpty) summary,
                    duration,
                    const SizedBox(height: 6),
                    play,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _restore(PlaylistEntry entry) async {
    try {
      final path = await widget.linkPicker();
      if (path != null && mounted)
        await _run(
          (playlist) => widget.repository.relink(
            playlist.id,
            playlist.revision,
            entry.id,
            path,
          ),
        );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _reorder(int from, int to) {
    if (_busy || _loading) return;
    final ids = _detail!.entries.map((entry) => entry.id).toList();
    ids.insert(to, ids.removeAt(from));
    _run(
      (playlist) =>
          widget.repository.reorder(playlist.id, playlist.revision, ids),
    );
  }

  Future<void> _play([int? index]) async {
    if (_busy ||
        _loading ||
        _detail!.unavailableCount > 0 ||
        widget.onPlay == null)
      return;
    final detail = _detail!;
    final selected = index == null ? null : detail.entries[index].id;
    final entries = detail.entries
        .where((entry) => entry.albumConflict == null)
        .toList();
    final start = selected == null
        ? 0
        : entries.indexWhere((entry) => entry.id == selected);
    if (entries.isEmpty || start < 0) return;
    final tracks = entries
        .map(
          (entry) =>
              entry.track.toPlayable(playlistEntry: (widget.id, entry.id)),
        )
        .toList();
    setState(() => _busy = true);
    try {
      await widget.onPlay!(tracks, start);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editDisc(PlaylistEntry entry) async {
    final result = await albumDiscDialog(context, entry.albumDisc);
    if (result != null && mounted) {
      await _run(
        (playlist) => widget.repository.setAlbumDisc(
          playlist.id,
          playlist.revision,
          entry.id,
          result.disc,
        ),
      );
    }
  }

  Future<void> _writeAlbum() async {
    final detail = _detail!;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Записать теги альбома в файлы?'),
        content: Text(
          '«${detail.playlist.name}». Запись изменит теги файлов MP3 и FLAC '
          'и создаст резервную копию каждого изменённого файла. '
          'Текущие обложки сохранятся, если для альбома не задана общая обложка.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Записать теги'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final library = widget.library;
    if (library?.mutating == true) return;
    AlbumWriteReport? report;
    await _run((_) async {
      Future<AlbumWriteReport> save() => widget.repository.writeAlbumTags(
        detail.playlist.id,
        detail.playlist.revision,
      );
      report = library == null
          ? await save()
          : await library.writeMetadata(save);
    });
    if (!mounted || report == null) return;
    final result = report!;
    final saved = result.items
        .where((item) => item.status == AlbumWriteStatus.saved)
        .length;
    await showAppDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Результат записи тегов'),
        content: SizedBox(
          width: 520,
          height: (MediaQuery.sizeOf(context).height * .45).clamp(60.0, 340.0),
          child: ListView.builder(
            itemCount: result.items.length + 1,
            itemBuilder: (_, index) {
              if (index == 0)
                return Text(
                  [
                    'Сохранено: $saved из ${result.items.length}',
                    if (result.catalogWarning case final warning?) warning,
                  ].join('\n'),
                );
              final item = result.items[index - 1];
              return ListTile(
                title: Text(p.basename(item.path)),
                subtitle: Text(
                  [
                    if (item.message case final message?) message,
                    if (item.backupPath case final backup?)
                      'Резервная копия: $backup',
                  ].join('\n'),
                ),
                leading: Icon(
                  item.status == AlbumWriteStatus.saved
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _entryMenu(int index) => [
    if (widget.library != null)
      PopupMenuItem(
        value: 'edit',
        enabled:
            _detail!.entries[index].available &&
            !widget.library!.mutating &&
            ['.mp3', '.flac'].contains(
              p.extension(_detail!.entries[index].track.path).toLowerCase(),
            ),
        child: const Text('Редактировать метаданные'),
      ),
    if (_detail!.playlist.isAlbum &&
        _detail!.entries[index].albumConflict == null)
      const PopupMenuItem(value: 'disc', child: Text('Номер диска')),
    PopupMenuItem(
      value: 'up',
      enabled: index > 0,
      child: const Text('Переместить выше'),
    ),
    PopupMenuItem(
      value: 'down',
      enabled: index + 1 < _detail!.entries.length,
      child: const Text('Переместить ниже'),
    ),
    const PopupMenuItem(value: 'restore', child: Text('Восстановить ссылку')),
    const PopupMenuItem(value: 'add', child: Text('Добавить в плейлист')),
    const PopupMenuItem(value: 'remove', child: Text('Удалить из плейлиста')),
  ];
  void _entryAction(int index, String action) {
    final entry = _detail!.entries[index];
    switch (action) {
      case 'edit':
        editTrackMetadataPath(context, entry.track.path, widget.library!);
      case 'disc':
        _editDisc(entry);
      case 'up':
        _reorder(index, index - 1);
      case 'down':
        _reorder(index, index + 1);
      case 'restore':
        _restore(entry);
      case 'add':
        addToPlaylist(context, widget.repository, [entry.track]).then((_) {
          if (mounted) _load();
        });
      case 'remove':
        _run(
          (playlist) => widget.repository.remove(
            playlist.id,
            playlist.revision,
            entry.id,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final enabled = !_busy && !_loading;
    final aurora = AuroraAppearance.of(context);
    final unavailable = detail?.unavailableCount ?? 0;
    final warning = unavailable == 0
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Недоступных файлов: $unavailable. Восстановите ссылки или удалите записи из плейлиста.',
            ),
          );
    final hero = aurora == null || detail == null
        ? null
        : Column(
            children: [
              _overview(detail, enabled, aurora),
              if (warning != null) warning,
            ],
          );
    return Scaffold(
      backgroundColor: aurora == null ? null : Colors.transparent,
      appBar: AppBar(
        toolbarHeight: aurora == null ? null : 46,
        leading: widget.onBack == null
            ? null
            : BackButton(onPressed: widget.onBack),
        title: aurora == null || detail == null
            ? Text(detail?.playlist.name ?? 'Плейлист')
            : null,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Обновить плейлист',
            style: aurora?.iconButton(context),
            onPressed: enabled ? _load : null,
            icon: const Icon(Icons.refresh),
          ),
          if (detail != null)
            PopupMenuButton<String>(
              popUpAnimationStyle: reducedAnimationStyle(context),
              tooltip: 'Действия плейлиста',
              enabled: enabled,
              style: aurora?.iconButton(context),
              onSelected: (action) => switch (action) {
                'rename' => _rename(),
                'properties' => _properties(),
                'reset-cover' => _resetCover(),
                'choose-cover' => _chooseCover(),
                'write-album' => _writeAlbum(),
                _ => _delete(),
              },
              itemBuilder: (_) => [
                if (aurora == null && !detail.playlist.isAlbum)
                  const PopupMenuItem(
                    value: 'rename',
                    child: Text('Переименовать'),
                  ),
                const PopupMenuItem(
                  value: 'properties',
                  child: Text('Свойства'),
                ),
                if (detail.playlist.isAlbum && aurora == null)
                  const PopupMenuItem(
                    value: 'choose-cover',
                    child: Text('Выбрать обложку'),
                  ),
                if (detail.playlist.isAlbum)
                  PopupMenuItem(
                    value: 'write-album',
                    enabled:
                        detail.entries.isNotEmpty &&
                        widget.library?.mutating != true,
                    child: const Text('Записать теги в MP3 и FLAC'),
                  ),
                if (aurora != null || detail.playlist.isAlbum)
                  const PopupMenuItem(
                    value: 'reset-cover',
                    child: Text('Сбросить обложку'),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Удалить плейлист'),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (_loading || _busy) const BusyIndicator.bar(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          if (detail != null) ...[
            if (aurora == null) _overview(detail, enabled, aurora),
            if (aurora == null && warning != null) warning,
            Expanded(
              child: detail.entries.isEmpty
                  ? hero == null
                        ? const Center(
                            child: Text(
                              'Добавьте треки через меню «Добавить в плейлист»',
                            ),
                          )
                        : ListView(
                            children: [
                              hero,
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Добавьте треки через меню «Добавить в плейлист»',
                                ),
                              ),
                            ],
                          )
                  : ReorderableListView.builder(
                      header: hero,
                      proxyDecorator: MediaQuery.disableAnimationsOf(context)
                          ? (child, _, _) => Material(
                              type: MaterialType.transparency,
                              child: child,
                            )
                          : null,
                      buildDefaultDragHandles: false,
                      onReorderItem: _reorder,
                      itemCount: detail.entries.length,
                      itemBuilder: (context, index) {
                        final entry = detail.entries[index];
                        final playing = CurrentTrackScope.playingOf(
                          context,
                          entry.track.path,
                          entry: (widget.id, entry.id),
                          matchPath: _firstEntries.contains(entry.id),
                        );
                        final handle = ReorderableDragStartListener(
                          index: index,
                          enabled: enabled,
                          child: const Icon(Icons.drag_handle),
                        );
                        final tile = GestureDetector(
                          key: aurora == null ? ValueKey(entry.id) : null,
                          onSecondaryTapDown: enabled
                              ? (details) async {
                                  final overlay =
                                      Overlay.of(context).context
                                              .findRenderObject()!
                                          as RenderBox;
                                  final point = overlay.globalToLocal(
                                    details.globalPosition,
                                  );
                                  final action = await showMenu<String>(
                                    popUpAnimationStyle: reducedAnimationStyle(
                                      context,
                                    ),
                                    context: context,
                                    position: RelativeRect.fromSize(
                                      Rect.fromLTWH(point.dx, point.dy, 0, 0),
                                      overlay.size,
                                    ),
                                    items: _entryMenu(index),
                                  );
                                  if (mounted && action != null)
                                    _entryAction(index, action);
                                }
                              : null,
                          child: ListTile(
                            tileColor: currentTrackTint(aurora, playing),
                            leading: aurora == null
                                ? handle
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      handle,
                                      const SizedBox(width: 6),
                                      AuroraArtwork(
                                        appearance: aurora,
                                        size: 40,
                                        radius: 8,
                                        path: entry.track.coverKey == null
                                            ? null
                                            : widget.repository.trackCoverPath(
                                                entry.track.coverKey!,
                                              ),
                                      ),
                                    ],
                                  ),
                            dense: aurora == null ? null : true,
                            contentPadding: aurora == null
                                ? null
                                : const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                            shape: aurora == null
                                ? null
                                : RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                            hoverColor: aurora?.interaction({
                              WidgetState.hovered,
                            }),
                            focusColor: aurora?.interaction({
                              WidgetState.focused,
                            }),
                            splashColor: aurora?.interaction({
                              WidgetState.pressed,
                            }),
                            textColor: aurora?.ink,
                            iconColor: aurora?.muted,
                            title: trackTitle(
                              Text(
                                entry.track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              indicatorKey: ValueKey(
                                'playlist-current-track-${entry.id}',
                              ),
                              playing: playing,
                              appearance: aurora,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  aurora != null && entry.track.artists.isEmpty
                                      ? 'Неизвестный исполнитель'
                                      : entry.track.artists.join(' / '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: aurora == null
                                      ? null
                                      : TextStyle(
                                          color: aurora.muted,
                                          fontSize: 12,
                                        ),
                                ),
                                if (entry.albumConflict != null)
                                  const Text(
                                    'Трек закреплён за другой записью',
                                  ),
                                if (!entry.available)
                                  Text(
                                    entry.error!,
                                    key: Key('playlist-missing-${entry.id}'),
                                    maxLines: aurora == null ? null : 2,
                                    overflow: aurora == null
                                        ? null
                                        : TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                if (aurora == null)
                                  Text(
                                    entry.track.path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            onTap:
                                enabled &&
                                    unavailable == 0 &&
                                    entry.albumConflict == null &&
                                    widget.onPlay != null
                                ? () => _play(index)
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!entry.available)
                                  IconButton(
                                    tooltip: 'Восстановить ссылку',
                                    onPressed: enabled
                                        ? () => _restore(entry)
                                        : null,
                                    icon: const Icon(Icons.link),
                                  ),
                                PopupMenuButton<String>(
                                  popUpAnimationStyle: reducedAnimationStyle(
                                    context,
                                  ),
                                  key: Key('playlist-entry-menu-${entry.id}'),
                                  tooltip: 'Действия записи',
                                  style: aurora?.iconButton(context),
                                  icon: aurora == null
                                      ? null
                                      : const Icon(Icons.more_horiz_rounded),
                                  enabled: enabled,
                                  onSelected: (action) =>
                                      _entryAction(index, action),
                                  itemBuilder: (_) => _entryMenu(index),
                                ),
                                if (aurora != null)
                                  Text(
                                    libraryTime(entry.track.durationMs),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: aurora.muted),
                                  ),
                              ],
                            ),
                          ),
                        );
                        if (aurora == null) return tile;
                        return AuroraTrackSurface(
                          key: ValueKey(entry.id),
                          appearance: aurora,
                          child: tile,
                        );
                      },
                    ),
            ),
          ] else if (_loading)
            const Expanded(child: Center(child: BusyIndicator())),
        ],
      ),
    );
  }
}
