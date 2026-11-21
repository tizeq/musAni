import 'package:material_ui/material_ui.dart';

AnimationStyle? reducedAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null;

ChipAnimationStyle? reducedChipStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? ChipAnimationStyle(
        selectAnimation: AnimationStyle.noAnimation,
        enableAnimation: AnimationStyle.noAnimation,
        avatarDrawerAnimation: AnimationStyle.noAnimation,
        deleteDrawerAnimation: AnimationStyle.noAnimation,
      )
    : null;

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
  animationStyle: reducedAnimationStyle(context),
);

void showAppSnackBar(BuildContext context, SnackBar snackBar) =>
    ScaffoldMessenger.of(context).showSnackBar(
      snackBar,
      snackBarAnimationStyle:
          reducedAnimationStyle(context) ??
          const AnimationStyle(
            duration: Duration(milliseconds: 250),
            reverseDuration: Duration(milliseconds: 250),
          ),
    );

class BusyIndicator extends StatelessWidget {
  const BusyIndicator({super.key}) : bar = false, minHeight = null;
  const BusyIndicator.bar({super.key, this.minHeight}) : bar = true;
  final bool bar;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    // A steady indicator preserves feedback without scheduling a ticker.
    final value = reduced ? .4 : null;
    const label = 'Выполняется…';
    final indicator = bar
        ? LinearProgressIndicator(
            value: value,
            minHeight: minHeight,
            semanticsLabel: label,
          )
        : CircularProgressIndicator(value: value, semanticsLabel: label);
    return reduced
        ? Semantics(
            label: label,
            liveRegion: true,
            excludeSemantics: true,
            child: indicator,
          )
        : indicator;
  }
}
