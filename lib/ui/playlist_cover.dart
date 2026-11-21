import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../playlists/models.dart';
import '../playlists/playlist_repository.dart';
import 'album_artwork.dart';
import 'aurora_scene.dart';

typedef PlaylistCoverPicker = Future<XFile?> Function();

Future<XFile?> pickPlaylistCover() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'Изображения',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
    ),
  ],
);

Future<Uint8List> preparePlaylistCover(XFile file) async {
  if (await file.length() > 16 * 1024 * 1024) {
    throw const FormatException('Выберите изображение размером до 16 МБ');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    await file.readAsBytes(),
  );
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width * descriptor.height > 32 * 1024 * 1024) {
        throw const FormatException(
          'Выберите изображение разрешением до 32 Мп',
        );
      }
      final scale = math.min(
        1.0,
        384 / math.max(descriptor.width, descriptor.height),
      );
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final bytes = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (bytes == null)
            throw const FormatException('Не удалось подготовить обложку');
          return bytes.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

class PlaylistCover extends StatefulWidget {
  const PlaylistCover({
    super.key,
    required this.repository,
    required this.playlist,
    required this.appearance,
    required this.size,
    this.catalogRevision,
  });

  final PlaylistRepository repository;
  final UserPlaylist playlist;
  final AuroraAppearance appearance;
  final double size;
  final int? catalogRevision;

  @override
  State<PlaylistCover> createState() => _PlaylistCoverState();
}

class _PlaylistCoverState extends State<PlaylistCover> {
  late Future<PlaylistArtwork> _future = _load();

  Future<PlaylistArtwork> _load() => widget.repository.artwork(
    widget.playlist.id,
    revision: widget.playlist.revision,
    catalogRevision: widget.catalogRevision,
  );

  @override
  void didUpdateWidget(PlaylistCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.id != widget.playlist.id ||
        oldWidget.playlist.revision != widget.playlist.revision ||
        oldWidget.catalogRevision != widget.catalogRevision ||
        oldWidget.repository != widget.repository) {
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(widget.size > 72 ? 15 : 9),
      child: FutureBuilder<PlaylistArtwork>(
        future: _future,
        builder: (context, snapshot) {
          final artwork = snapshot.data;
          if (artwork?.image case final image?) {
            return Image.memory(
              image,
              key: Key('playlist-custom-cover-${widget.playlist.id}'),
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (_, _, _) => _placeholder(),
            );
          }
          final covers = artwork?.trackCovers ?? const <String>[];
          if (covers.isEmpty) return _placeholder();
          if (widget.playlist.isAlbum) {
            return AlbumArtwork(
              path: widget.repository.trackCoverPath(covers.first),
              displaySize: widget.size,
              radius: 0,
            );
          }
          return _mosaic(covers);
        },
      ),
    ),
  );

  Widget _placeholder() => ColoredBox(
    color: widget.appearance.plate,
    child: Center(
      child: Icon(
        widget.playlist.isAlbum
            ? Icons.album_outlined
            : Icons.queue_music_rounded,
        color: widget.appearance.accent,
        size: widget.size * .42,
      ),
    ),
  );

  Widget _mosaic(List<String> covers) {
    Widget tile(int index) => AlbumArtwork(
      path: widget.repository.trackCoverPath(covers[index]),
      displaySize: covers.length == 1 ? widget.size : widget.size / 2,
      radius: 0,
    );
    Widget stack(int first, int second) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: tile(first)),
        const SizedBox(height: 1),
        Expanded(child: tile(second)),
      ],
    );
    if (covers.length == 1) return tile(0);
    return Row(
      key: const Key('playlist-cover-mosaic'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: covers.length == 4 ? stack(0, 2) : tile(0)),
        const SizedBox(width: 1),
        Expanded(
          child: covers.length >= 3 ? stack(1, covers.length - 1) : tile(1),
        ),
      ],
    );
  }
}
