import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musani/files/local_tracks.dart';

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp('musani-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test('Unicode, spaces, #, uppercase extension and duplicate paths', () async {
    final file = await File('${directory.path}/Песня #1.FLAC')
        .writeAsBytes([0]);
    final tracks = await LocalTracks().resolve([file.path, file.path]);
    expect(tracks, hasLength(1));
    expect(tracks.single.uri.scheme, 'file');
    expect(tracks.single.uri.toFilePath(), file.path);
  });
  test('unsupported and missing files fail before opening a queue', () async {
    await expectLater(
      LocalTracks().resolve(['${directory.path}/a.txt']),
      throwsFormatException,
    );
    await expectLater(
      LocalTracks().resolve(['${directory.path}/a.mp3']),
      throwsA(isA<FileSystemException>()),
    );
  });
  test('empty selection produces an empty list', () async {
    expect(await LocalTracks().resolve([]), isEmpty);
  });
}
