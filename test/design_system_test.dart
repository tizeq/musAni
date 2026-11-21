import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/models.dart';
import 'package:musani/settings/settings_controller.dart';
import 'package:musani/settings/shortcuts.dart';
import 'package:musani/ui/album_page.dart';
import 'package:musani/ui/aurora_scene.dart';
import 'package:musani/ui/design_system.dart';
import 'package:musani/ui/musani_app.dart';
import 'package:shared_preferences_linux/shared_preferences_linux.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'player_page_test.dart' show FakeEngine;
import 'repeat_mode_store_linux_test.dart' show TemporaryPathProvider;
import 'support/library_fakes.dart';

class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([AppSettings? initial])
    : value = initial ?? AppSettings();
  AppSettings value;
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    await gate?.future;
    if (fail) throw StateError('Disk unavailable');
    value = settings;
  }
}

void main() {
  test('all style and color combinations keep body text readable', () {
    for (final mode in MusaniTheme.values) {
      for (final brightness in Brightness.values) {
        final colors = MusaniDesign.theme(mode, brightness).colorScheme;
        for (final foreground in [colors.onSurface, colors.onSurfaceVariant]) {
          for (final background in [
            colors.surface,
            colors.surfaceContainerLow,
          ]) {
            final a = foreground.computeLuminance();
            final b = background.computeLuminance();
            final contrast = a > b
                ? (a + .05) / (b + .05)
                : (b + .05) / (a + .05);
            expect(
              contrast,
              greaterThanOrEqualTo(4.5),
              reason: '$mode body text',
            );
          }
        }
      }
    }
  });
  test('legacy settings migrate and new choices survive reopening the Linux backend', () async {
    final dir = await Directory.systemTemp.createTemp('musani-theme-');
    final original = SharedPreferencesAsyncPlatform.instance;
    void backend() =>
        SharedPreferencesAsyncPlatform.instance = SharedPreferencesAsyncLinux()
          ..pathProvider = TemporaryPathProvider(dir.path);
    try {
      backend();
      final legacy = SharedPreferencesAsync();
      await legacy.setString('appearance.theme', 'atmosphere');
      await legacy.setBool('appearance.reduceMotion', true);
      backend();
      final store = PreferencesSettingsStore();
      final migrated = await store.load();
      expect(migrated.style, MusaniTheme.atmosphere);
      expect(migrated.colors, ColorMode.dark);
      expect(migrated.reduceMotion, isTrue);
      expect(migrated.glassEffects, GlassEffects.soft);
      expect(migrated.showAlbumsInAtmosphere, isFalse);
      expect(
        AppSettings.decode('{"glassEffects":"full"}').glassEffects,
        GlassEffects.full,
      );
      expect(migrated.libraryOrder, LibrarySection.values);
      final controller = SettingsController(store, initial: migrated);
      await controller.update(
        migrated.copyWith(
          style: MusaniTheme.minimal,
          volumeStep: 15,
          glassEffects: GlassEffects.lite,
          libraryOrder: [LibrarySection.tracks, LibrarySection.albums],
          showAlbumsInAtmosphere: true,
        ),
      );
      const chord = KeyChord(LogicalKeyboardKey.keyP, alt: true);
      expect(await controller.assign(PlayerShortcut.playPause, chord), isTrue);
      const panel = (
        open: false,
        compactOpen: true,
        width: 485.0,
        mode: CollectionPanelMode.currentTrack,
      );
      expect(await controller.updateCollectionPanel(panel), isTrue);
      backend();
      final saved = await PreferencesSettingsStore().load();
      expect(saved.style, MusaniTheme.minimal);
      expect(saved.colors, ColorMode.dark);
      expect(saved.reduceMotion, isTrue);
      expect(saved.volumeStep, 15);
      expect(saved.glassEffects, GlassEffects.lite);
      expect(saved.showAlbumsInAtmosphere, isTrue);
      expect(saved.libraryOrder, [
        LibrarySection.tracks,
        LibrarySection.albums,
        LibrarySection.artists,
        LibrarySection.playlists,
      ]);
      expect(saved.shortcuts[PlayerShortcut.playPause], chord);
      expect(saved.collectionPanel, panel);
      controller.dispose();
    } finally {
      SharedPreferencesAsyncPlatform.instance = original;
      await dir.delete(recursive: true);
    }
  });

  testWidgets(
    'motion setting preserves the open album tab and reduces theme transitions',
    (tester) async {
      final tracks = sampleLibraryTracks('/tmp');
      final library = LibraryController(FakeLibraryRepository(tracks));
      final appearance = SettingsController(MemorySettingsStore());
      await tester.pumpWidget(
        MusaniApp(engine: FakeEngine(), library: library, settings: appearance),
      );
      await tester.pumpAndSettle();
      final catalogRoute = ModalRoute.of(
        tester.element(find.byKey(const Key('library-search'))),
      );
      await tester.tap(find.text('Север'));
      await tester.pumpAndSettle();
      final album = tester.state(find.byType(AlbumPage));
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Общие'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Уменьшить анимации'));
      await tester.pumpAndSettle();
      expect(appearance.value.reduceMotion, isTrue);
      await tester.tap(find.byTooltip('Закрыть настройки'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .themeAnimationDuration,
        Duration.zero,
      );
      expect(
        ModalRoute.of(tester.element(find.byType(AlbumPage))),
        same(catalogRoute),
      );
      expect(tester.state(find.byType(AlbumPage)), same(album));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tab-album-album')));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AlbumPage)), same(album));
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
    },
  );

  test(
    'failed save rolls back theme, reports error and permits retry',
    () async {
      final store = MemorySettingsStore()..fail = true;
      final controller = SettingsController(store);
      await controller.update(
        controller.value.copyWith(style: MusaniTheme.atmosphere),
      );
      expect(controller.value.style, MusaniTheme.minimal);
      expect(controller.saving, isFalse);
      expect(controller.error, isNotNull);
      store.fail = false;
      await controller.update(
        controller.value.copyWith(style: MusaniTheme.atmosphere),
      );
      expect(controller.value.style, MusaniTheme.atmosphere);
      expect(controller.error, isNull);
      controller.dispose();
    },
  );

  testWidgets(
    'theme menu changes palette without resetting queue, navigation or playback',
    (tester) async {
      final tracks = sampleLibraryTracks('/tmp');
      final engine = FakeEngine(
        queue: tracks.map((track) => track.playable).toList(),
      );
      final controller = LibraryController(FakeLibraryRepository(tracks));
      final appearance = SettingsController(MemorySettingsStore());
      await tester.pumpWidget(
        MusaniApp(engine: engine, library: controller, settings: appearance),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Треки'));
      await tester.pumpAndSettle();
      final queue = engine.state.queue;
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Цветовая схема'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<ColorMode>, 'Dark'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Закрыть настройки'));
      await tester.pumpAndSettle();
      expect(appearance.value.style, MusaniTheme.minimal);
      expect(appearance.value.colors, ColorMode.dark);
      expect(
        Theme.of(tester.element(find.byKey(const Key('library-search'))))
            .brightness,
        Brightness.dark,
      );
      expect(find.text('Первый трек'), findsNWidgets(2));
      expect(engine.state.queue, same(queue));
      expect(engine.opens, 0);
      expect(engine.controller.isClosed, isFalse);
      expect(find.byKey(const Key('now-playing-artwork')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
    },
  );

  testWidgets(
    'Atmosphere uses a static highlight for focused search at every effect level',
    (tester) async {
      final tracks = sampleLibraryTracks('/tmp');
      final settings = SettingsController(
        MemorySettingsStore(),
        initial: AppSettings(
          style: MusaniTheme.atmosphere,
          glassEffects: GlassEffects.full,
        ),
      );
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MusaniApp(
          engine: FakeEngine(),
          library: LibraryController(FakeLibraryRepository(tracks)),
          settings: settings,
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('library-search'));
      final blur = find.byType(BackdropFilter);
      final surface = find.ancestor(
        of: search,
        matching: find.byType(AuroraSurface),
      );
      expect(blur, findsNothing);
      final before = tester.widget<AuroraSurface>(surface).highlight;

      await tester.tap(search);
      await tester.pump();
      expect(blur, findsNothing);
      expect(
        tester.widget<AuroraSurface>(surface).highlight,
        greaterThan(before),
      );

      await settings.update(
        settings.value.copyWith(glassEffects: GlassEffects.lite),
      );
      await tester.pumpAndSettle();
      expect(blur, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Atmosphere hides Albums by default, keeps its slot and reorders via mouse or keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1586, 992);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final initial = AppSettings(
        style: MusaniTheme.atmosphere,
        reduceMotion: true,
      );
      final store = MemorySettingsStore(initial);
      final settings = SettingsController(store, initial: initial);
      addTearDown(settings.dispose);
      final library = LibraryController(
        FakeLibraryRepository(sampleLibraryTracks('/tmp')),
      );
      await tester.pumpWidget(
        MusaniApp(engine: FakeEngine(), library: library, settings: settings),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byKey(const Key('library-navigation'));
      Finder label(String name) =>
          find.descendant(of: sidebar, matching: find.text(name));
      expect(library.query.view, LibraryView.tracks);
      expect(label('Альбомы'), findsNothing);
      await tester.tap(find.text('Все альбомы'));
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      expect(label('Альбомы'), findsNothing);
      await tester.tap(label('Треки'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: sidebar,
          matching: find.byIcon(Icons.drag_indicator),
        ),
        findsNothing,
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(label('Артисты')));
      await tester.pump();
      final handle = find.byKey(const Key('library-drag-artists'));
      expect(handle, findsOneWidget);
      final start = tester.getCenter(handle);
      await mouse.moveTo(start);
      await mouse.down(start);
      await mouse.moveBy(const Offset(0, 124));
      await tester.pump(const Duration(milliseconds: 300));
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(store.value.libraryOrder, [
        LibrarySection.albums,
        LibrarySection.tracks,
        LibrarySection.playlists,
        LibrarySection.artists,
      ]);
      expect(handle, findsNothing);

      Focus.of(tester.element(label('Артисты'))).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(store.value.libraryOrder, [
        LibrarySection.albums,
        LibrarySection.tracks,
        LibrarySection.artists,
        LibrarySection.playlists,
      ]);

      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Навигация'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-show-albums')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Закрыть настройки'));
      await tester.pumpAndSettle();
      expect(store.value.showAlbumsInAtmosphere, isTrue);
      expect(
        tester.getTopLeft(label('Альбомы')).dy,
        lessThan(tester.getTopLeft(label('Треки')).dy),
      );
      await tester.tap(label('Альбомы'));
      await tester.pumpAndSettle();
      expect(library.query.view, LibraryView.albums);
      expect(find.byType(GridView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'collection width, mode and expanded state survive compact windows',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1586, 992);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final title = 'Длинное название композиции ' * 12;
      final artist = 'Исполнитель с длинным именем ' * 12;
      final tracks = [
        LibraryTrack(
          id: 7,
          path: '/music/long.flac',
          albumId: 'album',
          metadata: TrackMetadata(
            title: title,
            artists: [artist],
            album: 'Север',
            albumArtist: artist,
          ),
          size: 0,
          modifiedUs: 0,
          changedUs: 0,
        ),
      ];
      final initial = AppSettings(
        style: MusaniTheme.atmosphere,
        showAlbumsInAtmosphere: true,
        reduceMotion: true,
        colors: ColorMode.dark,
      );
      final store = MemorySettingsStore(initial);
      final settings = SettingsController(store, initial: initial);
      final repository = FakeLibraryRepository(tracks);
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MusaniApp(
          engine: FakeEngine(queue: [tracks.single.playable]),
          library: LibraryController(repository),
          settings: settings,
        ),
      );
      await tester.pumpAndSettle();

      final panel = find.byKey(const Key('aurora-collection'));
      final grip = find.byKey(const Key('collection-resize-handle'));
      final header = find.byTooltip('Коллекция и очередь');
      final catalog = find.byType(GridView);
      expect(find.text('Север'), findsOneWidget);
      expect(panel, findsOneWidget);
      final navigation = find.byKey(const Key('library-navigation'));
      for (final label in ['Артисты', 'Альбомы', 'Артисты', 'Альбомы']) {
        await tester.tap(
          find.descendant(of: navigation, matching: find.text(label)),
        );
        await tester.pumpAndSettle();
      }
      expect(
        repository.queries.where((query) => query.limit == 4),
        hasLength(1),
      );
      final start = tester.getSize(panel).width;
      final drag = await tester.startGesture(tester.getCenter(grip));
      await drag.moveBy(const Offset(30, 0));
      await drag.moveBy(const Offset(110, 0));
      await tester.pump();
      final resized = tester.getSize(panel).width;
      expect(resized, lessThan(start));
      expect(store.value.collectionPanel.width, isNull);
      await drag.up();
      await tester.pumpAndSettle();
      expect(store.value.collectionPanel.width, resized);

      await tester.tap(find.byKey(const Key('collection-mode-currentTrack')));
      await tester.pumpAndSettle();
      final currentTitle = tester.widget<Text>(
        find.byKey(const Key('panel-track-title')),
      );
      expect(currentTitle.data, title);
      expect(currentTitle.overflow, TextOverflow.ellipsis);
      expect(
        store.value.collectionPanel.mode,
        CollectionPanelMode.currentTrack,
      );

      for (final size in [const Size(1200, 800), const Size(960, 640)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        final catalogBounds = tester.getRect(catalog);
        await tester.tap(header);
        await tester.pump();
        expect(panel, findsOneWidget);
        expect(grip, findsNothing);
        expect(tester.getRect(catalog), catalogBounds);
        final drawerBounds = tester.getRect(panel);
        expect(drawerBounds.right, catalogBounds.right);
        expect(drawerBounds.width, lessThan(catalogBounds.width));
        expect(
          tester.getRect(find.byKey(const Key('playback-dock'))).top,
          greaterThanOrEqualTo(drawerBounds.bottom),
        );
        expect(tester.takeException(), isNull);
        if (size.width == 1200) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tapAt(
            Offset(catalogBounds.left + 16, catalogBounds.center.dy),
          );
        }
        await tester.pump();
        expect(panel, findsNothing);
        expect(tester.getRect(catalog), catalogBounds);
        expect(store.value.collectionPanel.width, resized);
        expect(store.value.collectionPanel.open, isNull);
      }

      tester.view.physicalSize = const Size(1586, 992);
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, resized);
      final widthWithPanel = tester.getSize(catalog).width;
      await tester.tap(find.byTooltip('Закрыть панель коллекции'));
      await tester.pump();
      expect(panel, findsNothing);
      expect(tester.getSize(catalog).width, greaterThan(widthWithPanel));
      expect(store.value.collectionPanel.open, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final theme in MusaniTheme.values) {
    for (final size in [
      const Size(320, 600),
      const Size(960, 640),
      const Size(900, 400),
      const Size(1200, 900),
    ]) {
      testWidgets(
        '$theme fits $size with a playing queue and reachable navigation',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final tracks = sampleLibraryTracks('/tmp');
          final engine = FakeEngine(
            queue: tracks.map((track) => track.playable).toList(),
          );
          final controller = LibraryController(FakeLibraryRepository(tracks));
          final appearance = SettingsController(
            MemorySettingsStore(),
            initial: AppSettings(
              style: theme,
              colors: theme == MusaniTheme.atmosphere
                  ? ColorMode.dark
                  : ColorMode.light,
            ),
          );
          await tester.pumpWidget(
            MusaniApp(
              engine: engine,
              library: controller,
              settings: appearance,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Треки'));
          await tester.tap(find.text('Треки'));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('track-menu-1')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          appearance.dispose();
        },
      );
    }
  }
}
