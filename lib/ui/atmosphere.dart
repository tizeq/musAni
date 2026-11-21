import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/settings_controller.dart';

/// Cover keys are content-addressed. Keep only the sampled colors in memory.
class ArtworkAccent extends ValueNotifier<Color?> {
  ArtworkAccent() : super(null);
  final _cache = <String, Color?>{};
  String? _path;
  int _generation = 0;

  Future<void> select(String? path) async {
    if (_path == path) return;
    _path = path;
    final generation = ++_generation;
    Color? color;
    if (path != null) {
      if (_cache.containsKey(path)) {
        color = _cache[path];
      } else {
        try {
          final bytes = await File(path).readAsBytes();
          if (generation != _generation) return;
          final codec = await ui.instantiateImageCodec(
            bytes,
            targetWidth: 16,
            targetHeight: 16,
          );
          try {
            final frame = await codec.getNextFrame();
            try {
              final data = await frame.image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              if (data != null) {
                // Weight saturated midtones, so white lettering and black margins
                // don't wash out the cover's dominant hue.
                final weights = List<double>.filled(12, 0);
                final samples = List<Color?>.filled(12, null);
                for (var i = 0; i < data.lengthInBytes; i += 4) {
                  if (data.getUint8(i + 3) < 128) continue;
                  final pixel = Color.fromARGB(
                    255,
                    data.getUint8(i),
                    data.getUint8(i + 1),
                    data.getUint8(i + 2),
                  );
                  final hsl = HSLColor.fromColor(pixel);
                  if (hsl.saturation < .16 ||
                      hsl.lightness < .09 ||
                      hsl.lightness > .92)
                    continue;
                  final bin = (hsl.hue / 30).floor() % 12;
                  weights[bin] += hsl.saturation;
                  samples[bin] = pixel;
                }
                final best = weights.reduce((a, b) => a > b ? a : b);
                color = samples[weights.indexOf(best)];
              }
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
          if (generation != _generation) return;
          if (_cache.length >= 48) _cache.remove(_cache.keys.first);
          _cache[path] = color;
        } on Exception {
          /* Missing or unreadable artwork uses the house palette. */
        }
      }
    }
    if (generation == _generation) value = color;
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}

class AccentScope extends InheritedNotifier<ArtworkAccent> {
  const AccentScope({
    super.key,
    required ArtworkAccent accent,
    required super.child,
  }) : super(notifier: accent);
}

class GlassFinish extends ThemeExtension<GlassFinish> {
  const GlassFinish(this.effects);
  final GlassEffects effects;
  @override
  GlassFinish copyWith({GlassEffects? effects}) =>
      GlassFinish(effects ?? this.effects);
  @override
  GlassFinish lerp(GlassFinish? other, double t) =>
      t < .5 ? this : other ?? this;
}

class GlassColors {
  GlassColors(this.dark, this.effects, Color? cover)
    : hue = cover == null ? 183 : HSLColor.fromColor(cover).hue;
  final bool dark;
  final GlassEffects effects;
  final double hue;
  bool get lite => effects == GlassEffects.lite;
  double get strength => switch (effects) {
    GlassEffects.lite => .28,
    GlassEffects.soft => .58,
    GlassEffects.full => 1,
  };
  Color tone(double angle, double sat, double light) =>
      HSLColor.fromAHSL(1, (hue + angle) % 360, sat, light).toColor();
  Color get ink => dark ? const Color(0xffedf9ff) : const Color(0xff102934);
  Color get muted => dark ? const Color(0xffc1d2db) : const Color(0xff425764);
  Color get base => dark ? const Color(0xff0c1824) : const Color(0xffe3edf1);
  Color get accent => tone(0, .74, dark ? .77 : .25);
  Color get pearl => tone(58, .78, dark ? 0.82 : .44);
  Color get lining => (dark ? Colors.white : const Color(0xff375b6d))
      .withValues(alpha: dark ? .24 : .21);
  Color get selection => Color.lerp(paneTint, accent, .11 * strength)!;
  Color get paneTint =>
      Color.lerp(base, dark ? const Color(0xff2a3854) : Colors.white, .56)!;
  Color get controlEdge => accent.withValues(alpha: dark ? .40 : .30);
  Color get divider => ink.withValues(alpha: dark ? .095 : .12);
  Color get menuColor => Color.lerp(paneTint, base, .16)!;
  OutlinedBorder get menuShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: BorderSide(color: lining),
  );

  Color controlOverlay(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed))
      return accent.withValues(alpha: .19);
    if (states.contains(WidgetState.focused))
      return accent.withValues(alpha: .16);
    if (states.contains(WidgetState.hovered)) return ink.withValues(alpha: .09);
    return Colors.transparent;
  }

  ButtonStyle iconStyle({bool active = false}) => IconButton.styleFrom(
    foregroundColor: active ? accent : muted,
    disabledForegroundColor: muted.withValues(alpha: .42),
    iconSize: 19,
    minimumSize: const Size.square(36),
  ).copyWith(overlayColor: WidgetStateProperty.resolveWith(controlOverlay));
  Color get onAccent => dark ? const Color(0xff0d242a) : Colors.white;

  static GlassColors? of(BuildContext context) {
    final theme = Theme.of(context);
    final finish = theme.extension<GlassFinish>();
    if (finish == null) return null;
    final cover = context
        .dependOnInheritedWidgetOfExactType<AccentScope>()
        ?.notifier
        ?.value;
    return GlassColors(
      theme.brightness == Brightness.dark,
      finish.effects,
      cover,
    );
  }
}

/// Keep the glass finish separate from the content that updates during playback.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.glass,
    required this.child,
    this.radius = 20,
    this.frosted = false,
  });

  final GlassColors glass;
  final Widget child;
  final double radius;
  final bool frosted;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: GlassPanePainter(
              glass,
              radius: radius,
              opacity: frosted && !glass.lite ? .69 : .84,
              reflectionStrength: frosted ? .62 : .52,
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

/// Stationary ribbons. The boundary records once per palette or size.
class GlassField extends CustomPainter {
  const GlassField(this.glass);
  final GlassColors glass;
  @override
  void paint(Canvas canvas, Size size) {
    final g = glass;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = g.base);
    canvas.save();
    canvas.clipRect(rect);
    canvas.scale(size.width / 1000, size.height / 650);
    final halo = Color.lerp(
      g.base,
      g.tone(140, .48, g.dark ? .45 : .65),
      .43 * g.strength,
    )!;
    final points = <Offset>[const Offset(760, 20)];
    for (var i = 0; i <= 48; i++) {
      final angle = 2 * math.pi * i / 48;
      points.add(
        Offset(760 + 750 * math.cos(angle), 20 + 530 * math.sin(angle)),
      );
    }
    final field = ui.Vertices(
      ui.VertexMode.triangleFan,
      points,
      colors: [halo, ...List.filled(49, g.base)],
    );
    canvas.drawVertices(field, BlendMode.srcOver, Paint());
    field.dispose();
    if (!g.lite) {
      final ribbon = Path()
        ..moveTo(135, -100)
        ..cubicTo(430, 240, 590, -100, 788, 34)
        ..cubicTo(920, 117, 840, 230, 1050, 266)
        ..lineTo(1060, 325)
        ..cubicTo(811, 275, 927, 170, 770, 78)
        ..cubicTo(593, -8, 456, 302, 126, -55)
        ..close();
      canvas.drawPath(
        ribbon,
        Paint()..color = g.pearl.withValues(alpha: .08 * g.strength),
      );
      const strands = 8;
      for (var i = 0; i < strands; i++) {
        final d = i * 6.5;
        final path = Path()
          ..moveTo(135, -100 + d)
          ..cubicTo(430, 240 - d, 590, -100 + 2 * d, 788, 34 + d)
          ..cubicTo(920, 117 - d, 840, 230 + d, 1050, 266 + d);
        final line = Color.lerp(g.accent, g.pearl, i / (strands - 1))!;
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = i == 0 ? 1.8 : 1
            ..color = line.withValues(
              alpha: (.025 + .21 * (1 - i / strands)) * g.strength,
            ),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GlassField old) =>
      old.glass.hue != glass.hue ||
      old.glass.dark != glass.dark ||
      old.glass.effects != glass.effects;
}

class GlassPanePainter extends CustomPainter {
  const GlassPanePainter(
    this.glass, {
    this.radius = 23,
    this.opacity = .91,
    this.reflectionStrength = 1,
  });
  final GlassColors glass;
  final double radius;
  final double opacity;
  final double reflectionStrength;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(.5),
      Radius.circular(radius),
    );
    canvas.drawRRect(
      shape,
      Paint()..color = glass.paneTint.withValues(alpha: opacity),
    );
    if (!glass.lite) {
      canvas.save();
      canvas.clipRRect(shape, doAntiAlias: false);
      _reflection(
        canvas,
        Offset(size.width * .14, -6),
        Size(size.width * .24, size.height * .77),
        glass.pearl,
        .28,
      );
      _reflection(
        canvas,
        Offset(size.width * .72, size.height + 3),
        Size(size.width * .34, size.height * .78),
        glass.accent,
        .22,
      );
      canvas.restore();
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..color = glass.lining
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _reflection(
    Canvas canvas,
    Offset center,
    Size radius,
    Color color,
    double opacity,
  ) {
    const steps = 24;
    final points = <Offset>[center];
    for (var i = 0; i <= steps; i++) {
      final angle = i * math.pi * 2 / steps;
      points.add(
        center +
            Offset(
              math.cos(angle) * radius.width,
              math.sin(angle) * radius.height,
            ),
      );
    }
    final light = ui.Vertices(
      ui.VertexMode.triangleFan,
      points,
      colors: [
        color.withValues(alpha: opacity * glass.strength * reflectionStrength),
        ...List.filled(steps + 1, color.withValues(alpha: 0)),
      ],
    );
    canvas.drawVertices(light, BlendMode.srcOver, Paint());
    light.dispose();
  }

  @override
  bool shouldRepaint(GlassPanePainter old) =>
      glass.dark != old.glass.dark ||
      glass.effects != old.glass.effects ||
      glass.hue != old.glass.hue ||
      radius != old.radius ||
      opacity != old.opacity ||
      reflectionStrength != old.reflectionStrength;
}

class SleeveShade extends CustomPainter {
  const SleeveShade();
  @override
  void paint(Canvas canvas, Size size) {
    final vertices = <Offset>[];
    final colors = <Color>[];
    for (final (stop, alpha) in [(0.0, 26), (.38, 0), (.72, 190), (1.0, 248)]) {
      vertices.addAll([
        Offset(0, size.height * stop),
        Offset(size.width, size.height * stop),
      ]);
      colors.addAll(List.filled(2, Color.fromARGB(alpha, 7, 15, 26)));
    }
    final shade = ui.Vertices(
      ui.VertexMode.triangleStrip,
      vertices,
      colors: colors,
    );
    canvas.drawVertices(shade, BlendMode.srcOver, Paint());
    shade.dispose();
  }

  @override
  bool shouldRepaint(SleeveShade old) => false;
}
