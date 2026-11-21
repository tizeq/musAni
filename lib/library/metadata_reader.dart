import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:path/path.dart' as p;

import '../metadata/tag_values.dart';
import 'models.dart';

abstract interface class MetadataReader {
  TrackMetadata read(String path, String coverDirectory);
}

/// Used only in a worker isolate. No setters, save() or write-access APIs are
/// exposed here; the only files we write are our own extracted artwork cache.
class TagLibMetadataReader implements MetadataReader {
  @override
  TrackMetadata read(String path, String coverDirectory) {
    final fallback = p.basenameWithoutExtension(path);
    TagLibFile? file;
    try {
      file = TagLibFile.open(
        path,
        audioPropertiesStyle: TagLibAudioPropertiesStyle.fast,
      );
      if (file == null)
        throw const FormatException(
          'Повреждённый или неподдерживаемый аудиофайл',
        );
      if (file.sampleRate <= 0 && file.duration == Duration.zero) {
        throw const FormatException('Аудиоданные не распознаны');
      }
      final properties = file.properties;
      final artists = trackArtistValues(properties, fallback: file.artist);
      if (artists.isEmpty) artists.add('Неизвестный исполнитель');
      final albumArtist = albumArtistValue(properties);
      final album = file.album.trim();
      String? coverKey;
      String? warning;
      try {
        final cover = file.coverData;
        if (cover != null && cover.isNotEmpty) {
          if (cover.length > 16 * 1024 * 1024) {
            warning = 'Обложка превышает 16 МиБ';
          } else {
            coverKey = sha256.convert(cover).toString();
            final destination = File(p.join(coverDirectory, '$coverKey.art'));
            if (!destination.existsSync()) {
              destination.parent.createSync(recursive: true);
              final temporary = File('${destination.path}.$pid.tmp');
              temporary.writeAsBytesSync(cover, flush: true);
              temporary.renameSync(destination.path);
            }
          }
        }
      } catch (error) {
        warning = 'Не удалось прочитать обложку: $error';
      }
      return TrackMetadata(
        title: file.title.trim().isEmpty ? fallback : file.title.trim(),
        artists: artists,
        album: album,
        albumTagged: album.isNotEmpty,
        albumArtist: albumArtist,
        year: file.year,
        genre: file.genre.trim(),
        trackNumber: file.track,
        discNumber:
            int.tryParse(
              (properties['DISCNUMBER']?.firstOrNull ?? '').split('/').first,
            ) ??
            0,
        durationMs: file.duration.inMilliseconds,
        properties: properties,
        coverKey: coverKey,
        warning: warning,
      );
    } catch (error) {
      return TrackMetadata(
        title: fallback,
        artists: const ['Неизвестный исполнитель'],
        album: '',
        albumArtist: '',
        albumTagged: false,
        warning: 'Не удалось прочитать метаданные: $error',
      );
    } finally {
      file?.close();
    }
  }
}
