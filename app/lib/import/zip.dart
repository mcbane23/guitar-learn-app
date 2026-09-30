/// A small reader for zip archives (.gp and .mxl files are zips).
library;

import 'dart:io';
import 'dart:typed_data';

import 'score.dart';

class ZipEntry {
  ZipEntry._(this.name, this._bytes, this._offset, this._size, this._method);

  final String name;
  final Uint8List _bytes;
  final int _offset;
  final int _size;
  final int _method;

  /// The file's contents, inflated if needed.
  Uint8List read() {
    final data = Uint8List.sublistView(_bytes, _offset, _offset + _size);
    if (_method == 0) return data;
    if (_method == 8) return Uint8List.fromList(ZLibDecoder(raw: true).convert(data));
    throw ImportException('Unsupported compression in zip file');
  }
}

/// Lists the files of a zip archive. Throws [ImportException] when [bytes]
/// is not a zip file.
List<ZipEntry> readZip(Uint8List bytes) {
  if (bytes.length < 22 || bytes[0] != 0x50 || bytes[1] != 0x4B) throw ImportException('Not a zip file');
  final d = ByteData.sublistView(bytes);
  // End of central directory record, searched from the end.
  var eocd = -1;
  for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 22 - 65535; i--) {
    if (d.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw ImportException('Damaged zip file');
  final count = d.getUint16(eocd + 10, Endian.little);
  var p = d.getUint32(eocd + 16, Endian.little);
  final entries = <ZipEntry>[];
  for (var i = 0; i < count; i++) {
    if (p + 46 > bytes.length || d.getUint32(p, Endian.little) != 0x02014b50) break;
    final method = d.getUint16(p + 10, Endian.little);
    final compressedSize = d.getUint32(p + 20, Endian.little);
    final nameLength = d.getUint16(p + 28, Endian.little);
    final extraLength = d.getUint16(p + 30, Endian.little);
    final commentLength = d.getUint16(p + 32, Endian.little);
    final local = d.getUint32(p + 42, Endian.little);
    final name = String.fromCharCodes(bytes, p + 46, p + 46 + nameLength);
    if (local + 30 <= bytes.length && d.getUint32(local, Endian.little) == 0x04034b50) {
      final localName = d.getUint16(local + 26, Endian.little);
      final localExtra = d.getUint16(local + 28, Endian.little);
      final start = local + 30 + localName + localExtra;
      if (start + compressedSize <= bytes.length) {
        entries.add(ZipEntry._(name, bytes, start, compressedSize, method));
      }
    }
    p += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}
