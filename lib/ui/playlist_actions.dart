import 'package:material_ui/material_ui.dart';

import 'atmosphere.dart';

import '../library/models.dart';
import '../playlists/models.dart';
import '../playlists/playlist_repository.dart';
import 'motion.dart';

typedef PlaylistProperties = ({
  String name,
  bool isAlbum,
  UserAlbumMetadata metadata,
});

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
  builder: (_) => _PlaylistNameDialog(
    initial: playlist.name,
    album: playlist.isAlbum,
    metadata: playlist.albumMetadata,
  ),
);

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({
    this.initial,
    this.album,
    this.metadata = const UserAlbumMetadata(),
  });
  final String? initial;
  final bool? album;
  final UserAlbumMetadata metadata;
  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  late bool? _album = widget.album;
  late final _artist = TextEditingController(text: widget.metadata.artist);
  late final _genre = TextEditingController(text: widget.metadata.genre);
  late final _year = TextEditingController(
    text: widget.metadata.year == 0 ? '' : '${widget.metadata.year}',
  );
  late final _disc = TextEditingController(text: '${widget.metadata.disc}');
  final _form = GlobalKey<FormState>();
  void _save() {
    if (_form.currentState!.validate())
      Navigator.pop(context, (
        name: _name.text.trim(),
        isAlbum: _album ?? false,
        metadata: UserAlbumMetadata(
          artist: _artist.text,
          genre: _genre.text,
          year: int.tryParse(_year.text.trim()) ?? 0,
          disc: int.tryParse(_disc.text.trim()) ?? 1,
        ),
      ));
  }

  @override
  void dispose() {
    for (final field in [_name, _artist, _genre, _year, _disc]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      _album == true
          ? 'Свойства альбома'
          : _album != null
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
              decoration: InputDecoration(
                labelText: _album == true
                    ? 'Название альбома'
                    : 'Название плейлиста',
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
            if (_album == true) ...[
              TextFormField(
                controller: _artist,
                decoration: const InputDecoration(
                  labelText: 'Исполнитель альбома',
                ),
              ),
              TextFormField(
                controller: _genre,
                decoration: const InputDecoration(labelText: 'Жанр'),
              ),
              TextFormField(
                controller: _year,
                decoration: const InputDecoration(labelText: 'Год выпуска'),
                keyboardType: TextInputType.number,
                validator: (value) => _checkAlbumNumber(value, optional: true),
              ),
              TextFormField(
                controller: _disc,
                decoration: const InputDecoration(
                  labelText: 'Номер диска по умолчанию',
                ),
                keyboardType: TextInputType.number,
                validator: _checkAlbumNumber,
              ),
            ],
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

String? _checkAlbumNumber(String? value, {bool optional = false}) {
  final text = value?.trim() ?? '';
  if (optional && text.isEmpty) return null;
  final number = int.tryParse(text);
  return number == null || number < 1 || number > 9999
      ? 'Введите число от 1 до 9999'
      : null;
}

Future<void> savePlaylistProperties(
  PlaylistRepository repository,
  UserPlaylist playlist,
  PlaylistProperties properties,
) => properties.isAlbum
    ? repository.updateAlbum(
        playlist.id,
        playlist.revision,
        properties.name,
        properties.metadata,
      )
    : repository.updateProperties(
        playlist.id,
        playlist.revision,
        name: properties.name,
        isAlbum: false,
      );

Future<({int? disc})?> albumDiscDialog(
  BuildContext context,
  int? current,
) async {
  return showAppDialog<({int? disc})>(
    context: context,
    builder: (_) => _AlbumDiscDialog(current),
  );
}

class _AlbumDiscDialog extends StatefulWidget {
  const _AlbumDiscDialog(this.current);
  final int? current;
  @override
  State<_AlbumDiscDialog> createState() => _AlbumDiscDialogState();
}

class _AlbumDiscDialogState extends State<_AlbumDiscDialog> {
  final _form = GlobalKey<FormState>();
  late final _number = TextEditingController(text: widget.current?.toString());

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Номер диска композиции'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _number,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Номер диска',
          helperText: 'Пустое поле использует номер альбома',
        ),
        validator: (value) => _checkAlbumNumber(value, optional: true),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, (disc: int.tryParse(_number.text.trim())));
          }
        },
        child: const Text('Сохранить'),
      ),
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
