import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musani/metadata/audio_digest.dart';
import 'package:musani/metadata/linux_files.dart';
import 'package:musani/metadata/track_editor.dart';

import 'support/audio_fixtures.dart';

void main() {
  late Directory dir;
  late TagLibTrackEditor editor;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('musani-edit-test-');
    editor = TagLibTrackEditor('${dir.path}/backups');
  });
  tearDown(() => dir.delete(recursive: true));
  Future<String> hash(File file) async =>
      sha256.convert(await file.readAsBytes()).toString();

  for (final format in ['mp3', 'flac']) {
    test(
      '$format writes real tags and cover, preserves audio, unrelated tags and backup',
      () async {
        final file = await createAudioFixture(dir, format);
        final extra = TagLibFile.open(file.path)!;
        final props = extra.properties;
        props['COMMENT'] = ['Keep this comment'];
        props['LYRICS'] = ['Не изменять текст'];
        props['CUSTOM_TEST'] = ['arbitrary value'];
        expect(extra.setProperties(props), isEmpty);
        final pictures = extra.pictures;
        expect(
          extra.setPictures([
            ...pictures,
            Picture(
              bytes: pictures.first.bytes,
              mimeType: 'image/png',
              pictureType: 'Back Cover',
              description: 'Keep back cover',
            ),
          ]),
          isTrue,
        );
        expect(extra.save(), isTrue);
        extra.close();
        final originalHash = await hash(file);
        final audio = audioDigest(file.path, '.$format');
        final snapshot = await editor.read(file.path);
        expect(snapshot.fields['TITLE'], 'Первая песня');
        expect(snapshot.fields['ALBUMARTIST'], 'Группа');
        final newImage = '${dir.path}/replacement.png';
        await ffmpeg([
          '-f',
          'lavfi',
          '-i',
          'color=c=red:s=48x48',
          '-frames:v',
          '1',
          '-threads',
          '1',
          newImage,
        ]);
        final result = await editor.save(
          snapshot,
          MetadataPatch(
            {
              'TITLE': 'Новое название',
              'ALBUMARTIST': 'Другой album artist',
              'ALBUM': 'Новый альбом',
              'DATE': '2024',
              'GENRE': 'Jazz',
              'TRACKNUMBER': '7',
            },
            artists: const ['Новый артист'],
            coverPath: newImage,
          ),
        );
        expect(await hash(File(result.backupPath)), originalHash);
        expect(audioDigest(file.path, '.$format'), audio);
        final changed = await editor.read(file.path);
        expect(changed.fields['TITLE'], 'Новое название');
        expect(changed.fields['DATE'], '2024');
        expect(changed.fields['TRACKNUMBER'], '7');
        final actual = TagLibFile.open(file.path)!;
        try {
          expect(actual.properties['COMMENT'], ['Keep this comment']);
          expect(actual.properties['LYRICS'], ['Не изменять текст']);
          expect(actual.properties['CUSTOM_TEST'], ['arbitrary value']);
          expect(actual.properties['DISCNUMBER'], ['1/2']);
          expect(actual.properties['TRACKNUMBER'], ['7/12']);
          // FFmpeg's initial picture is Other, not Front Cover; retain it and
          // the back cover, adding a new explicit Front Cover.
          expect(actual.pictures, hasLength(3));
          expect(actual.pictures.last.description, 'Keep back cover');
          expect(actual.coverData, await File(newImage).readAsBytes());
        } finally {
          actual.close();
        }
        // Independent decoder: PCM samples before/after must match too.
        final beforePcm = await Process.run('ffmpeg', [
          '-v',
          'error',
          '-i',
          result.backupPath,
          '-map',
          '0:a:0',
          '-f',
          'hash',
          '-hash',
          'sha256',
          '-',
        ]);
        final afterPcm = await Process.run('ffmpeg', [
          '-v',
          'error',
          '-i',
          file.path,
          '-map',
          '0:a:0',
          '-f',
          'hash',
          '-hash',
          'sha256',
          '-',
        ]);
        expect(beforePcm.exitCode, 0);
        expect(afterPcm.exitCode, 0);
        expect(afterPcm.stdout, beforePcm.stdout);
      },
    );

    test(
      '$format permits clearing fields, preserving unchanged fields and artwork',
      () async {
        final file = await createAudioFixture(dir, format);
        final snapshot = await editor.read(file.path);
        await editor.save(
          snapshot,
          const MetadataPatch({
            'TITLE': '',
            'DATE': '',
            'TRACKNUMBER': '',
            'ALBUMARTIST': '',
          }),
        );
        final changed = await editor.read(file.path);
        expect(changed.fields['TITLE'], '');
        expect(changed.fields['DATE'], '');
        expect(changed.fields['TRACKNUMBER'], '');
        expect(changed.artists, snapshot.artists);
        expect(changed.cover, snapshot.cover);
      },
    );
  }

  test(
    'concurrent changes are rejected, including changes just before commit',
    () async {
      final file = await createAudioFixture(dir, 'mp3');
      final snapshot = await editor.read(file.path);
      await expectLater(
        saveTrackMetadata(
          snapshot,
          const MetadataPatch({'TITLE': 'new'}),
          editor.backupDirectory,
          beforeCommit: () async {
            await file.writeAsBytes([1, 2, 3], mode: FileMode.append);
          },
        ),
        throwsStateError,
      );
      final changed = await hash(file);
      await expectLater(
        editor.save(snapshot, const MetadataPatch({'TITLE': 'lost update'})),
        throwsStateError,
      );
      expect(await hash(file), changed);
    },
  );

  test('a failed staged write cannot damage the original', () async {
    final file = await createAudioFixture(dir, 'flac');
    final before = await hash(file);
    await expectLater(
      saveTrackMetadata(
        await editor.read(file.path),
        const MetadataPatch({'TITLE': 'new'}),
        editor.backupDirectory,
        beforeVerify: (staged) => staged.writeAsBytesSync([0, 1, 2]),
      ),
      throwsFormatException,
    );
    expect(await hash(file), before);
    expect(
      dir.listSync().whereType<Directory>().where(
        (d) => d.path.contains('.musani-edit-'),
      ),
      isEmpty,
    );
  });

  test(
    'read-only file and invalid image fail without touching original',
    () async {
      final file = await createAudioFixture(dir, 'mp3');
      final snapshot = await editor.read(file.path);
      final before = await hash(file);
      await Process.run('chmod', ['444', file.path]);
      await expectLater(
        editor.save(snapshot, const MetadataPatch({'TITLE': 'no access'})),
        throwsA(isA<FileSystemException>()),
      );
      await Process.run('chmod', ['644', file.path]);
      final image = await File('${dir.path}/bad.png')
          .writeAsString('not a picture');
      await expectLater(
        editor.save(
          await editor.read(file.path),
          MetadataPatch(const {}, coverPath: image.path),
        ),
        throwsFormatException,
      );
      expect(await hash(file), before);
    },
  );

  test(
    'native save failure leaves original and verified backup intact',
    () async {
      final file = await createAudioFixture(dir, 'mp3');
      final before = await hash(file);
      await expectLater(
        saveTrackMetadata(
          await editor.read(file.path),
          const MetadataPatch({'TITLE': 'cannot write'}),
          editor.backupDirectory,
          beforeWrite: (staged) => setPermissions(staged.path, 0x124), // 0444
        ),
        throwsStateError,
      );
      expect(await hash(file), before);
      final backups = await Directory(editor.backupDirectory)
          .list(recursive: true)
          .where((entry) => entry.path.endsWith('original.mp3'))
          .toList();
      expect(backups, hasLength(1));
      expect(await hash(File(backups.single.path)), before);
    },
  );

  test(
    'busy file and unavailable backup directory fail before replacement',
    () async {
      final file = await createAudioFixture(dir, 'flac');
      final before = await hash(file);
      final snapshot = await editor.read(file.path);
      final lock = lockMetadataFile(file.path);
      try {
        await expectLater(
          editor.save(snapshot, const MetadataPatch({'TITLE': 'locked'})),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        unlockMetadataFile(lock);
      }
      final blocked = await File('${dir.path}/blocked').writeAsString('keep');
      await expectLater(
        TagLibTrackEditor(blocked.path)
            .save(snapshot, const MetadataPatch({'TITLE': 'no backup'})),
        throwsA(isA<FileSystemException>()),
      );
      expect(await blocked.readAsString(), 'keep');
      expect(await hash(file), before);
    },
  );

  test(
    'links are refused and successful replacement preserves permissions',
    () async {
      final file = await createAudioFixture(dir, 'flac');
      final before = await hash(file);
      final link = await Link('${dir.path}/link.flac').create(file.path);
      await expectLater(
        editor.read(link.path),
        throwsA(isA<FileSystemException>()),
      );
      final alias = '${dir.path}/hardlink.flac';
      expect((await Process.run('ln', [file.path, alias])).exitCode, 0);
      await expectLater(
        editor.save(
          await editor.read(file.path),
          const MetadataPatch({'TITLE': 'no links'}),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await hash(file), before);
      await File(alias).delete();
      setPermissions(file.path, 0x1a0); // 0640
      final owner = identity(file.path);
      await editor.save(
        await editor.read(file.path),
        const MetadataPatch({'TITLE': 'safe'}),
      );
      expect((await file.stat()).mode & 0x1ff, 0x1a0);
      expect(identity(file.path).owner, owner.owner);
      expect(identity(file.path).group, owner.group);
    },
  );

  test(
    'corrupt and unsupported files are rejected; invalid numbers do not write',
    () async {
      final file = await File('${dir.path}/broken.mp3').writeAsString('broken');
      await expectLater(editor.read(file.path), throwsFormatException);
      await expectLater(
        editor.read('${dir.path}/a.m4a'),
        throwsUnsupportedError,
      );
      final valid = await createAudioFixture(dir, 'mp3');
      final before = await hash(valid);
      await expectLater(
        editor.save(
          await editor.read(valid.path),
          const MetadataPatch({'DATE': 'wrong'}),
        ),
        throwsFormatException,
      );
      expect(await hash(valid), before);
    },
  );
}
