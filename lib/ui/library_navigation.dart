import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../settings/settings_controller.dart';
import 'design_system.dart';
import 'atmosphere.dart';
import 'aurora_scene.dart';

class LibraryNavigation extends StatelessWidget {
  const LibraryNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.order,
    required this.onReorder,
    this.horizontal = false,
    this.aurora,
  });
  final int selected;
  final ValueChanged<int> onSelected;
  final List<LibrarySection> order;
  final ReorderCallback onReorder;
  final bool horizontal;
  final AuroraAppearance? aurora;
  static const labels = ['Альбомы', 'Артисты', 'Треки', 'Плейлисты'];
  static const icons = [
    Icons.album_outlined,
    Icons.people_outline,
    Icons.music_note_outlined,
    Icons.queue_music,
  ];
  @override
  Widget build(BuildContext context) {
    final glass = GlassColors.of(context);
    if (!horizontal) {
      final list = ReorderableListView.builder(
        key: const Key('library-navigation'),
        padding: const EdgeInsets.all(8),
        buildDefaultDragHandles: false,
        onReorderItem: onReorder,
        proxyDecorator: (child, _, _) => Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(MusaniDesign.radius),
          child: child,
        ),
        itemCount: order.length,
        itemBuilder: (context, position) => _item(context, position, glass),
      );
      if (aurora case final appearance?) {
        return AuroraSurface(
          appearance: appearance,
          radius: 25,
          opacity: appearance.dark ? .26 : .47,
          highlight: .64,
          child: list,
        );
      }
      return Container(
        margin: glass == null ? null : const EdgeInsets.fromLTRB(12, 0, 4, 12),
        width: glass == null ? MusaniDesign.navigationWidth : 166,
        child: glass == null
            ? list
            : GlassSurface(glass: glass, radius: 17, child: list),
      );
    }
    final strip = SingleChildScrollView(
      key: const Key('library-navigation'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var position = 0; position < order.length; position++)
            _item(context, position, glass),
        ],
      ),
    );
    return SizedBox(
      height: aurora == null ? 64 : 54,
      child: glass == null || aurora != null
          ? strip
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: GlassSurface(glass: glass, radius: 16, child: strip),
            ),
    );
  }

  Widget _item(BuildContext context, int position, GlassColors? glass) {
    final index = order[position].index;
    final colors = Theme.of(context).colorScheme;
    final accent = aurora?.accent ?? glass?.accent ?? colors.primary;
    final active = selected == index;
    void move(int offset) => onReorder(position, position + offset);
    Widget row(bool showHandle) => Material(
      animationDuration: Duration.zero,
      color: active
          ? aurora?.accent.withValues(alpha: .15) ??
                glass?.selection ??
                accent.withValues(alpha: .12)
          : Colors.transparent,
      borderRadius: glass == null && aurora == null
          ? BorderRadius.circular(MusaniDesign.radius)
          : null,
      shape: glass == null && aurora == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MusaniDesign.radius),
              side: active
                  ? BorderSide(
                      color:
                          aurora?.accent.withValues(alpha: .54) ??
                          glass!.controlEdge,
                    )
                  : BorderSide.none,
            ),
      child: InkWell(
        borderRadius: BorderRadius.circular(MusaniDesign.radius),
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (aurora case final appearance?)
            return appearance.interaction(states);
          if (glass != null) return glass.controlOverlay(states);
          if (states.contains(WidgetState.pressed)) {
            return accent.withValues(alpha: .18);
          }
          if (states.contains(WidgetState.focused)) {
            return colors.primary.withValues(alpha: .14);
          }
          if (states.contains(WidgetState.hovered)) {
            return accent.withValues(alpha: .07);
          }
          return Colors.transparent;
        }),
        onTap: () => onSelected(index),
        child: Semantics(
          selected: selected == index,
          button: true,
          customSemanticsActions: aurora == null
              ? null
              : {
                  if (position > 0)
                    const CustomSemanticsAction(
                      label: 'Переместить раздел раньше',
                    ): () =>
                        move(-1),
                  if (position + 1 < order.length)
                    const CustomSemanticsAction(
                      label: 'Переместить раздел позже',
                    ): () =>
                        move(1),
                },
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              aurora == null ? 12 : 9,
              horizontal ? 12 : 4,
              aurora == null ? 12 : 9,
            ),
            child: Row(
              children: [
                Icon(
                  icons[index],
                  size: 18,
                  color: selected == index
                      ? accent
                      : aurora?.muted ??
                            glass?.muted ??
                            colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: aurora == null ? 12 : 13,
                      fontWeight: selected == index
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: selected == index
                          ? aurora?.ink ?? glass?.ink ?? accent
                          : aurora?.ink ??
                                glass?.muted ??
                                colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (!horizontal)
                  if (!showHandle)
                    const SizedBox(width: 20, height: 16)
                  else
                    Tooltip(
                      message: 'Перетащить раздел «${labels[index]}»',
                      child: ReorderableDragStartListener(
                        key: ValueKey('library-drag-${order[position].name}'),
                        index: position,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      key: ValueKey(order[position]),
      padding: horizontal
          ? const EdgeInsets.only(right: 4)
          : const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        width: horizontal ? 112 : null,
        child: aurora == null
            ? row(true)
            : CallbackShortcuts(
                bindings: {
                  if (position > 0)
                    SingleActivator(
                      horizontal
                          ? LogicalKeyboardKey.arrowLeft
                          : LogicalKeyboardKey.arrowUp,
                      alt: true,
                    ): () =>
                        move(-1),
                  if (position + 1 < order.length)
                    SingleActivator(
                      horizontal
                          ? LogicalKeyboardKey.arrowRight
                          : LogicalKeyboardKey.arrowDown,
                      alt: true,
                    ): () =>
                        move(1),
                },
                child: horizontal ? row(false) : _NavigationHover(builder: row),
              ),
      ),
    );
  }
}

class _NavigationHover extends StatefulWidget {
  const _NavigationHover({required this.builder});
  final Widget Function(bool hovered) builder;

  @override
  State<_NavigationHover> createState() => _NavigationHoverState();
}

class _NavigationHoverState extends State<_NavigationHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(_hovered),
  );
}
