import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> ffmpeg(List<String> arguments) async {
  final result = await Process.run('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    ...arguments,
  ]);
  if (result.exitCode != 0) throw StateError('ffmpeg failed: ${result.stderr}');
}

Future<File> createAudioFixture(
  Directory directory,
  String extension, {
  String name = 'Песня #1',
  String title = 'Первая песня',
  String album = 'Альбом',
  String artist = 'Исполнитель',
  String albumArtist = 'Группа',
  int track = 1,
  bool withCover = true,
  int durationSeconds = 1,
}) async {
  await directory.create(recursive: true);
  final cover = File('${directory.path}/cover.png');
  if (withCover && !cover.existsSync()) {
    await ffmpeg([
      '-f',
      'lavfi',
      '-i',
      'color=c=0x69d6b5:s=32x32',
      '-frames:v',
      '1',
      '-threads',
      '1',
      cover.path,
    ]);
  }
  final output = File('${directory.path}/$name.$extension');
  final codec = {
    'mp3': 'libmp3lame',
    'flac': 'flac',
    'm4a': 'aac',
    'ogg': 'libvorbis',
  }[extension]!;
  final arguments = ['-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo'];
  if (withCover && extension != 'ogg') arguments.addAll(['-i', cover.path]);
  arguments.addAll(['-t', '$durationSeconds', '-map', '0:a', '-c:a', codec]);
  if (withCover && extension != 'ogg') {
    arguments.addAll([
      '-map',
      '1:v',
      '-c:v',
      'copy',
      '-disposition:v',
      'attached_pic',
    ]);
  }
  if (withCover && extension == 'ogg') {
    final png = await cover.readAsBytes();
    final mime = utf8.encode('image/png');
    final block = BytesBuilder();
    void number(int value) =>
        block.add((ByteData(4)..setUint32(0, value)).buffer.asUint8List());
    number(3);
    number(mime.length);
    block.add(mime);
    number(0);
    number(32);
    number(32);
    number(24);
    number(0);
    number(png.length);
    block.add(png);
    arguments.addAll([
      '-metadata',
      'METADATA_BLOCK_PICTURE=${base64Encode(block.takeBytes())}',
    ]);
  }
  arguments.addAll([
    '-metadata',
    'title=$title',
    '-metadata',
    'album=$album',
    '-metadata',
    'artist=$artist',
    '-metadata',
    'album_artist=$albumArtist',
    '-metadata',
    'date=2026',
    '-metadata',
    'genre=Электроника',
    '-metadata',
    'track=$track/12',
    '-metadata',
    'disc=1/2',
    output.path,
  ]);
  await ffmpeg(arguments);
  return output;
}
