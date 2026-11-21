import 'package:material_ui/material_ui.dart';

import 'atmosphere.dart';

import '../library/models.dart';
import '../playlists/models.dart';
import '../playlists/playlist_repository.dart';
import 'motion.dart';

typedef PlaylistProperties = ({String name, bool isAlbum});

Future<String?> playlistNameDialog(
  BuildContext context, {
  String? initial,
}) async => (await showAppDialog<PlaylistProperties>(
  context: context,
  builder: (_) => _PlaylistNameDialog(initial: initial),
))?.name;

Future<PlaylistProperties?> playlistPropertiesDialog(
  BuildContext context,
  UserPlaylist playlist,
) => showAppDialog<PlaylistProperties>(
  context: context,
  builder: (_) =>
      _PlaylistNameDialog(initial: playlist.name, album: playlist.isAlbum),
);

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({this.initial, this.album});
  final String? initial;
  final bool? album;
  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  late bool? _album = widget.album;
  final _form = GlobalKey<FormState>();
  void _save() {
    if (_form.currentState!.validate())
      Navigator.pop(context, (
        name: _name.text.trim(),
        isAlbum: _album ?? false,
      ));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _album != null
          ? 'Свойства плейлиста'
          : widget.initial == null
          ? 'Создать плейлист'
          : 'Переименовать плейлист',
    ),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('playlist-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Название плейлиста',
              ),
              maxLength: 200,
              validator: (value) =>
                  value == null ||
                      value.trim().isEmpty ||
                      value.contains('\u0000')
                  ? 'Введите название'
                  : null,
              onFieldSubmitted: (_) => _save(),
            ),
            if (_album case final album?)
              SwitchListTile(
                key: const Key('playlist-as-album'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Считать альбомом'),
                value: album,
                onChanged: (value) => setState(() => _album = value),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(onPressed: _save, child: const Text('Сохранить')),
    ],
  );
}

Future<bool> confirmPlaylistDelete(BuildContext context, String name) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить плейлист?'),
        content: Text('«$name» будет удалён. Аудиофайлы сохранятся.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> addToPlaylist(
  BuildContext context,
  PlaylistRepository repository,
  List<PlaylistTrackRef> tracks,
) async {
  if (tracks.isEmpty) return false;
  final playlist = await showAppDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _AddToPlaylistDialog(repository: repository, tracks: tracks),
  );
  if (playlist != null && context.mounted)
    showAppSnackBar(
      context,
      SnackBar(
        content: Text(
          'В плейлист «$playlist» добавлено записей: ${tracks.length}',
        ),
      ),
    );
  return playlist != null;
}

class _AddToPlaylistDialog extends StatefulWidget {
  const _AddToPlaylistDialog({required this.repository, required this.tracks});
  final PlaylistRepository repository;
  final List<PlaylistTrackRef> tracks;
  @override
  State<_AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends State<_AddToPlaylistDialog> {
  List<UserPlaylist>? _playlists;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.repository.list();
      if (mounted)
        setState(() {
          _playlists = items;
          _error = null;
        });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _add(UserPlaylist playlist) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.add(
        playlist.id,
        playlist.revision,
        widget.tracks,
      );
      if (mounted) {
        setState(() => _busy = false);
        Navigator.pop(context, playlist.name);
      }
    } catch (error) {
      await _load();
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = await playlistNameDialog(context);
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final created = await widget.repository.create(name);
      if (!mounted) return;
      setState(() {
        _playlists = [created, ...?_playlists];
        _busy = false;
      });
      await _add(created);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Добавить в плейлист'),
      content: SizedBox(
        width: 440,
        height: 300,
        child: Column(
          children: [
            if (_busy) const BusyIndicator.bar(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Expanded(
              child: _playlists == null
                  ? _error == null
                        ? const Center(child: BusyIndicator())
                        : Center(
                            child: TextButton(
                              onPressed: _load,
                              child: const Text('Повторить'),
                            ),
                          )
                  : _playlists!.isEmpty
                  ? const Center(child: Text('Плейлистов пока нет'))
                  : ListView.builder(
                      itemCount: _playlists!.length,
                      itemBuilder: (_, index) {
                        final playlist = _playlists![index];
                        return ListTile(
                          key: Key('add-to-${playlist.id}'),
                          title: Text(playlist.name),
                          subtitle: Text('${playlist.trackCount} треков'),
                          onTap: _busy ? null : () => _add(playlist),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.add),
          label: const Text('Новый плейлист'),
        ),
      ],
    ),
  );
}

class TrackSelectionBar extends StatelessWidget {
  const TrackSelectionBar({
    super.key,
    required this.selected,
    required this.repository,
    required this.onClear,
    this.glass,
  });
  final List<LibraryTrack> selected;
  final PlaylistRepository repository;
  final VoidCallback onClear;
  final GlassColors? glass;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Выбрано: ${selected.length}',
          style: glass == null ? null : TextStyle(color: glass?.muted),
        ),
        TextButton.icon(
          style: glass == null
              ? null
              : TextButton.styleFrom(foregroundColor: glass?.accent).copyWith(
                  overlayColor: WidgetStateProperty.resolveWith(
                    glass!.controlOverlay,
                  ),
                ),
          icon: const Icon(Icons.playlist_add),
          label: const Text('Добавить в плейлист'),
          onPressed: () async {
            if (await addToPlaylist(
              context,
              repository,
              selected.map(PlaylistTrackRef.fromLibrary).toList(),
            ))
              onClear();
          },
        ),
        IconButton(
          style: glass?.iconStyle(),
          tooltip: 'Снять выделение',
          onPressed: onClear,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}
