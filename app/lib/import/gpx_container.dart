/// The container of Guitar Pro 6 files (.gpx): a "BCFZ" compressed block
/// holding a "BCFS" file system, in which `score.gpif` is the music.
library;

import 'dart:typed_data';

import 'score.dart';

class _BitReader {
  _BitReader(this.bytes, this.pos);
  final Uint8List bytes;
  int pos;
  int bit = 0;

  bool get eof => pos >= bytes.length;

  int readBit() {
    if (pos >= bytes.length) throw ImportException('The file ends too early (damaged file?)');
    final v = (bytes[pos] >> (7 - bit)) & 1;
    if (++bit == 8) {
      bit = 0;
      pos++;
    }
    return v;
  }

  /// Most significant bit first.
  int readBits(int count) {
    var v = 0;
    for (var i = count - 1; i >= 0; i--) {
      v |= readBit() << i;
    }
    return v;
  }

  /// Least significant bit first.
  int readBitsReversed(int count) {
    var v = 0;
    for (var i = 0; i < count; i++) {
      v |= readBit() << i;
    }
    return v;
  }
}

/// Decompresses a BCFZ block that starts at [offset] (right after the
/// "BCFZ" tag).
Uint8List decompressBcfz(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.length) throw ImportException('Damaged Guitar Pro 6 file');
  final expected = ByteData.sublistView(bytes).getUint32(offset, Endian.little);
  if (expected > 200 * 1024 * 1024) throw ImportException('Guitar Pro 6 file is too large');
  final out = BytesBuilder(copy: false);
  final buffer = Uint8List(expected);
  var length = 0;
  final r = _BitReader(bytes, offset + 4);
  while (length < expected && !r.eof) {
    if (r.readBit() == 1) {
      final wordSize = r.readBits(4);
      final back = r.readBitsReversed(wordSize);
      final size = r.readBitsReversed(wordSize);
      final from = length - back;
      if (from < 0 || back == 0) throw ImportException('Damaged Guitar Pro 6 file');
      final toRead = back < size ? back : size;
      for (var i = 0; i < toRead && length < expected; i++) {
        buffer[length++] = buffer[from + i];
      }
    } else {
      final size = r.readBitsReversed(2);
      for (var i = 0; i < size && length < expected; i++) {
        buffer[length++] = r.readBits(8);
      }
    }
  }
  out.add(Uint8List.sublistView(buffer, 0, length));
  return out.toBytes();
}

/// Reads the files of a BCFS file system.
Map<String, Uint8List> readBcfs(Uint8List data) {
  const sectorSize = 0x1000;
  final files = <String, Uint8List>{};
  final d = ByteData.sublistView(data);
  var offset = sectorSize;
  while (offset + 0x98 < data.length) {
    if (d.getInt32(offset, Endian.little) == 2) {
      var end = offset + 4;
      while (end < offset + 4 + 127 && end < data.length && data[end] != 0) {
        end++;
      }
      final name = String.fromCharCodes(data, offset + 4, end);
      final size = d.getInt32(offset + 0x8c, Endian.little);
      final content = BytesBuilder(copy: false);
      var pointer = offset + 0x94;
      while (pointer + 4 <= data.length) {
        final sector = d.getInt32(pointer, Endian.little);
        if (sector <= 0) break;
        final start = sector * sectorSize;
        if (start >= data.length) break;
        final stop = start + sectorSize > data.length ? data.length : start + sectorSize;
        content.add(Uint8List.sublistView(data, start, stop));
        pointer += 4;
      }
      final bytes = content.toBytes();
      if (size >= 0 && size <= bytes.length) {
        files[name] = Uint8List.sublistView(bytes, 0, size);
      }
    }
    offset += sectorSize;
  }
  return files;
}

/// Extracts `score.gpif` (the music as XML) from a .gpx file.
Uint8List readGpxScore(Uint8List bytes) {
  if (bytes.length < 8) throw ImportException('Not a Guitar Pro 6 file');
  final tag = String.fromCharCodes(bytes, 0, 4);
  Uint8List data;
  if (tag == 'BCFZ') {
    data = decompressBcfz(bytes, 4);
  } else if (tag == 'BCFS') {
    data = bytes;
  } else {
    throw ImportException('Not a Guitar Pro 6 file');
  }
  // The file system offsets count either from the "BCFS" tag or from the byte after it.
  for (final candidate in [data, if (data.length > 4 && String.fromCharCodes(data, 0, 4) == 'BCFS') Uint8List.sublistView(data, 4)]) {
    final files = readBcfs(candidate);
    final score = files['score.gpif'] ?? files.entries.where((e) => e.key.endsWith('.gpif')).map((e) => e.value).firstOrNull;
    if (score != null) return score;
  }
  throw ImportException('No music found in this Guitar Pro 6 file');
}
