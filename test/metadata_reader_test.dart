import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musani/library/metadata_reader.dart';

import 'support/audio_fixtures.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('musani-tags-'),
  );
  tearDown(() => directory.delete(recursive: true));

  for (final extension in ['mp3', 'flac', 'm4a', 'ogg']) {
    test(
      'reads $extension tags and embedded cover without changing audio file',
      () async {
        final file = await createAudioFixture(directory, extension);
        final before = sha256.convert(await file.readAsBytes());
        final path = file.path;
        final covers = '${directory.path}/artwork';
        final metadata = await Isolate.run(
          () => TagLibMetadataReader().read(path, covers),
        );
        expect(metadata.warning, isNull);
        expect(metadata.title, 'Первая песня');
        expect(metadata.artists, ['Исполнитель']);
        expect(metadata.album, 'Альбом');
        expect(metadata.albumArtist, 'Группа');
        expect(metadata.year, 2026);
        expect(metadata.genre, 'Электроника');
        expect(metadata.trackNumber, 1);
        expect(metadata.discNumber, 1);
        expect(metadata.durationMs, greaterThanOrEqualTo(900));
        expect(metadata.properties['ALBUMARTIST'], ['Группа']);
        expect(metadata.coverKey, isNotNull);
        expect(
          await File('$covers/${metadata.coverKey}.art').readAsBytes(),
          await File('${directory.path}/cover.png').readAsBytes(),
        );
        expect(sha256.convert(await file.readAsBytes()), before);
      },
    );
  }

  test('missing tags and invalid audio have usable fallbacks', () async {
    final file = await createAudioFixture(
      directory,
      'mp3',
      title: '',
      album: '',
      artist: '',
      albumArtist: '',
      withCover: false,
    );
    final metadata = TagLibMetadataReader().read(
      file.path,
      '${directory.path}/art',
    );
    expect(metadata.title, 'Песня #1');
    expect(metadata.albumTagged, isFalse);
    expect(metadata.artists, ['Неизвестный исполнитель']);
    expect(metadata.coverKey, isNull);
    final invalid = await File('${directory.path}/broken.flac')
        .writeAsString('broken');
    final fallback = TagLibMetadataReader().read(
      invalid.path,
      '${directory.path}/art',
    );
    expect(fallback.title, 'broken');
    expect(fallback.warning, isNotNull);
  });
}
