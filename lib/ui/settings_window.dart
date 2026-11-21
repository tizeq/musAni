import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;

import '../playback/playback_engine.dart';
import '../settings/settings_controller.dart';
import '../settings/shortcuts.dart';
import 'motion.dart';

enum _Section {
  appearance('Оформление'),
  navigation('Навигация'),
  shortcuts('Горячие клавиши'),
  player('Плеер'),
  general('Общие');

  const _Section(this.label);
  final String label;
}

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({
    super.key,
    required this.settings,
    required this.engine,
  });
  final SettingsController settings;
  final PlaybackEngine engine;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  _Section _section = _Section.appearance;
  bool _playerBusy = false;
  String? _playerError;
  late final _repeatModes = widget.engine.changes
      .map((value) => value.repeatMode)
      .distinct();
  SettingsController get settings => widget.settings;
  bool get _busy => settings.saving || _playerBusy;

  Future<void> _setRepeat(RepeatMode mode) async {
    setState(() {
      _playerBusy = true;
      _playerError = null;
    });
    try {
      await widget.engine.setRepeatMode(mode);
    } catch (error) {
      if (mounted) setState(() => _playerError = '$error');
    } finally {
      if (mounted) setState(() => _playerBusy = false);
    }
  }

  Future<void> _capture(PlayerShortcut action) async {
    final chord = await showAppDialog<KeyChord>(
      context: context,
      builder: (_) => _CaptureShortcut(action: action, settings: settings),
    );
    if (chord != null && mounted) await settings.assign(action, chord);
  }

  Future<void> _reset() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить все настройки?'),
        content: const Text(
          'Будут восстановлены исходные значения, включая горячие клавиши и режим повтора.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (await settings.update(AppSettings()) &&
        mounted &&
        widget.engine.state.repeatMode != RepeatMode.off) {
      await _setRepeat(RepeatMode.off);
    }
  }

  Widget _choice<T>({
    required String title,
    required T current,
    required Iterable<T> options,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
  }) => ListTile(
    title: Text(title),
    trailing: PopupMenuButton<T>(
      tooltip: title,
      enabled: !_busy,
      popUpAnimationStyle: reducedAnimationStyle(context),
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final option in options)
          CheckedPopupMenuItem(
            value: option,
            checked: current == option,
            child: Text(label(option)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(label(current)),
      ),
    ),
  );

  List<Widget> _options(AppSettings value) => switch (_section) {
    _Section.appearance => [
      _choice(
        title: 'Визуальный стиль',
        current: value.style,
        options: MusaniTheme.values,
        label: (style) =>
            style == MusaniTheme.minimal ? 'Minimal' : 'Atmosphere',
        onChanged: (style) => settings.update(value.copyWith(style: style)),
      ),
      _choice(
        title: 'Цветовая схема',
        current: value.colors,
        options: ColorMode.values,
        label: (mode) => switch (mode) {
          ColorMode.system => 'System',
          ColorMode.light => 'Light',
          ColorMode.dark => 'Dark',
        },
        onChanged: (mode) => settings.update(value.copyWith(colors: mode)),
      ),
      if (value.style == MusaniTheme.atmosphere)
        _choice(
          title: 'Эффекты стекла',
          current: value.glassEffects,
          options: GlassEffects.values,
          label: (level) => switch (level) {
            GlassEffects.lite => 'Облегчённые',
            GlassEffects.soft => 'Мягкие',
            GlassEffects.full => 'Выразительные',
          },
          onChanged: (level) =>
              settings.update(value.copyWith(glassEffects: level)),
        ),
    ],
    _Section.navigation => [
      SwitchListTile(
        key: const Key('settings-show-albums'),
        title: const Text('Показывать раздел «Альбомы»'),
        value: value.showAlbumsInAtmosphere,
        onChanged: _busy
            ? null
            : (show) =>
                  settings.update(value.copyWith(showAlbumsInAtmosphere: show)),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'Чтобы изменить порядок, наведите курсор на раздел и потяните за ручку. С клавиатуры нажмите Alt и стрелку на выбранном разделе.',
        ),
      ),
    ],
    _Section.shortcuts => [
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Сочетания работают внутри musAni. В текстовых полях используются обычные клавиши ввода.',
        ),
      ),
      for (final action in PlayerShortcut.values)
        ListTile(
          title: Text(action.label),
          trailing: Tooltip(
            message: 'Переназначить: ${action.label}',
            child: TextButton(
              key: ValueKey('shortcut-${action.name}'),
              onPressed: _busy ? null : () => _capture(action),
              child: Text(value.shortcuts[action]!.label),
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _busy
              ? null
              : () => settings.update(value.copyWith(shortcuts: const {})),
          child: const Text('Сбросить горячие клавиши'),
        ),
      ),
    ],
    _Section.player => [
      _choice(
        title: 'Шаг громкости',
        current: value.volumeStep,
        options: AppSettings.volumeSteps,
        label: (step) => '$step%',
        onChanged: (step) => settings.update(value.copyWith(volumeStep: step)),
      ),
      StreamBuilder<RepeatMode>(
        stream: _repeatModes,
        initialData: widget.engine.state.repeatMode,
        builder: (_, snapshot) => _choice(
          title: 'Режим повтора',
          current: snapshot.data!,
          options: RepeatMode.values,
          label: (mode) => switch (mode) {
            RepeatMode.off => 'Выкл.',
            RepeatMode.all => 'Очередь',
            RepeatMode.one => 'Трек',
          },
          onChanged: _setRepeat,
        ),
      ),
    ],
    _Section.general => [
      SwitchListTile(
        key: const Key('settings-reduced-motion'),
        title: const Text('Уменьшить анимации'),
        value: value.reduceMotion,
        onChanged: _busy
            ? null
            : (reduced) =>
                  settings.update(value.copyWith(reduceMotion: reduced)),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _busy ? null : _reset,
          child: const Text('Сбросить все настройки'),
        ),
      ),
    ],
  };

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    insetAnimationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 100),
    child: SizedBox(
      width: 620,
      height: 530,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final error = settings.error ?? _playerError;
          return PopScope(
            canPop: !_busy,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Настройки',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть настройки',
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final section in _Section.values)
                        if (section != _Section.navigation ||
                            settings.value.style == MusaniTheme.atmosphere)
                          ChoiceChip(
                            label: Text(section.label),
                            selected: section == _section,
                            chipAnimationStyle: reducedChipStyle(context),
                            onSelected: (_) =>
                                setState(() => _section = section),
                          ),
                    ],
                  ),
                  const Divider(height: 16),
                  if (error != null)
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      key: PageStorageKey(_section),
                      children: _options(settings.value),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _CaptureShortcut extends StatefulWidget {
  const _CaptureShortcut({required this.action, required this.settings});
  final PlayerShortcut action;
  final SettingsController settings;

  @override
  State<_CaptureShortcut> createState() => _CaptureShortcutState();
}

class _CaptureShortcutState extends State<_CaptureShortcut> {
  String? _error;

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.synthesized)
      return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab)
      return KeyEventResult.ignored;
    final chord = KeyChord.fromEvent(event);
    if (!chord.isAssignable) return KeyEventResult.ignored;
    final error = widget.settings.shortcutError(widget.action, chord);
    if (error != null) {
      setState(() => _error = error);
    } else {
      Navigator.pop(context, chord);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _key,
    child: AlertDialog(
      title: Text(widget.action.label),
      content: Text(_error ?? 'Нажмите новое сочетание клавиш. Esc — отмена.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}
