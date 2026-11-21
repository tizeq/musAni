import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Hash the encoded audio payload, excluding MP3 tags / FLAC metadata blocks.
/// Unknown or malformed framing fails closed before the original is replaced.
String audioDigest(String path, String extension) {
  final file = File(path).openSync();
  try {
    var start = 0;
    var end = file.lengthSync();
    Uint8List at(int offset, int count) {
      if (offset < 0 || offset + count > end)
        throw const FormatException('Повреждённая структура аудиофайла');
      file.setPositionSync(offset);
      final bytes = file.readSync(count);
      if (bytes.length != count)
        throw const FormatException('Аудиофайл усечён');
      return bytes;
    }

    bool signature(Uint8List bytes, String text) =>
        latin1.decode(bytes, allowInvalid: true) == text;
    if (extension == '.flac') {
      if (!signature(at(0, 4), 'fLaC'))
        throw const FormatException('Неверный заголовок FLAC');
      start = 4;
      var last = false;
      while (!last) {
        final block = at(start, 4);
        last = block[0] & 0x80 != 0;
        start += 4 + (block[1] << 16) + (block[2] << 8) + block[3];
        if (start > end) throw const FormatException('Повреждённые блоки FLAC');
      }
    } else {
      while (signature(at(start, 3), 'ID3')) {
        final tag = at(start, 10);
        if (tag.sublist(6).any((b) => b & 0x80 != 0))
          throw const FormatException('Неверный размер ID3');
        final length = (tag[6] << 21) + (tag[7] << 14) + (tag[8] << 7) + tag[9];
        start += 10 + length + (tag[3] == 4 && tag[5] & 0x10 != 0 ? 10 : 0);
      }
      if (end >= 128 && signature(at(end - 128, 3), 'TAG')) end -= 128;
      if (end >= 32 && signature(at(end - 32, 8), 'APETAGEX')) {
        final footer = ByteData.sublistView(at(end - 32, 32));
        end -= footer.getUint32(12, Endian.little);
        if (footer.getUint32(20, Endian.little) & 0x80000000 != 0) end -= 32;
      }
    }
    if (start >= end) throw const FormatException('Аудиоданные отсутствуют');
    final output = _DigestSink();
    final sink = sha256.startChunkedConversion(output);
    file.setPositionSync(start);
    var remaining = end - start;
    while (remaining > 0) {
      final bytes = file.readSync(remaining.clamp(1, 65536));
      if (bytes.isEmpty) throw const FormatException('Аудиофайл усечён');
      remaining -= bytes.length;
      sink.add(bytes);
    }
    sink.close();
    return output.value!.toString();
  } finally {
    file.closeSync();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
