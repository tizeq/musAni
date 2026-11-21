import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:media_kit/media_kit.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/library/models.dart';
import 'package:musani/playback/media_kit_engine.dart';
import 'package:musani/playback/playback_engine.dart';
import 'package:musani/settings/settings_controller.dart';
import 'package:musani/ui/musani_app.dart';
import 'package:musani/ui/aurora_scene.dart';

import '../test/support/audio_fixtures.dart';
import '../test/support/memory_repeat_mode_store.dart';
import '../test/design_system_test.dart' show MemorySettingsStore;
import 'library_test.dart' show pumpUntil;

// Deterministic artwork for synthetic preview fixtures, never user files.
Future<void> _cover(Directory directory, int index) async {
  await directory.create(recursive: true);
  const colors = [
    Color(0xffc66b46),
    Color(0xff788b92),
    Color(0xff6c6984),
    Color(0xffb49a60),
    Color(0xff68817a),
    Color(0xffa86e7d),
  ];
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final color = colors[index];
  canvas.drawRect(const Rect.fromLTWH(0, 0, 512, 512), Paint()..color = color);
  canvas.save();
  canvas.translate(256, 256);
  canvas.rotate(index * math.pi / 12);
  for (var i = 0; i < 12; i++) {
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(60, 0),
        width: 100 + i * 34,
        height: 100 + i * 38,
      ),
      Paint()
        ..color = const Color(0xfff3e5cf).withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
  canvas.drawCircle(
    const Offset(-130, -130),
    66,
    Paint()..color = const Color(0xff292b36).withValues(alpha: .8),
  );
  canvas.restore();
  final picture = recorder.endRecording();
  final image = await picture.toImage(512, 512);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('${directory.path}/cover.png')
      .writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'preview both themes and keep navigation reachable in the default window',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      MediaKit.ensureInitialized();
      final dir = await Directory.systemTemp.createTemp(
        'musani-design-preview-',
      );
      const titles = [
        'Тихие орбиты',
        'Береговой свет',
        'После дождя',
        'Линии времени',
        'Сады эфира',
        'Тёплый воздух',
      ];
      const artists = [
        'Лунный атлас',
        'Полюса',
        'Маяк',
        'Касание',
        'Северный сад',
        'Тихий ход',
      ];
      final music = Directory('${dir.path}/music');
      for (var i = 0; i < titles.length; i++) {
        final album = Directory('${music.path}/$i');
        await _cover(album, i);
        await createAudioFixture(
          album,
          'flac',
          title: i == 0 ? 'Медленный спутник' : titles[i],
          album: titles[i],
          artist: artists[i],
          albumArtist: artists[i],
        );
      }
      final repo = LibraryRepository('${dir.path}/catalog');
      await repo.scan(addRoot: music.path);
      final tracks = (await repo.query(
        const LibraryQuery(view: LibraryView.tracks),
      )).tracks;
      final engine = MediaKitEngine(
        Player(),
        repeatModeStore: MemoryRepeatModeStore(),
      );
      await engine.setRepeatMode(RepeatMode.one);
      await engine.open(
        tracks.map((track) => track.playable).toList(),
        index: tracks.indexWhere(
          (track) => track.metadata.title == 'Медленный спутник',
        ),
      );
      final controller = LibraryController(repo);
      final appearance = SettingsController(MemorySettingsStore());
      const boundary = Key('design-preview');
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MusaniApp(
              engine: engine,
              library: controller,
              settings: appearance,
            ),
          ),
        );
        await pumpUntil(
          tester,
          () =>
              controller.initialized &&
              !controller.loading &&
              engine.state.playing,
        );
        await engine.toggle();
        await pumpUntil(tester, () => !engine.state.playing);
        final output = Directory('/tmp/musani-design');
        await output.create(recursive: true);
        for (final (theme, colors, name) in [
          (MusaniTheme.minimal, ColorMode.light, 'minimal'),
          (MusaniTheme.atmosphere, ColorMode.dark, 'atmosphere'),
          (MusaniTheme.atmosphere, ColorMode.light, 'atmosphere-light'),
        ]) {
          await appearance.update(AppSettings(style: theme, colors: colors));
          await tester.pumpAndSettle();
          // Wait for local artwork decode before recording the real Flutter UI.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          final render = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundary),
          );
          final image = await render.toImage();
          if (theme == MusaniTheme.atmosphere) {
            expect(find.byType(AuroraBackdrop), findsOneWidget);
            expect(
              find.byKey(const Key('aurora-window-header')),
              findsOneWidget,
            );
            expect(find.text('Ваша музыка'), findsNothing);
            expect(
              tester.getRect(find.byKey(const Key('player-content'))).bottom,
              lessThan(
                tester.getRect(find.byKey(const Key('playback-dock'))).top,
              ),
            );
          }
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
          expect(tester.takeException(), isNull);
        }
        await tester.binding.setSurfaceSize(const Size(960, 640));
        await tester.pumpAndSettle();
        final song = engine.state.queue[engine.state.index];
        final shuffle = find.byKey(const Key('dock-shuffle'));
        await tester.tap(shuffle);
        await pumpUntil(tester, () => engine.state.shuffle);
        await tester.pumpAndSettle();
        expect(engine.state.queue[engine.state.index], same(song));
        await tester.tap(shuffle);
        await pumpUntil(tester, () => !engine.state.shuffle);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Открыть очередь'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Действия трека очереди'), findsWidgets);
        await tester.tap(find.byTooltip('Вернуться в библиотеку'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Плейлисты'));
        await tester.tap(find.text('Плейлисты'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(engine.state.queue.length, tracks.length);
        await tester.binding.setSurfaceSize(const Size(320, 600));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Громкость'));
        await tester.pumpAndSettle();
        final oldVolume = engine.state.volume;
        await tester.drag(find.byType(Slider).last, const Offset(-40, 0));
        await tester.pumpAndSettle();
        expect(engine.state.volume, lessThan(oldVolume));
        expect(
          tester.widget<Slider>(find.byType(Slider).last).value,
          closeTo(engine.state.volume, .1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        appearance.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await dir.delete(recursive: true);
      }
    },
  );
}
