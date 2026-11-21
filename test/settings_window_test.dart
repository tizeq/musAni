import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:musani/library/library_controller.dart';
import 'package:musani/playback/playback_engine.dart';
import 'package:musani/settings/settings_controller.dart';
import 'package:musani/settings/shortcuts.dart';
import 'package:musani/ui/album_page.dart';
import 'package:musani/ui/musani_app.dart';
import 'package:musani/ui/settings_window.dart';

import 'design_system_test.dart' show MemorySettingsStore;
import 'player_page_test.dart' show FakeEngine;
import 'support/library_fakes.dart';

Future<void> _ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  late SettingsController settings;
  late FakeEngine engine;
  Future<void> start(WidgetTester tester, {AppSettings? initial}) async {
    final tracks = sampleLibraryTracks('/tmp');
    settings = SettingsController(
      MemorySettingsStore(initial),
      initial: initial,
    );
    engine = FakeEngine(queue: tracks.map((track) => track.playable).toList());
    await tester.pumpWidget(
      MusaniApp(
        engine: engine,
        library: LibraryController(FakeLibraryRepository(tracks)),
        settings: settings,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  }

  testWidgets('settings sections remain reachable in a small window', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await start(tester);
    expect(tester.takeException(), isNull, reason: 'before opening settings');
    await _ctrl(tester, LogicalKeyboardKey.comma);
    for (final section in ['Горячие клавиши', 'Плеер', 'Общие', 'Оформление']) {
      await tester.tap(find.text(section));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await stop(tester);
  });

  testWidgets(
    'default shortcuts control playback, respect text fields and reach library search',
    (tester) async {
      await start(tester, initial: AppSettings(volumeStep: 10));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(engine.playing, isFalse);
      await _ctrl(tester, LogicalKeyboardKey.arrowRight);
      expect(engine.index, 1);
      await _ctrl(tester, LogicalKeyboardKey.arrowLeft);
      expect(engine.index, 0);
      await _ctrl(tester, LogicalKeyboardKey.arrowLeft);
      expect(engine.jumps, [1, 0]);
      await _ctrl(tester, LogicalKeyboardKey.arrowUp);
      expect(engine.volume, 90);
      await _ctrl(tester, LogicalKeyboardKey.arrowDown);
      expect(engine.volume, 80);
      for (final volume in [0, 80]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
        await tester.pumpAndSettle();
        expect(engine.volume, volume);
      }

      await tester.tap(find.text('Север'));
      await tester.pumpAndSettle();
      expect(find.byType(AlbumPage), findsOneWidget);
      await _ctrl(tester, LogicalKeyboardKey.keyF);
      expect(find.byType(AlbumPage), findsNothing);
      final search = find.byType(EditableText);
      expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);
      final playing = engine.playing;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await _ctrl(tester, LogicalKeyboardKey.arrowRight);
      expect(engine.playing, playing);
      expect(engine.index, 0);
      expect(engine.volume, 80);
      await tester.enterText(search, 'rock mix');
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(search).controller.text, 'rock mix');

      await tester.tap(find.byTooltip('Очередь воспроизведения'));
      await tester.pumpAndSettle();
      await _ctrl(tester, LogicalKeyboardKey.keyF);
      expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);
      expect(tester.widget<EditableText>(search).controller.text, 'rock mix');
      await stop(tester);
    },
  );

  testWidgets(
    'capture rejects conflicts, applies a new shortcut and resets it',
    (tester) async {
      await start(tester);
      await _ctrl(tester, LogicalKeyboardKey.comma);
      expect(find.byType(SettingsWindow), findsOneWidget);
      await tester.tap(find.text('Горячие клавиши'));
      await tester.pumpAndSettle();
      final change = find.byKey(const ValueKey('shortcut-playPause'));
      await tester.tap(change);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(find.textContaining('уже назначено'), findsOneWidget);
      expect(engine.volume, 80);
      expect(
        settings.value.shortcuts[PlayerShortcut.playPause],
        PlayerShortcut.playPause.defaultChord,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.textContaining('уже назначено'), findsNothing);

      await tester.tap(change);
      await tester.pumpAndSettle();
      await _ctrl(tester, LogicalKeyboardKey.keyP);
      expect(
        settings.value.shortcuts[PlayerShortcut.playPause],
        const KeyChord(LogicalKeyboardKey.keyP, ctrl: true),
      );
      await tester.tap(find.byTooltip('Закрыть настройки'));
      await tester.pumpAndSettle();
      await _ctrl(tester, LogicalKeyboardKey.keyP);
      expect(engine.playing, isFalse);
      await _ctrl(tester, LogicalKeyboardKey.comma);
      await tester.tap(find.text('Горячие клавиши'));
      await tester.pumpAndSettle();
      final reset = find.text('Сбросить горячие клавиши');
      await tester.scrollUntilVisible(
        reset,
        160,
        scrollable: find.descendant(
          of: find.byType(SettingsWindow),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(
        settings.value.shortcuts[PlayerShortcut.playPause],
        PlayerShortcut.playPause.defaultChord,
      );
      await stop(tester);
    },
  );

  testWidgets(
    'System follows platform brightness and reset restores repeat and preferences',
    (tester) async {
      await start(
        tester,
        initial: AppSettings(
          style: MusaniTheme.atmosphere,
          volumeStep: 15,
          reduceMotion: true,
        ),
      );
      Brightness brightness() =>
          Theme.of(tester.element(find.byKey(const Key('library-search'))))
              .brightness;
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      await _ctrl(tester, LogicalKeyboardKey.comma);
      final dialog = ModalRoute.of(
        tester.element(find.byType(SettingsWindow)),
      )!;
      expect(dialog.transitionDuration, Duration.zero);
      await tester.tap(find.text('Плеер'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Режим повтора'));
      await tester.pumpAndSettle();
      final option = find.widgetWithText(
        CheckedPopupMenuItem<RepeatMode>,
        'Трек',
      );
      expect(
        ModalRoute.of(tester.element(option))!.transitionDuration,
        Duration.zero,
      );
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(engine.repeatMode, RepeatMode.one);
      await tester.tap(find.text('Общие'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сбросить все настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сбросить'));
      await tester.pumpAndSettle();
      expect(engine.repeatMode, RepeatMode.off);
      expect(settings.value.encode(), AppSettings().encode());
      await stop(tester);
    },
  );
}
