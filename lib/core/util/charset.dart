import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

/// 书籍文件编码标记
enum BookEncoding { utf8, utf16le, utf16be, gbk }

/// 编码探测：BOM 优先 → UTF-8 严格校验 → GBK 兜底。
/// 国内网文 TXT 绝大多数是 GBK（无 BOM、非 UTF-8），此兜底顺序覆盖 95%+ 场景。
class CharsetDetector {
  /// [head] 为文件头部字节（建议 >= 4KB，提高 UTF-8 误判为 GBK 的门槛）。
  static BookEncoding detect(Uint8List head) {
    final b = head;
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      return BookEncoding.utf8;
    }
    if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
      return BookEncoding.utf16le;
    }
    if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
      return BookEncoding.utf16be;
    }
    if (_isValidUtf8(b)) return BookEncoding.utf8;
    return BookEncoding.gbk;
  }

  static bool _isValidUtf8(List<int> bytes) {
    try {
      utf8.decode(bytes, allowMalformed: false);
      return true;
    } on FormatException {
      return false;
    }
  }
}

/// 解码工具：按编码把字节流转为文本
class CharsetDecoder {
  static String decode(List<int> bytes, BookEncoding encoding) {
    switch (encoding) {
      case BookEncoding.utf8:
        // 去掉 BOM 后解码；allowMalformed 保证脏数据不崩溃（M1 提供手动切编码重解）
        var start = 0;
        if (bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF) {
          start = 3;
        }
        return utf8.decode(bytes.sublist(start), allowMalformed: true);
      case BookEncoding.utf16le:
      case BookEncoding.utf16be:
        return _decodeUtf16(bytes, encoding);
      case BookEncoding.gbk:
        return gbk.decode(bytes);
    }
  }

  static String _decodeUtf16(List<int> bytes, BookEncoding encoding) {
    final little = encoding == BookEncoding.utf16le;
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(little
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }
}
