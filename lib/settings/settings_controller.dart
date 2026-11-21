import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shortcuts.dart';

enum MusaniTheme { minimal, atmosphere }

enum ColorMode { system, light, dark }

enum GlassEffects { lite, soft, full }

enum LibrarySection { albums, artists, tracks, playlists }

enum CollectionPanelMode { collection, queue, currentTrack }

typedef CollectionPanelSettings = ({
  bool? open,
  bool compactOpen,
  double? width,
  CollectionPanelMode mode,
});

@immutable
class AppSettings {
  AppSettings({
    this.style = MusaniTheme.minimal,
    this.colors = ColorMode.system,
    this.glassEffects = GlassEffects.soft,
    this.reduceMotion = false,
    this.volumeStep = 5,
    this.collectionPanel = defaultCollectionPanel,
    this.showAlbumsInAtmosphere = false,
    Map<PlayerShortcut, KeyChord> shortcuts = const {},
    Iterable<LibrarySection> libraryOrder = LibrarySection.values,
  }) : libraryOrder = List.unmodifiable({
         ...libraryOrder,
         ...LibrarySection.values,
       }),
       shortcuts = Map.unmodifiable({
         for (final action in PlayerShortcut.values)
           action: shortcuts[action] ?? action.defaultChord,
       });

  static const volumeSteps = [1, 5, 10, 15, 20];
  static const CollectionPanelSettings defaultCollectionPanel = (
    open: null,
    compactOpen: false,
    width: null,
    mode: CollectionPanelMode.collection,
  );
  final MusaniTheme style;
  final ColorMode colors;
  final GlassEffects glassEffects;
  final bool reduceMotion;
  final int volumeStep;
  final Map<PlayerShortcut, KeyChord> shortcuts;
  final List<LibrarySection> libraryOrder;
  final bool showAlbumsInAtmosphere;
  final CollectionPanelSettings collectionPanel;

  AppSettings copyWith({
    MusaniTheme? style,
    ColorMode? colors,
    GlassEffects? glassEffects,
    bool? reduceMotion,
    int? volumeStep,
    Map<PlayerShortcut, KeyChord>? shortcuts,
    Iterable<LibrarySection>? libraryOrder,
    bool? showAlbumsInAtmosphere,
    CollectionPanelSettings? collectionPanel,
  }) => AppSettings(
    style: style ?? this.style,
    colors: colors ?? this.colors,
    glassEffects: glassEffects ?? this.glassEffects,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    volumeStep: volumeStep ?? this.volumeStep,
    shortcuts: shortcuts ?? this.shortcuts,
    libraryOrder: libraryOrder ?? this.libraryOrder,
    showAlbumsInAtmosphere:
        showAlbumsInAtmosphere ?? this.showAlbumsInAtmosphere,
    collectionPanel: collectionPanel ?? this.collectionPanel,
  );

  PlayerShortcut? actionFor(KeyChord chord) =>
      shortcuts.keys.where((action) => shortcuts[action] == chord).firstOrNull;

  factory AppSettings.decode(String encoded) {
    final json = jsonDecode(encoded);
    if (json is! Map<String, dynamic>)
      throw const FormatException('Invalid settings');
    final stored = json['shortcuts'];
    final shortcuts = {
      for (final action in PlayerShortcut.values)
        action:
            KeyChord.decode(stored is Map ? stored[action.name] : null) ??
            action.defaultChord,
    };
    final step = json['volumeStep'];
    final order = json['libraryOrder'];
    final sectionsByName = LibrarySection.values.asNameMap();
    final panel = json['collectionPanel'];
    final panelOpen = panel is Map ? panel['open'] : null;
    final compactOpen = panel is Map && panel['compactOpen'] == true;
    final panelWidth = panel is Map ? panel['width'] : null;
    final panelMode = panel is Map ? panel['mode'] : null;
    return AppSettings(
      style:
          MusaniTheme.values
              .where((mode) => mode.name == json['style'])
              .firstOrNull ??
          MusaniTheme.minimal,
      colors:
          ColorMode.values
              .where((mode) => mode.name == json['colors'])
              .firstOrNull ??
          ColorMode.system,
      reduceMotion: json['reduceMotion'] == true,
      glassEffects:
          GlassEffects.values.asNameMap()[json['glassEffects']] ??
          GlassEffects.soft,
      volumeStep: step is int && volumeSteps.contains(step) ? step : 5,
      collectionPanel: (
        open: panelOpen is bool ? panelOpen : null,
        compactOpen: compactOpen,
        width: panelWidth is num && panelWidth.isFinite && panelWidth > 0
            ? panelWidth.toDouble()
            : null,
        mode:
            CollectionPanelMode.values.asNameMap()[panelMode] ??
            CollectionPanelMode.collection,
      ),
      shortcuts: shortcuts.values.toSet().length == shortcuts.length
          ? shortcuts
          : const {},
      libraryOrder: order is List
          ? order.map((name) => sectionsByName[name]).nonNulls
          : LibrarySection.values,
      showAlbumsInAtmosphere: json['showAlbumsInAtmosphere'] == true,
    );
  }

  String encode() => jsonEncode({
    'style': style.name,
    'colors': colors.name,
    'glassEffects': glassEffects.name,
    'reduceMotion': reduceMotion,
    'volumeStep': volumeStep,
    'libraryOrder': libraryOrder.map((section) => section.name).toList(),
    'showAlbumsInAtmosphere': showAlbumsInAtmosphere,
    'collectionPanel': {
      'open': collectionPanel.open,
      'compactOpen': collectionPanel.compactOpen,
      'width': collectionPanel.width,
      'mode': collectionPanel.mode.name,
    },
    'shortcuts': shortcuts.map(
      (action, chord) => MapEntry(action.name, chord.toJson()),
    ),
  });
}

abstract interface class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class PreferencesSettingsStore implements SettingsStore {
  PreferencesSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  static const _key = 'settings.v1';

  @override
  Future<AppSettings> load() async {
    final encoded = await _preferences.getString(_key);
    if (encoded != null) return AppSettings.decode(encoded);
    final legacyTheme = await _preferences.getString('appearance.theme');
    final legacyMotion = await _preferences.getBool('appearance.reduceMotion');
    final atmosphere = legacyTheme == 'atmosphere';
    return AppSettings(
      style: atmosphere ? MusaniTheme.atmosphere : MusaniTheme.minimal,
      colors: atmosphere
          ? ColorMode.dark
          : legacyTheme != null || legacyMotion != null
          ? ColorMode.light
          : ColorMode.system,
      reduceMotion: legacyMotion ?? false,
    );
  }

  @override
  Future<void> save(AppSettings settings) =>
      _preferences.setString(_key, settings.encode());
}

class SettingsController extends ChangeNotifier {
  SettingsController(this.store, {AppSettings? initial})
    : _value = initial ?? AppSettings();
  final SettingsStore store;
  AppSettings _value;
  AppSettings get value => _value;
  bool saving = false;
  Completer<void>? _saved;
  String? error;

  Future<void> restore() async {
    try {
      _value = await store.load();
    } catch (_) {
      error = 'Не удалось прочитать настройки';
    }
    notifyListeners();
  }

  String? shortcutError(PlayerShortcut action, KeyChord chord) {
    if (!chord.isAssignable)
      return 'Это сочетание зарезервировано для навигации и ввода.';
    final conflict = value.actionFor(chord);
    if (conflict != null && conflict != action) {
      return 'Сочетание уже назначено действию «${conflict.label}».';
    }
    return null;
  }

  Future<bool> assign(PlayerShortcut action, KeyChord chord) async {
    if (shortcutError(action, chord) != null) return false;
    return update(
      value.copyWith(shortcuts: {...value.shortcuts, action: chord}),
    );
  }

  Future<bool> update(AppSettings settings) => _write(settings, notify: true);

  Future<bool> _write(AppSettings settings, {required bool notify}) async {
    if (saving) return false;
    final previous = value;
    saving = true;
    final saved = _saved = Completer<void>();
    error = null;
    _value = settings;
    if (notify) notifyListeners();
    try {
      await store.save(settings);
      return true;
    } catch (_) {
      _value = previous;
      error = 'Не удалось сохранить настройки. Попробуйте ещё раз.';
      return false;
    } finally {
      saving = false;
      _saved = null;
      saved.complete();
      if (notify) notifyListeners();
    }
  }

  Future<bool> updateCollectionPanel(CollectionPanelSettings panel) async {
    while (_saved != null) {
      await _saved!.future;
    }
    return panel == value.collectionPanel ||
        await _write(value.copyWith(collectionPanel: panel), notify: false);
  }
}
