import 'package:material_ui/material_ui.dart';

import '../settings/settings_controller.dart';
import 'atmosphere.dart';

/// Shared foundations; future layout preferences can use these without owning
/// playback or catalog state. Theme choice is deliberately separate from layout.
abstract final class MusaniDesign {
  static const space = 4.0;
  static const radius = 12.0;
  static const panelRadius = 20.0;
  static const motion = Duration(milliseconds: 180);
  static const navigationWidth = 152.0;

  static ThemeData theme(
    MusaniTheme mode,
    Brightness brightness, {
    bool reduceMotion = false,
    GlassEffects glassEffects = GlassEffects.soft,
  }) {
    final atmosphere = mode == MusaniTheme.atmosphere;
    final dark = brightness == Brightness.dark;
    final (surface, text, muted, low, high, outline, glow) = switch ((
      mode,
      brightness,
    )) {
      (MusaniTheme.minimal, Brightness.light) => (
        0xfffaf8f3,
        0xff292c2c,
        0xff686762,
        0xfff0ede6,
        0xffe9e5dc,
        0xffd9d4ca,
        0xfffaf8f3,
      ),
      (MusaniTheme.minimal, Brightness.dark) => (
        0xff202120,
        0xffefede7,
        0xffbfbbb3,
        0xff292a28,
        0xff393a36,
        0xff494a44,
        0xff202120,
      ),
      (MusaniTheme.atmosphere, Brightness.light) => (
        0xfffbf7fa,
        0xff2d2533,
        0xff6f5c70,
        0xfff3eaf2,
        0xffebdfeb,
        0xffd9cbd8,
        0xffe9d8eb,
      ),
      (MusaniTheme.atmosphere, Brightness.dark) => (
        0xff201e2a,
        0xfff2e9e5,
        0xffbcb1bd,
        0xff272431,
        0xff383240,
        0xff49404c,
        0xff393047,
      ),
    };
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xffa75335),
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xffefb798) : const Color(0xff91472e),
          onPrimary: dark ? const Color(0xff35251f) : Colors.white,
          surface: Color(surface),
          onSurface: Color(text),
          onSurfaceVariant: Color(muted),
          surfaceContainerLow: Color(low),
          surfaceContainerHighest: Color(high),
          outlineVariant: Color(outline),
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: 'sans',
      scaffoldBackgroundColor: colors.surface,
      visualDensity: VisualDensity.compact,
    );
    return base.copyWith(
      splashFactory: reduceMotion ? NoSplash.splashFactory : null,
      textButtonTheme: reduceMotion
          ? const TextButtonThemeData(
              style: ButtonStyle(animationDuration: Duration.zero),
            )
          : null,
      outlinedButtonTheme: reduceMotion
          ? const OutlinedButtonThemeData(
              style: ButtonStyle(animationDuration: Duration.zero),
            )
          : null,
      extensions: [
        if (atmosphere) GlassFinish(glassEffects),
        MusaniSurfaces(
          background: colors.surface,
          glow: Color(glow),
          atmospheric: atmosphere,
        ),
      ],
      textTheme: base.textTheme.copyWith(
        headlineSmall: TextStyle(
          fontSize: 26,
          height: 1.15,
          fontWeight: FontWeight.w600,
          letterSpacing: -.7,
          color: colors.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: colors.onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 11,
          height: 1.4,
          color: colors.onSurfaceVariant,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          height: 1.3,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 52,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        minVerticalPadding: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        selectedTileColor: colors.primary.withValues(alpha: .1),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 36),
          iconSize: 20,
          animationDuration: reduceMotion ? Duration.zero : null,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          animationDuration: reduceMotion ? Duration.zero : null,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
      ),
    );
  }
}

class MusaniSurfaces extends ThemeExtension<MusaniSurfaces> {
  const MusaniSurfaces({
    required this.background,
    required this.glow,
    required this.atmospheric,
  });
  final Color background;
  final Color glow;
  final bool atmospheric;
  static MusaniSurfaces of(BuildContext context) =>
      Theme.of(context).extension<MusaniSurfaces>() ??
      const MusaniSurfaces(
        background: Color(0xfffaf8f3),
        glow: Color(0xfffaf8f3),
        atmospheric: false,
      );
  @override
  MusaniSurfaces copyWith({
    Color? background,
    Color? glow,
    bool? atmospheric,
  }) => MusaniSurfaces(
    background: background ?? this.background,
    glow: glow ?? this.glow,
    atmospheric: atmospheric ?? this.atmospheric,
  );
  @override
  MusaniSurfaces lerp(covariant MusaniSurfaces? other, double t) =>
      other == null
      ? this
      : MusaniSurfaces(
          background: Color.lerp(background, other.background, t)!,
          glow: Color.lerp(glow, other.glow, t)!,
          atmospheric: t < .5 ? atmospheric : other.atmospheric,
        );
}

class LibraryBackdrop extends StatelessWidget {
  const LibraryBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final glass = GlassColors.of(context);
    if (glass != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: CustomPaint(painter: GlassField(glass))),
          Material(type: MaterialType.transparency, child: child),
        ],
      );
    }
    final surfaces = MusaniSurfaces.of(context);
    return CustomPaint(
      painter: _LibrarySurfacePainter(
        background: surfaces.background,
        glow: surfaces.atmospheric ? surfaces.glow : surfaces.background,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class _LibrarySurfacePainter extends CustomPainter {
  const _LibrarySurfacePainter({required this.background, required this.glow});
  final Color background;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = background;
    canvas.drawRect(Offset.zero & size, paint);
    if (background == glow) return;
    // Low-contrast bands avoid the hard edge observed with native gradients in
    // Linux captures. No blur, offscreen buffer or animation loop.
    const bands = 64;
    final height = size.height / bands;
    for (var i = 0; i < bands; i++) {
      final strength = .65 * (1 - i / (bands - 1));
      paint.color = Color.lerp(background, glow, strength)!;
      canvas.drawRect(
        Rect.fromLTWH(0, height * i, size.width, height + 1),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LibrarySurfacePainter oldDelegate) =>
      background != oldDelegate.background || glow != oldDelegate.glow;
}
