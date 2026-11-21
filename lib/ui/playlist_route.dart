import 'package:material_ui/material_ui.dart';

/// A playlist enters from the side, independently of the catalog tab motion.
Route<void> playlistRoute(BuildContext context, WidgetBuilder builder) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return PageRouteBuilder<void>(
    pageBuilder: (context, _, _) => builder(context),
    transitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 120),
    reverseTransitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 90),
    allowSnapshotting: false,
    transitionsBuilder: (_, animation, _, child) => AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: child),
      builder: (_, child) {
        final remaining = 1 - Curves.easeOutCubic.transform(animation.value);
        return Transform.translate(
          offset: Offset(12 * remaining, 0),
          child: child,
        );
      },
    ),
  );
}
