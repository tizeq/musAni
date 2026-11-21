import 'package:flutter/services.dart';

enum PlayerShortcut {
  playPause('Пауза / воспроизведение', KeyChord(LogicalKeyboardKey.space)),
  previous(
    'Предыдущий трек',
    KeyChord(LogicalKeyboardKey.arrowLeft, ctrl: true),
  ),
  next('Следующий трек', KeyChord(LogicalKeyboardKey.arrowRight, ctrl: true)),
  volumeUp('Громче', KeyChord(LogicalKeyboardKey.arrowUp, ctrl: true)),
  volumeDown('Тише', KeyChord(LogicalKeyboardKey.arrowDown, ctrl: true)),
  search('Поиск в библиотеке', KeyChord(LogicalKeyboardKey.keyF, ctrl: true)),
  settings('Открыть настройки', KeyChord(LogicalKeyboardKey.comma, ctrl: true)),
  mute('Выключить / включить звук', KeyChord(LogicalKeyboardKey.keyM));

  const PlayerShortcut(this.label, this.defaultChord);
  final String label;
  final KeyChord defaultChord;

  bool get repeats => this == volumeUp || this == volumeDown;
}

class KeyChord {
  const KeyChord(
    this.key, {
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });
  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;

  static final _reserved = {
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.altGraph,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.numLock,
    LogicalKeyboardKey.scrollLock,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.tab,
  };

  factory KeyChord.fromEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    return KeyChord(
      event.logicalKey,
      ctrl: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
      meta: keyboard.isMetaPressed,
    );
  }

  bool get isAssignable =>
      !_reserved.contains(key) &&
      (key != LogicalKeyboardKey.enter &&
              key != LogicalKeyboardKey.numpadEnter ||
          ctrl ||
          alt ||
          shift ||
          meta) &&
      key != LogicalKeyboardKey.unidentified;

  String get label => [
    if (ctrl) 'Ctrl',
    if (alt) 'Alt',
    if (shift) 'Shift',
    if (meta) 'Super',
    switch (key) {
      LogicalKeyboardKey.space => 'Space',
      LogicalKeyboardKey.arrowLeft => '←',
      LogicalKeyboardKey.arrowRight => '→',
      LogicalKeyboardKey.arrowUp => '↑',
      LogicalKeyboardKey.arrowDown => '↓',
      _ =>
        key.keyLabel.isEmpty ? key.debugName ?? '${key.keyId}' : key.keyLabel,
    },
  ].join('+');

  List<Object> toJson() => [key.keyId, ctrl, alt, shift, meta];

  static KeyChord? decode(Object? value) {
    if (value case [
      final int id,
      final bool ctrl,
      final bool alt,
      final bool shift,
      final bool meta,
    ]) {
      if (id <= 0 || id > 0x1fffffffff) return null;
      final chord = KeyChord(
        LogicalKeyboardKey.findKeyByKeyId(id) ?? LogicalKeyboardKey(id),
        ctrl: ctrl,
        alt: alt,
        shift: shift,
        meta: meta,
      );
      return chord.isAssignable ? chord : null;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is KeyChord &&
      key == other.key &&
      ctrl == other.ctrl &&
      alt == other.alt &&
      shift == other.shift &&
      meta == other.meta;

  @override
  int get hashCode => Object.hash(key, ctrl, alt, shift, meta);
}
