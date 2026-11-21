import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

import 'audio_digest.dart';
import 'linux_files.dart';
import 'tag_values.dart';

const editableFields = [
  'TITLE',
  'ALBUMARTIST',
  'ALBUM',
  'DATE',
  'GENRE',
  'TRACKNUMBER',
];

class EditSnapshot {
  const EditSnapshot({
    required this.path,
    required this.hash,
    required this.size,
    required this.modifiedUs,
    required this.changedUs,
    required this.inode,
    required this.fields,
    this.cover,
    this.artists = const [],
  });
  final String path;
  final String hash;
  final int size;
  final int modifiedUs;
  final int changedUs;
  final int inode;
  final Map<String, String> fields;
  final Uint8List? cover;
  final List<String> artists;
}

class MetadataPatch {
  const MetadataPatch(this.fields, {this.artists, this.coverPath});

  /// Only changed fields. Missing means keep; an empty value means clear.
  final Map<String, String> fields;
  final String? coverPath;

  /// Null keeps the original list; [] removes track artist tags.
  final List<String>? artists;
}

class EditResult {
  const EditResult(this.backupPath, {this.warning});
  final String backupPath;
  final String? warning;
}

abstract interface class TrackEditor {
  Future<EditSnapshot> read(String path);
  Future<EditResult> save(EditSnapshot snapshot, MetadataPatch patch);
}

class TagLibTrackEditor implements TrackEditor {
  const TagLibTrackEditor(this.backupDirectory);
  final String backupDirectory;

  @override
  Future<EditSnapshot> read(String path) =>
      Isolate.run(() => readEditSnapshot(path));

  @override
  Future<EditResult> save(EditSnapshot snapshot, MetadataPatch patch) {
    final backup = backupDirectory;
    return Isolate.run(() => saveTrackMetadata(snapshot, patch, backup));
  }
}

String _extension(String path) {
  final extension = p.extension(path).toLowerCase();
  if (!Platform.isLinux || !['.mp3', '.flac'].contains(extension)) {
    throw UnsupportedError('Редактор поддерживает MP3 и FLAC на Linux');
  }
  return extension;
}

TagLibFile _openValid(String path) {
  final file = TagLibFile.open(path);
  if (file == null)
    throw const FormatException('Не удалось прочитать аудиофайл');
  if (file.sampleRate <= 0 || file.duration == Duration.zero) {
    file.close();
    throw const FormatException('Повреждённый аудиофайл');
  }
  return file;
}

Future<String> _hash(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

Future<EditSnapshot> readEditSnapshot(String path) async {
  _extension(path);
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw FileSystemException('Нужен обычный локальный файл, не ссылка', path);
  }
  final stat = await File(path).stat();
  final info = identity(path);
  final hash = await _hash(path);
  final file = _openValid(path);
  late Map<String, String> fields;
  Uint8List? cover;
  late List<String> artists;
  try {
    final properties = file.properties;
    artists = trackArtistValues(properties, fallback: file.artist);
    fields = {
      for (final key in editableFields)
        key: (properties[key] ?? const []).join(' / '),
    };
    fields['DATE'] = file.year == 0 ? '' : '${file.year}';
    fields['TRACKNUMBER'] = file.track == 0 ? '' : '${file.track}';
    cover = file.coverData;
    if (cover != null && cover.length > 16 * 1024 * 1024) cover = null;
  } finally {
    file.close();
  }
  final after = await File(path).stat();
  if (stat.size != after.size ||
      stat.modified != after.modified ||
      stat.changed != after.changed ||
      info.inode != identity(path).inode ||
      hash != await _hash(path)) {
    throw StateError(
      'Файл изменился во время чтения. Откройте редактор заново.',
    );
  }
  return EditSnapshot(
    path: path,
    hash: hash,
    size: stat.size,
    modifiedUs: stat.modified.microsecondsSinceEpoch,
    changedUs: stat.changed.microsecondsSinceEpoch,
    inode: info.inode,
    fields: fields,
    artists: artists,
    cover: cover,
  );
}

Future<void> _checkRevision(EditSnapshot snapshot) async {
  requireEditable(snapshot.path);
  final stat = await File(snapshot.path).stat();
  if (stat.size != snapshot.size ||
      stat.modified.microsecondsSinceEpoch != snapshot.modifiedUs ||
      stat.changed.microsecondsSinceEpoch != snapshot.changedUs ||
      identity(snapshot.path).inode != snapshot.inode ||
      await _hash(snapshot.path) != snapshot.hash) {
    throw StateError(
      'Файл изменён другой программой. Откройте редактор заново; изменения не записаны.',
    );
  }
}

Future<(Uint8List, String)> _readCover(String path) async {
  if (await File(path).length() > 16 * 1024 * 1024)
    throw const FormatException('Обложка больше 16 МиБ');
  final bytes = await File(path).readAsBytes();
  final decoder = image.findDecoderForData(bytes);
  if (decoder is! image.JpegDecoder && decoder is! image.PngDecoder) {
    throw const FormatException('Выберите изображение JPEG или PNG');
  }
  final info = decoder!.startDecode(bytes);
  if (info == null ||
      info.width * info.height > 32000000 ||
      info.width > 8192 ||
      info.height > 8192 ||
      decoder.decodeFrame(0) == null)
    throw const FormatException('Повреждённая или слишком большая обложка');
  return (bytes, decoder is image.PngDecoder ? 'image/png' : 'image/jpeg');
}

void validatePatch(MetadataPatch patch) {
  if (patch.artists case final artists?) {
    if (artists.length > 100 ||
        artists.any(
          (artist) =>
              artist.trim().isEmpty ||
              artist.length > 8192 ||
              artist.contains('\u0000'),
        )) {
      throw const FormatException(
        'Укажите до 100 непустых имён исполнителей без недопустимых символов',
      );
    }
  }
  for (final entry in patch.fields.entries) {
    if (!editableFields.contains(entry.key))
      throw ArgumentError('Неподдерживаемое поле ${entry.key}');
    if (entry.value.length > 8192 || entry.value.contains('\u0000'))
      throw const FormatException(
        'Слишком длинное значение или недопустимый символ',
      );
    if (['DATE', 'TRACKNUMBER'].contains(entry.key) && entry.value.isNotEmpty) {
      final number = int.tryParse(entry.value);
      if (number == null || number < 1 || number > 9999)
        throw const FormatException(
          'Год и номер трека: от 1 до 9999 либо пустое поле',
        );
    }
  }
}

/// Changes are made ONLY on a sibling copy. A verified copy replaces the path
/// once, using Linux atomic rename; the durable backup is never auto-deleted.
Future<EditResult> saveTrackMetadata(
  EditSnapshot snapshot,
  MetadataPatch patch,
  String backupDirectory, {
  void Function(File staged)? beforeWrite,
  void Function(File staged)? beforeVerify,
  Future<void> Function()? beforeCommit,
}) async {
  _extension(snapshot.path);
  requireEditable(snapshot.path);
  final lock = lockMetadataFile(snapshot.path);
  try {
    return await _saveLocked(
      snapshot,
      patch,
      backupDirectory,
      beforeWrite: beforeWrite,
      beforeVerify: beforeVerify,
      beforeCommit: beforeCommit,
    );
  } finally {
    unlockMetadataFile(lock);
  }
}

Future<EditResult> _saveLocked(
  EditSnapshot snapshot,
  MetadataPatch patch,
  String backupDirectory, {
  void Function(File staged)? beforeWrite,
  void Function(File staged)? beforeVerify,
  Future<void> Function()? beforeCommit,
}) async {
  validatePatch(patch);
  final extension = _extension(snapshot.path);
  await _checkRevision(snapshot);
  final cover = patch.coverPath == null
      ? null
      : await _readCover(patch.coverPath!);
  final original = File(snapshot.path);
  final info = identity(snapshot.path);
  final mode = original.statSync().mode;
  final backupRoot = await Directory(backupDirectory).create(recursive: true);
  if (FileSystemEntity.typeSync(backupRoot.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FileSystemException(
      'Каталог резервных копий не должен быть ссылкой',
      backupRoot.path,
    );
  }
  setPermissions(backupRoot.path, 0x1c0); // 0700
  final backupDir = await backupRoot.createTemp('edit-');
  final backup = await original.copy(
    p.join(backupDir.path, 'original$extension'),
  );
  setPermissions(backup.path, 0x180); // 0600
  final backupHandle = await backup.open(mode: FileMode.append);
  try {
    await backupHandle.flush();
  } finally {
    await backupHandle.close();
  }
  if (await _hash(backup.path) != snapshot.hash)
    throw StateError('Не удалось проверить резервную копию');
  syncDirectory(backupDir.path);
  syncDirectory(backupRoot.path);
  final staging = await original.parent.createTemp('.musani-edit-');
  try {
    final staged = await backup.copy(p.join(staging.path, 'track$extension'));
    requireEditable(staged.path);
    setPermissions(staged.path, 0x180);
    beforeWrite?.call(staged);
    final audio = audioDigest(backup.path, extension);
    final tag = _openValid(staged.path);
    late Map<String, List<String>> expected;
    late List<Picture> pictures;
    try {
      expected = {
        for (final entry in tag.properties.entries)
          entry.key: List.of(entry.value),
      };
      pictures = tag.pictures;
      for (final entry in patch.fields.entries) {
        final value = entry.value.trim();
        if (entry.key == 'DATE') expected.remove('YEAR');
        if (value.isEmpty)
          expected.remove(entry.key);
        else if (entry.key == 'TRACKNUMBER' &&
            (expected[entry.key]?.firstOrNull?.contains('/') ?? false)) {
          expected[entry.key] = [
            '$value/${expected[entry.key]!.first.split('/').skip(1).join('/')}',
          ];
        } else if (entry.key == 'DATE' &&
            (expected['DATE']?.firstOrNull?.startsWith(RegExp(r'\d{4}-.+')) ??
                false)) {
          expected['DATE'] = ['$value${expected['DATE']!.first.substring(4)}'];
        } else {
          expected[entry.key] = [value];
        }
      }
      if (patch.artists case final artists?) {
        final values = artistValues(artists);
        if (values.isEmpty) {
          expected.remove('ARTIST');
          expected.remove('ARTISTS');
        } else {
          expected['ARTIST'] = values;
          if (expected.containsKey('ARTISTS')) expected['ARTISTS'] = values;
        }
      }
      final unsupported = tag.setProperties(expected);
      if (unsupported.keys.any(
        (key) =>
            patch.fields.containsKey(key) ||
            ['ARTIST', 'ARTISTS'].contains(key) && patch.artists != null,
      ))
        throw StateError(
          'Формат файла не поддерживает изменение выбранного поля',
        );
      if (cover != null) {
        final replacement = Picture(bytes: cover.$1, mimeType: cover.$2);
        final front = pictures.indexWhere(
          (picture) => picture.pictureType == 'Front Cover',
        );
        pictures = List.of(pictures);
        if (front < 0)
          pictures.insert(0, replacement);
        else
          pictures[front] = replacement;
        if (!tag.setPictures(pictures))
          throw StateError('Не удалось записать обложку');
      }
      if (!tag.save()) throw StateError('TagLib не смог сохранить теги');
    } finally {
      tag.close();
    }
    beforeVerify?.call(staged);
    final verification = _openValid(staged.path);
    try {
      if (jsonEncode(_canonical(verification.properties)) !=
          jsonEncode(_canonical(expected))) {
        throw StateError(
          'Проверка сохранённых тегов не пройдена. Оригинал сохранён.',
        );
      }
      final actual = verification.pictures;
      if (actual.length != pictures.length ||
          [
            for (var i = 0; i < actual.length; i++)
              _pictureSignature(actual[i]) == _pictureSignature(pictures[i]),
          ].contains(false)) {
        throw StateError('Проверка сохранённых обложек не пройдена');
      }
    } finally {
      verification.close();
    }
    if (audioDigest(staged.path, extension) != audio)
      throw StateError('Аудиоданные изменились. Оригинал сохранён.');
    setPermissions(staged.path, mode, original: info);
    final handle = await staged.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
    final journal = File(p.join(backupDir.path, 'operation.json'));
    final updatedHash = await _hash(staged.path);
    await journal.writeAsString(
      jsonEncode({
        'path': snapshot.path,
        'originalHash': snapshot.hash,
        'updatedHash': updatedHash,
        'state': 'prepared',
      }),
      flush: true,
    );
    syncDirectory(backupDir.path);
    await beforeCommit?.call();
    await _checkRevision(snapshot);
    await staged.rename(snapshot.path);
    String? warning;
    try {
      syncDirectory(original.parent.path);
      await journal.writeAsString(
        jsonEncode({
          'path': snapshot.path,
          'originalHash': snapshot.hash,
          'updatedHash': updatedHash,
          'state': 'committed',
        }),
        flush: true,
      );
    } catch (error) {
      warning =
          'Файл сохранён, но подтверждение записи на диск не завершено: $error. Резервная копия: ${backup.path}';
    }
    return EditResult(backup.path, warning: warning);
  } finally {
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
    } on FileSystemException {
      // Cleanup must not mask a failed write or turn an already committed
      // save into a reported failure. Scanner ignores our staging directories.
    }
  }
}

Map<String, List<String>> _canonical(Map<String, List<String>> properties) => {
  for (final key in (properties.keys.toList()..sort()))
    if (properties[key]!.isNotEmpty) key: properties[key]!,
};

String _pictureSignature(Picture picture) => jsonEncode([
  picture.pictureType,
  picture.mimeType,
  picture.description ?? '',
  sha256.convert(picture.bytes).toString(),
]);
