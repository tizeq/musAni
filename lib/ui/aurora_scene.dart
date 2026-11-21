import 'package:material_ui/material_ui.dart';

import '../settings/settings_controller.dart';
import 'album_artwork.dart';
import 'atmosphere.dart';

const _lightField = AssetImage('assets/atmosphere/aurora.webp');

class AuroraAppearance {
  const AuroraAppearance(this.brightness, this.effects);
  final Brightness brightness;
  final GlassEffects effects;
  static final _surfaces =
      <(Brightness, GlassEffects, double, double, double), BoxDecoration>{};

  static AuroraAppearance? of(BuildContext context) {
    final theme = Theme.of(context);
    final finish = theme.extension<GlassFinish>();
    return finish == null
        ? null
        : AuroraAppearance(theme.brightness, finish.effects);
  }

  bool get dark => brightness == Brightness.dark;
  Color get ink => dark ? const Color(0xfff2f3ff) : const Color(0xff162539);
  Color get muted => dark ? const Color(0xffb6bdd4) : const Color(0xff42556b);
  Color get accent => dark ? const Color(0xff7af4ed) : const Color(0xff00696e);
  Color get violet => const Color(0xff9388ff);
  Color get rose => const Color(0xffe980f4);
  Color get frame => ink.withValues(alpha: .22);
  Color get base => dark ? const Color(0xff10182d) : const Color(0xffeaf1f8);
  Color get plate => dark ? const Color(0xff1b2441) : const Color(0xfff2f7fc);

  ButtonStyle accentButton() => FilledButton.styleFrom(
    backgroundColor: accent,
    foregroundColor: dark ? const Color(0xff112739) : Colors.white,
  );
  double get reflections => switch (effects) {
    GlassEffects.full => 1,
    GlassEffects.soft => .62,
    GlassEffects.lite => 0,
  };

  BoxDecoration surface(double radius, double opacity, double highlight) {
    final key = (brightness, effects, radius, opacity, highlight);
    final cached = _surfaces[key];
    if (cached != null) return cached;
    final tint = plate.withValues(alpha: opacity);
    final strength = (reflections * highlight).clamp(0.0, 1.0);
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: strength == 0 ? tint : null,
      gradient: strength == 0
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  Color.lerp(
                    rose,
                    violet,
                    .28,
                  )!.withValues(alpha: .27 * strength),
                  tint,
                ),
                tint,
                Color.alphaBlend(
                  accent.withValues(alpha: .22 * strength),
                  tint,
                ),
              ],
              stops: const [0, .52, 1],
            ),
      border: Border.all(
        color: Color.lerp(
          frame,
          Color.lerp(violet, accent, .42)!.withValues(alpha: .60),
          strength,
        )!,
      ),
    );
    if (_surfaces.length >= 96) _surfaces.remove(_surfaces.keys.first);
    return _surfaces[key] = decoration;
  }

  Color interaction(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed))
      return accent.withValues(alpha: .19);
    if (states.contains(WidgetState.focused))
      return accent.withValues(alpha: .16);
    if (states.contains(WidgetState.hovered)) return ink.withValues(alpha: .08);
    return Colors.transparent;
  }

  ButtonStyle iconButton(BuildContext context) => IconButton.styleFrom(
    foregroundColor: ink,
    disabledForegroundColor: muted.withValues(alpha: .42),
    minimumSize: const Size.square(36),
    padding: EdgeInsets.zero,
    iconSize: 20,
    animationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : null,
  ).copyWith(overlayColor: WidgetStateProperty.resolveWith(interaction));
}

/// The only bitmap carried from the prototype is the decorative light field.
class AuroraBackdrop extends StatelessWidget {
  const AuroraBackdrop({
    super.key,
    required this.appearance,
    required this.child,
  });
  final AuroraAppearance appearance;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: appearance.base,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (appearance.reflections > 0)
          RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Image(
                  image: _lightField,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
                ColoredBox(
                  color: appearance.base.withValues(
                    alpha: appearance.dark
                        ? .10 + .48 * (1 - appearance.reflections)
                        : .85 + .10 * (1 - appearance.reflections),
                  ),
                ),
              ],
            ),
          ),
        child,
      ],
    ),
  );
}

class AuroraSurface extends StatelessWidget {
  const AuroraSurface({
    super.key,
    required this.appearance,
    required this.child,
    required this.radius,
    this.opacity = .34,
    this.highlight = .8,
  });
  final AuroraAppearance appearance;
  final Widget child;
  final double radius;
  final double opacity;
  final double highlight;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: appearance.surface(radius, opacity, highlight),
          ),
        ),
      ),
      child,
    ],
  );
}

class AuroraTrackSurface extends StatelessWidget {
  const AuroraTrackSurface({
    super.key,
    required this.appearance,
    required this.child,
  });

  final AuroraAppearance appearance;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Material(
      color: appearance.plate.withValues(alpha: appearance.dark ? .38 : .56),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: appearance.frame.withValues(alpha: .09)),
      ),
      child: child,
    ),
  );
}

class AuroraArtwork extends StatelessWidget {
  const AuroraArtwork({
    super.key,
    required this.appearance,
    required this.size,
    required this.radius,
    this.path,
    this.artworkKey,
  });
  final AuroraAppearance appearance;
  final double size;
  final double radius;
  final String? path;
  final Key? artworkKey;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      fit: StackFit.expand,
      children: [
        AlbumArtwork(
          key: artworkKey,
          path: path,
          displaySize: size,
          radius: radius,
          placeholder: DecoratedBox(
            decoration: appearance.surface(radius, .68, 1.2),
            child: Center(
              child: Icon(
                Icons.album_outlined,
                color: appearance.accent,
                size: size * .40,
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: appearance.frame),
            ),
          ),
        ),
      ],
    ),
  );
}
