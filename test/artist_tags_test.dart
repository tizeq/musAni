import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musani/files/local_tracks.dart';
import 'package:musani/library/metadata_reader.dart';
import 'package:musani/metadata/playback_tags.dart';
import 'package:musani/metadata/tag_values.dart';
import 'package:musani/metadata/track_editor.dart';

import 'support/audio_fixtures.dart';

void main() {
  late Directory dir;
  setUp(
    () async =>
        dir = await Directory.systemTemp.createTemp('musani-artist-tags-'),
  );
  tearDown(() => dir.delete(recursive: true));
  const artists = [
    'Tyler, The Creator',
    'AC/DC',
    'Simon & Garfunkel',
    'Name; intact',
  ];

  test('normalization never guesses artist separators; duplicate names share identity', () {
    expect(artistValues([...artists, ' tyler, THE creator ', '']), artists);
    expect(
      trackArtistValues({
        'ARTIST': ['A / B, C; D & E'],
      }),
      ['A / B, C; D & E'],
    );
  });

  for (final format in ['mp3', 'flac', 'm4a', 'ogg']) {
    test(
      '$format reads separate artist values without changing punctuation or album artist',
      () async {
        final file = await createAudioFixture(dir, format);
        final tags = TagLibFile.open(file.path)!;
        try {
          final properties = tags.properties..['ARTIST'] = artists;
          expect(tags.setProperties(properties), isEmpty);
          expect(tags.save(), isTrue);
        } finally {
          tags.close();
        }
        final before = sha256.convert(await file.readAsBytes());
        final metadata = TagLibMetadataReader().read(
          file.path,
          '${dir.path}/covers',
        );
        expect(metadata.artists, artists);
        expect(metadata.albumArtist, 'Группа');
        expect(sha256.convert(await file.readAsBytes()), before);
        final playback = (await readPlaybackTags([
          LocalTrack(file.uri, 'fallback'),
        ])).single;
        expect(playback.artists, artists);
        expect(playback.name, metadata.title);
        expect(sha256.convert(await file.readAsBytes()), before);
      },
    );
  }

  for (final format in ['mp3', 'flac']) {
    test(
      '$format respects explicit ARTISTS and synchronizes it only when editing the artist list',
      () async {
        final file = await createAudioFixture(dir, format);
        final tag = TagLibFile.open(file.path)!;
        try {
          final properties = tag.properties
            ..['ARTIST'] = ['Tyler, The Creator feat. Guest']
            ..['ARTISTS'] = ['Tyler, The Creator', 'Guest'];
          expect(tag.setProperties(properties), isEmpty);
          expect(tag.save(), isTrue);
        } finally {
          tag.close();
        }
        final editor = TagLibTrackEditor('${dir.path}/backups');
        var snapshot = await editor.read(file.path);
        expect(snapshot.artists, ['Tyler, The Creator', 'Guest']);
        expect(
          TagLibMetadataReader().read(file.path, '${dir.path}/covers').artists,
          snapshot.artists,
        );
        await editor.save(
          snapshot,
          const MetadataPatch({'TITLE': 'Title only'}),
        );
        final unchanged = TagLibFile.open(file.path)!;
        try {
          expect(unchanged.properties['ARTIST'], [
            'Tyler, The Creator feat. Guest',
          ]);
          expect(unchanged.properties['ARTISTS'], [
            'Tyler, The Creator',
            'Guest',
          ]);
        } finally {
          unchanged.close();
        }
        snapshot = await editor.read(file.path);
        await editor.save(
          snapshot,
          const MetadataPatch({}, artists: ['AC/DC']),
        );
        final changed = TagLibFile.open(file.path)!;
        try {
          expect(changed.properties['ARTIST'], ['AC/DC']);
          expect(changed.properties['ARTISTS'], ['AC/DC']);
        } finally {
          changed.close();
        }
        await editor.save(
          await editor.read(file.path),
          const MetadataPatch({}, artists: []),
        );
        expect((await editor.read(file.path)).artists, isEmpty);
      },
    );

    test(
      '$format editor adds/removes artists using real multi-value tags and preserves other tags',
      () async {
        final file = await createAudioFixture(dir, format);
        final editor = TagLibTrackEditor('${dir.path}/backups');
        var snapshot = await editor.read(file.path);
        expect(snapshot.artists, ['Исполнитель']);
        await editor.save(snapshot, const MetadataPatch({}, artists: artists));
        snapshot = await editor.read(file.path);
        expect(snapshot.artists, artists);
        expect(snapshot.fields['ALBUMARTIST'], 'Группа');
        if (format == 'mp3') {
          // ID3v2.4 supports multiple TPE1 values; no comma-based legacy encoding.
          final bytes = await file.open();
          try {
            expect((await bytes.read(10))[3], 4);
          } finally {
            await bytes.close();
          }
        } else {
          // Independent evidence of repeated Vorbis comments in the actual file.
          final bytes = await file.readAsBytes();
          final text = String.fromCharCodes(bytes);
          for (final name in artists.take(3)) {
            expect(text.contains('ARTIST=$name'), isTrue);
          }
        }
        await editor.save(
          snapshot,
          const MetadataPatch({}, artists: ['Tyler, The Creator']),
        );
        snapshot = await editor.read(file.path);
        expect(snapshot.artists, ['Tyler, The Creator']);
        final metadata = TagLibMetadataReader().read(
          file.path,
          '${dir.path}/covers',
        );
        expect(metadata.artists, ['Tyler, The Creator']);
        expect(metadata.albumArtist, 'Группа');
        await editor.save(snapshot, const MetadataPatch({}, artists: []));
        expect((await editor.read(file.path)).artists, isEmpty);
        final tags = TagLibFile.open(file.path)!;
        try {
          expect(tags.properties['ARTIST'], isNull);
        } finally {
          tags.close();
        }
      },
    );
  }

  test('invalid artist lists cannot write the source', () async {
    final file = await createAudioFixture(dir, 'flac');
    final editor = TagLibTrackEditor('${dir.path}/backups');
    final snapshot = await editor.read(file.path);
    final before = sha256.convert(await file.readAsBytes());
    for (final invalid in [
      [' '],
      ['bad\u0000name'],
      List.filled(101, 'Artist'),
    ]) {
      await expectLater(
        editor.save(snapshot, MetadataPatch(const {}, artists: invalid)),
        throwsFormatException,
      );
    }
    expect(sha256.convert(await file.readAsBytes()), before);
  });
}
