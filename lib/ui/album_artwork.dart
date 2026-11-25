import 'dart:io';

import 'package:material_ui/material_ui.dart';

class AlbumArtwork extends StatelessWidget {
  const AlbumArtwork({
    super.key,
    required this.displaySize,
    this.path,
    this.radius = 14,
    this.placeholder,
  });
  final double displaySize;
  final String? path;
  final double radius;
  final Widget? placeholder;

  int _decodeWidth(double pixelRatio) {
    final pixels = displaySize * pixelRatio;
    // A few shared sizes let neighboring views reuse the decoded image cache
    // and keep small window resizes from decoding all visible covers again.
    const widths = [48, 64, 96, 128, 192, 256, 384, 448, 512];
    return widths.firstWhere((width) => pixels <= width, orElse: () => 512);
  }

  @override
  Widget build(BuildContext context) {
    Widget fallback() =>
        placeholder ??
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.surfaceContainerHighest,
                Theme.of(context).colorScheme.surfaceContainerLow,
              ],
            ),
          ),
          child: Center(
            child: FractionallySizedBox(
              widthFactor: .44,
              heightFactor: .44,
              child: FittedBox(
                child: Icon(
                  Icons.album_outlined,
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .55),
                ),
              ),
            ),
          ),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: path == null
          ? fallback()
          : Image.file(
              File(path!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: _decodeWidth(MediaQuery.devicePixelRatioOf(context)),
              errorBuilder: (_, _, _) => fallback(),
            ),
    );
  }
}
