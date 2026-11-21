import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/library/models.dart';
import 'package:musani/playlists/models.dart';
import 'package:musani/playlists/playlist_repository.dart';
import 'package:musani/settings/settings_controller.dart';
import 'package:musani/ui/aurora_scene.dart';
import 'package:musani/ui/design_system.dart';
import 'package:musani/ui/metadata_editor_dialog.dart';
import 'package:musani/ui/playlist_page.dart';

import '../test/support/audio_fixtures.dart';
import 'library_test.dart' show pumpUntil;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Atmosphere playlist properties retain artwork and ordered entries when changing type',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = await Directory.systemTemp.createTemp(
        'musani-playlist-cover-',
      );
      final rock = await Directory('${dir.path}/music/one')
          .create(recursive: true);
      final jazz = await Directory('${dir.path}/music/two')
          .create(recursive: true);
      final title = 'Длинное название композиции ' * 9;
      final artist = 'Исполнитель с длинным именем ' * 9;
      final custom = '${dir.path}/custom.png';
      for (final (path, color) in [
        ('${rock.path}/cover.png', 'red'),
        ('${jazz.path}/cover.png', 'blue'),
        (custom, 'purple'),
      ]) {
        await ffmpeg([
          '-f',
          'lavfi',
          '-i',
          'color=c=$color:s=512x512',
          '-frames:v',
          '1',
          '-threads',
          '1',
          path,
        ]);
      }
      final first = await createAudioFixture(
        rock,
        'flac',
        title: title,
        artist: artist,
        album: 'Первый альбом',
      );
      final second = await createAudioFixture(
        jazz,
        'flac',
        title: 'Второй трек',
        album: 'Второй альбом',
      );
      final library = LibraryRepository('${dir.path}/catalog');
      await library.scan(addRoot: '${dir.path}/music');
      final tracks = (await library.query(
        const LibraryQuery(view: LibraryView.tracks),
      )).tracks;
      final repo = PlaylistRepository(library.directory);
      final playlist = await repo.create('Длинное название плейлиста ' * 6);
      await repo.add(playlist.id, playlist.revision, [
        for (final file in [first, second])
          PlaylistTrackRef.fromLibrary(
            tracks.singleWhere((track) => track.path == file.path),
          ),
      ]);
      final controller = LibraryController(library);
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: MusaniDesign.theme(
              MusaniTheme.atmosphere,
              Brightness.dark,
              reduceMotion: true,
            ),
            home: PlaylistPage(
              id: playlist.id,
              repository: repo,
              library: controller,
              coverPicker: () async => XFile(custom),
            ),
          ),
        );
        final mosaic = find.byKey(const Key('playlist-cover-mosaic'));
        final customCover = find.byKey(
          Key('playlist-custom-cover-${playlist.id}'),
        );
        await pumpUntil(tester, () => mosaic.evaluate().isNotEmpty);
        expect(find.text(first.path), findsNothing);
        expect(find.text(second.path), findsNothing);
        expect(
          tester.widget<Text>(find.text(title.trim())).overflow,
          TextOverflow.ellipsis,
        );
        expect(
          tester.widget<Text>(find.text(artist.trim())).overflow,
          TextOverflow.ellipsis,
        );
        expect(find.text('0:01'), findsNWidgets(2));
        expect(find.byType(AuroraTrackSurface), findsNWidgets(2));
        await tester.tap(
          find.text('Второй трек'),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Редактировать метаданные'));
        await pumpUntil(
          tester,
          () => find.byKey(const Key('metadata-TITLE')).evaluate().isNotEmpty,
        );
        expect(find.byType(MetadataEditorDialog), findsOneWidget);
        await tester.tap(find.text('Отмена'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Выбрать обложку плейлиста'));
        await pumpUntil(tester, () => customCover.evaluate().isNotEmpty);
        expect((await repo.artwork(playlist.id)).image, isNotEmpty);
        expect(await File(custom).exists(), isTrue);
        expect(mosaic, findsNothing);

        final before = await repo.detail(playlist.id);
        final handle = find.byType(ReorderableDragStartListener);
        await tester.timedDrag(
          handle.first,
          const Offset(0, 110),
          const Duration(milliseconds: 400),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        PlaylistDetail after;
        do {
          await tester.pump(const Duration(milliseconds: 50));
          after = await repo.detail(playlist.id);
        } while (after.playlist.revision == before.playlist.revision &&
            DateTime.now().isBefore(deadline));
        expect(
          after.entries.map((entry) => entry.id),
          before.entries.reversed.map((entry) => entry.id),
        );
        await tester.pumpAndSettle();
        expect(customCover, findsOneWidget);

        Future<void> properties({String? name}) async {
          await tester.tap(find.byTooltip('Действия плейлиста'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Свойства'));
          await tester.pumpAndSettle();
          if (name != null)
            await tester.enterText(
              find.byKey(const Key('playlist-name')),
              name,
            );
          await tester.tap(find.byKey(const Key('playlist-as-album')));
          await tester.tap(find.text('Сохранить'));
        }

        await properties(name: 'Мой концертный альбом');
        final albumBadge = find.text('Пользовательский альбом');
        await pumpUntil(tester, () => albumBadge.evaluate().isNotEmpty);
        await pumpUntil(tester, () => customCover.evaluate().isNotEmpty);
        await tester.pumpAndSettle();
        expect(find.text('Мой концертный альбом'), findsOneWidget);
        expect(find.text('Воспроизвести альбом'), findsOneWidget);
        final converted = await repo.detail(playlist.id);
        expect(converted.playlist.isAlbum, isTrue);
        expect(
          converted.entries.map((e) => e.id),
          after.entries.map((e) => e.id),
        );

        await tester.tap(find.byTooltip('Действия плейлиста'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Сбросить обложку'));
        await pumpUntil(tester, () => customCover.evaluate().isEmpty);
        await tester.pumpAndSettle();
        expect(mosaic, findsNothing);
        expect((await repo.artwork(playlist.id)).image, isNull);
        await properties();
        await pumpUntil(tester, () => mosaic.evaluate().isNotEmpty);
        expect(albumBadge, findsNothing);
        expect((await repo.detail(playlist.id)).playlist.isAlbum, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
