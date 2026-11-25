import 'package:material_ui/material_ui.dart';

import '../library/library_controller.dart';
import '../playlists/models.dart';
import '../playlists/playlist_repository.dart';
import 'library_widgets.dart';
import 'playlist_route.dart';
import 'playlist_actions.dart';
import 'playlist_page.dart';
import 'motion.dart';
import 'aurora_scene.dart';
import 'playlist_cover.dart';

class PlaylistsView extends StatefulWidget {
  const PlaylistsView({
    super.key,
    required this.repository,
    this.onPlay,
    this.library,
    this.linkPicker = pickPlaylistLink,
    this.active = true,
  });
  final PlaylistRepository repository;
  final PlaylistPlayback? onPlay;
  final LibraryController? library;
  final PlaylistLinkPicker linkPicker;
  final bool active;
  @override
  State<PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<PlaylistsView> {
  List<UserPlaylist>? _items;
  String? _error;
  bool _busy = false;
  int _request = 0;
  int? _catalogRevision;
  @override
  void initState() {
    super.initState();
    widget.library?.addListener(_catalogChanged);
    _load();
  }

  @override
  void didUpdateWidget(PlaylistsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != widget.library) {
      oldWidget.library?.removeListener(_catalogChanged);
      widget.library?.addListener(_catalogChanged);
      _catalogChanged();
    }
    if (widget.active && !oldWidget.active && !_busy) _load();
  }

  void _catalogChanged() {
    if (!_busy &&
        widget.active &&
        _catalogRevision != widget.library?.catalogRevision)
      _load();
  }

  @override
  void dispose() {
    widget.library?.removeListener(_catalogChanged);
    super.dispose();
  }

  Future<void> _load() async {
    _catalogRevision = widget.library?.catalogRevision;
    final request = ++_request;
    try {
      final items = await widget.repository.list();
      if (mounted && request == _request)
        setState(() {
          _items = items;
          _error = null;
        });
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = '$error');
    }
  }

  Future<void> _change(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
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

  Future<void> _create() async {
    final name = await playlistNameDialog(context);
    if (name != null && mounted)
      await _change(() async {
        await widget.repository.create(name);
      });
  }

  Future<void> _action(UserPlaylist playlist, String action) async {
    if (action == 'properties') {
      final properties = await playlistPropertiesDialog(context, playlist);
      if (properties != null && mounted)
        await _change(
          () => savePlaylistProperties(widget.repository, playlist, properties),
        );
    } else if (action == 'rename') {
      final name = await playlistNameDialog(context, initial: playlist.name);
      if (name != null && mounted)
        await _change(
          () => widget.repository.rename(playlist.id, playlist.revision, name),
        );
    } else if (await confirmPlaylistDelete(context, playlist.name) && mounted) {
      await _change(
        () => widget.repository.delete(playlist.id, playlist.revision),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final aurora = AuroraAppearance.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Плейлисты',
                style: aurora == null
                    ? null
                    : TextStyle(
                        color: aurora.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
              ),
              FilledButton.icon(
                style: aurora?.accentButton(),
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.add),
                label: const Text('Создать плейлист'),
              ),
            ],
          ),
        ),
        if (_busy) const BusyIndicator.bar(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Повторить')),
              ],
            ),
          ),
        Expanded(
          child: _items == null
              ? _error == null
                    ? const LibraryLoadingIndicator()
                    : const SizedBox()
              : _items!.isEmpty
              ? const Center(child: Text('Плейлистов пока нет'))
              : ListView.builder(
                  itemCount: _items!.length,
                  itemBuilder: (context, index) {
                    final playlist = _items![index];
                    final album = playlist.isAlbum;
                    final description = Text(
                      '${album ? 'Альбом · ' : ''}${aurora == null ? '${playlist.trackCount} треков' : libraryTrackCount(playlist.trackCount)} · ${libraryTime(playlist.durationMs)}',
                      style: aurora == null
                          ? null
                          : TextStyle(color: aurora.muted),
                    );
                    return ListTile(
                      key: Key('playlist-${playlist.id}'),
                      leading: aurora == null
                          ? Icon(
                              album ? Icons.album_outlined : Icons.queue_music,
                            )
                          : PlaylistCover(
                              repository: widget.repository,
                              playlist: playlist,
                              appearance: aurora,
                              size: 51,
                              catalogRevision: widget.library?.catalogRevision,
                            ),
                      textColor: aurora?.ink,
                      title: Text(
                        playlist.name,
                        maxLines: aurora == null ? null : 1,
                        overflow: aurora == null ? null : TextOverflow.ellipsis,
                      ),
                      subtitle: album
                          ? Row(
                              children: [
                                Icon(
                                  Icons.album_outlined,
                                  size: 15,
                                  color: aurora?.accent,
                                ),
                                const SizedBox(width: 5),
                                Flexible(child: description),
                              ],
                            )
                          : description,
                      onTap: _busy
                          ? null
                          : () async {
                              await Navigator.of(context).push(
                                playlistRoute(
                                  context,
                                  (_) => PlaylistPage(
                                    id: playlist.id,
                                    repository: widget.repository,
                                    onPlay: widget.onPlay,
                                    library: widget.library,
                                    linkPicker: widget.linkPicker,
                                  ),
                                ),
                              );
                              if (mounted) await _load();
                            },
                      trailing: PopupMenuButton<String>(
                        style: aurora?.iconButton(context),
                        popUpAnimationStyle: reducedAnimationStyle(context),
                        tooltip: 'Действия плейлиста',
                        enabled: !_busy,
                        onSelected: (action) => _action(playlist, action),
                        itemBuilder: (_) => [
                          if (aurora == null)
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text('Переименовать'),
                            ),
                          const PopupMenuItem(
                            value: 'properties',
                            child: Text('Свойства'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Удалить плейлист'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
