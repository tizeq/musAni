import 'package:material_ui/material_ui.dart' hide RepeatMode;

import '../library/library_controller.dart';
import '../playback/playback_engine.dart';
import 'current_track_details.dart';
import 'design_system.dart';
import 'motion.dart';
import 'aurora_scene.dart';

class PlaybackDock extends StatelessWidget {
  const PlaybackDock({
    super.key,
    required this.engine,
    required this.state,
    required this.busy,
    required this.run,
    required this.onToggleMute,
    required this.onShowQueue,
    required this.queueVisible,
    this.queueInCollection = false,
    this.library,
  });
  final PlaybackEngine engine;
  final PlaybackState state;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;
  final VoidCallback onToggleMute;
  final VoidCallback? onShowQueue;
  final bool queueVisible;
  final bool queueInCollection;
  final LibraryController? library;

  Widget _controls() {
    final enabled = state.queue.isNotEmpty && !busy;
    final previous = state.indexAtOffset(-1);
    final next = state.indexAtOffset(1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Предыдущий',
          onPressed: enabled && previous != null
              ? () => run(() => engine.jump(previous))
              : null,
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton.filled(
          tooltip: state.playing ? 'Пауза' : 'Воспроизвести',
          onPressed: enabled ? () => run(engine.toggle) : null,
          icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          tooltip: 'Следующий',
          onPressed: enabled && next != null
              ? () => run(() => engine.jump(next))
              : null,
          icon: const Icon(Icons.skip_next),
        ),
        Builder(builder: (context) => _repeat(context)),
      ],
    );
  }

  Widget _repeat(BuildContext context, {ButtonStyle? style, Color? active}) =>
      IconButton(
        key: const Key('repeat-mode'),
        tooltip: switch (state.repeatMode) {
          RepeatMode.off => 'Повтор выключен (Repeat Off)',
          RepeatMode.all => 'Повтор очереди (Repeat All)',
          RepeatMode.one => 'Повтор трека (Repeat One)',
        },
        isSelected: state.repeatMode != RepeatMode.off,
        style: style,
        color: state.repeatMode == RepeatMode.off
            ? Theme.of(context).disabledColor
            : active ?? Theme.of(context).colorScheme.primary,
        icon: Icon(
          state.repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
        ),
        onPressed: busy
            ? null
            : () => run(() => engine.setRepeatMode(state.repeatMode.next)),
      );

  Widget _volume({double? volume, double width = 124}) => SizedBox(
    width: width,
    child: Slider(
      value: (volume ?? state.volume).clamp(0, 100).toDouble(),
      max: 100,
      label: '${(volume ?? state.volume).round()}%',
      semanticFormatterCallback: (value) => 'Громкость ${value.round()}%',
      onChanged: busy ? null : (value) => run(() => engine.setVolume(value)),
    ),
  );

  String get _muteLabel =>
      state.volume > 0 ? 'Отключить звук' : 'Включить звук';
  IconData get _volumeIcon =>
      state.volume > 0 ? Icons.volume_up_outlined : Icons.volume_off_outlined;

  Widget _volumeMenu(BuildContext context, {ButtonStyle? style}) =>
      PopupMenuButton<void>(
        style: style,
        popUpAnimationStyle: reducedAnimationStyle(context),
        tooltip: 'Громкость',
        icon: Icon(_volumeIcon),
        itemBuilder: (_) => [
          PopupMenuItem<void>(
            enabled: false,
            child: StreamBuilder<double>(
              stream: engine.changes.map((state) => state.volume).distinct(),
              initialData: state.volume,
              builder: (_, snapshot) => _volume(volume: snapshot.data),
            ),
          ),
          PopupMenuItem<void>(
            enabled: !busy,
            onTap: onToggleMute,
            child: Text(_muteLabel),
          ),
        ],
      );

  Widget _details(BuildContext context, {double coverSize = 44}) =>
      state.queue.isEmpty
      ? Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Выберите музыку для воспроизведения',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        )
      : CurrentTrackDetails(
          track: state.queue[state.index.clamp(0, state.queue.length - 1)],
          library: library,
          coverSize: coverSize,
        );

  Widget _progress({bool inline = false}) => _PlaybackProgress(
    engine: engine,
    enabled: state.queue.isNotEmpty && !busy,
    onSeek: (position) => run(() => engine.seek(position)),
    inline: inline,
  );

  @override
  Widget build(BuildContext context) {
    final glass = AuroraAppearance.of(context);
    if (glass != null) return _atmosphere(context, glass);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        key: const Key('playback-dock'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(child: _progress()),
              if (constraints.maxWidth < 640) ...[
                _details(context),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [_controls(), _volumeMenu(context)],
                ),
              ] else
                Row(
                  children: [
                    Expanded(child: _details(context)),
                    _controls(),
                    const SizedBox(width: MusaniDesign.space * 6),
                    IconButton(
                      tooltip: _muteLabel,
                      icon: Icon(_volumeIcon, size: 18),
                      onPressed: busy ? null : onToggleMute,
                    ),
                    _volume(),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _atmosphere(BuildContext context, AuroraAppearance glass) {
    final color = glass.accent;
    final enabled = state.queue.isNotEmpty && !busy;
    final previous = state.indexAtOffset(-1);
    final next = state.indexAtOffset(1);
    final iconStyle = glass.iconButton(context);
    final playStyle = iconStyle.copyWith(
      minimumSize: const WidgetStatePropertyAll(Size.square(48)),
      iconSize: const WidgetStatePropertyAll(25),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? glass.muted.withValues(alpha: .42)
            : color,
      ),
    );
    final transport = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('dock-shuffle'),
          tooltip: state.shuffle
              ? 'Выключить перемешивание'
              : 'Перемешать очередь',
          isSelected: state.shuffle,
          style: iconStyle.copyWith(
            foregroundColor: state.shuffle
                ? WidgetStatePropertyAll(color)
                : null,
          ),
          onPressed: enabled && state.queue.length > 1
              ? () => run(() => engine.setShuffle(!state.shuffle))
              : null,
          icon: const Icon(Icons.shuffle_rounded),
        ),
        IconButton(
          tooltip: 'Предыдущий',
          style: iconStyle,
          onPressed: enabled && previous != null
              ? () => run(() => engine.jump(previous))
              : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        AuroraSurface(
          appearance: glass,
          radius: 25,
          highlight: enabled ? 1.22 : .32,
          child: IconButton(
            tooltip: state.playing ? 'Пауза' : 'Воспроизвести',
            style: playStyle,
            onPressed: enabled ? () => run(engine.toggle) : null,
            icon: Icon(
              state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Следующий',
          style: iconStyle,
          onPressed: enabled && next != null
              ? () => run(() => engine.jump(next))
              : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        _repeat(
          context,
          style: iconStyle.copyWith(
            foregroundColor: WidgetStatePropertyAll(
              state.repeatMode == RepeatMode.off ? glass.muted : color,
            ),
          ),
          active: color,
        ),
      ],
    );
    final queue = IconButton(
      tooltip: queueVisible
          ? queueInCollection
                ? 'Закрыть коллекцию'
                : 'Вернуться в библиотеку'
          : 'Открыть очередь',
      isSelected: queueVisible,
      onPressed: onShowQueue,
      style: iconStyle.copyWith(
        foregroundColor: queueVisible ? WidgetStatePropertyAll(color) : null,
      ),
      icon: const Icon(Icons.queue_music_rounded),
    );
    final progress = RepaintBoundary(child: _progress(inline: true));
    final roomy =
        MediaQuery.sizeOf(context).width >= 1220 &&
        MediaQuery.sizeOf(context).height >= 720;
    return Padding(
      padding: roomy
          ? const EdgeInsets.fromLTRB(12, 13, 12, 20)
          : const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: AuroraSurface(
        key: const Key('playback-dock'),
        appearance: glass,
        radius: 23,
        opacity: glass.dark ? .52 : .84,
        highlight: 1.22,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: glass.frame,
            thumbColor: color,
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: roomy ? 22 : 14,
              vertical: roomy ? 18 : 8,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (width >= 850) {
                  return Row(
                    children: [
                      SizedBox(
                        width: width * .31,
                        child: _details(context, coverSize: roomy ? 76 : 68),
                      ),
                      const SizedBox(width: 12),
                      transport,
                      const SizedBox(width: 14),
                      Expanded(child: progress),
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: _muteLabel,
                        style: iconStyle,
                        icon: Icon(_volumeIcon),
                        onPressed: busy ? null : onToggleMute,
                      ),
                      _volume(width: 86),
                      queue,
                    ],
                  );
                }
                final volume = _volumeMenu(context, style: iconStyle);
                if (width >= 520) {
                  return Row(
                    children: [
                      Expanded(child: _details(context, coverSize: 52)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [transport, progress],
                        ),
                      ),
                      volume,
                      queue,
                    ],
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _details(context)),
                        volume,
                        queue,
                      ],
                    ),
                    transport,
                    progress,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackProgress extends StatefulWidget {
  const _PlaybackProgress({
    required this.engine,
    required this.enabled,
    required this.onSeek,
    required this.inline,
  });
  final PlaybackEngine engine;
  final bool enabled;
  final ValueChanged<Duration> onSeek;
  final bool inline;

  @override
  State<_PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<_PlaybackProgress> {
  static const _sliderFlex = 3;
  static const _timeFlex = 2;
  static const _sliderInset = 6.0;

  int _trackPixels = 0;
  late Stream<(Duration, Duration)> _times = _subscribe();

  Stream<(Duration, Duration)> _subscribe() => widget.engine.changes
      .map((state) => (state.position, state.duration))
      .distinct((last, current) {
        if (last == current) return true;
        final (position, length) = current;
        if (!widget.inline || _trackPixels <= 0 || length <= Duration.zero) {
          return false;
        }
        final (previousPosition, previousLength) = last;
        if (previousLength != length ||
            previousPosition.inSeconds != position.inSeconds) {
          return false;
        }
        // Between whole seconds the dock changes only if the thumb crosses a pixel.
        int pixel(Duration time) =>
            time.inMicroseconds * _trackPixels ~/ length.inMicroseconds;
        return pixel(previousPosition) == pixel(position);
      });

  @override
  void didUpdateWidget(_PlaybackProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.engine != oldWidget.engine) _times = _subscribe();
  }

  String _time(Duration value) =>
      '${value.inSeconds ~/ 60}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => widget.inline
      ? LayoutBuilder(
          builder: (context, constraints) {
            final sliderWidth =
                constraints.maxWidth * _sliderFlex / (_sliderFlex + _timeFlex) -
                2 * _sliderInset;
            _trackPixels =
                (sliderWidth * MediaQuery.devicePixelRatioOf(context)).ceil();
            return _buildProgress();
          },
        )
      : _buildProgress();

  Widget _buildProgress() {
    final state = widget.engine.state;
    return StreamBuilder<(Duration, Duration)>(
      stream: _times,
      initialData: (state.position, state.duration),
      builder: (context, snapshot) {
        final (position, length) = snapshot.data!;
        final duration = length.inMilliseconds.toDouble();
        final max = duration > 0 ? duration : 1.0;
        final style = Theme.of(context).textTheme.bodySmall;
        final slider = Expanded(
          flex: widget.inline ? _sliderFlex : 1,
          child: Slider(
            padding: widget.inline
                ? const EdgeInsets.symmetric(horizontal: _sliderInset)
                : null,
            value: position.inMilliseconds.toDouble().clamp(0, max),
            max: max,
            semanticFormatterCallback: (value) =>
                _time(Duration(milliseconds: value.round())),
            onChanged: widget.enabled && duration > 0
                ? (value) =>
                      widget.onSeek(Duration(milliseconds: value.round()))
                : null,
          ),
        );
        return SizedBox(
          height: 30,
          child: Row(
            children: [
              if (!widget.inline) Text(_time(position), style: style),
              slider,
              if (widget.inline)
                Flexible(
                  flex: _timeFlex,
                  child: Text(
                    '${_time(position)} / ${_time(length)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                )
              else
                Text(_time(length), style: style),
            ],
          ),
        );
      },
    );
  }
}
