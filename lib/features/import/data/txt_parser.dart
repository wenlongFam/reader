import 'dart:io';

import '../../../core/util/charset.dart';

/// 章节（标题, 起始字节偏移）——不落正文，正文按需读取
class TxtChapterInfo {
  final String title;
  final int byteOffset;
  const TxtChapterInfo(this.title, this.byteOffset);
}

class TxtParseResult {
  final BookEncoding encoding;
  final List<TxtChapterInfo> chapters;
  final int totalBytes;
  const TxtParseResult({
    required this.encoding,
    required this.chapters,
    required this.totalBytes,
  });
}

/// TXT 分章解析器（MVP 投入重心）：
/// - 编码探测：BOM → UTF-8 严格校验 → GBK 兜底（见 charset.dart）
/// - 流式扫描：RandomAccessFile 分块读取，不把整本读进内存，100MB+ 全本可扫
/// - 偏移索引：章节只记录字节偏移入 SQLite，阅读时按偏移区间取正文
class TxtParser {
  /// 中文网文章节标题：第X章/节/卷/回/集/部（允许"第一章 标题（一）"等后缀）
  static final RegExp _cnChapter = RegExp(
    r'^[ \t\u3000]*第[零〇一二三四五六七八九十百千万两0-9０-９]+[章节卷回集部].{0,50}$',
  );

  /// 英文章节：Chapter N
  static final RegExp _enChapter = RegExp(
    r'^[ \t]*Chapter\s+\d+.*$',
    caseSensitive: false,
  );

  static const int _chunkSize = 1 << 20; // 每次读 1MB
  static const int _maxLineBytes = 4 << 20; // 单行超长保护（防无换行的病态文件撑爆内存）

  /// 扫描全文件，返回编码 + 章节偏移索引
  static Future<TxtParseResult> scanChapters(String path) async {
    final file = File(path);
    final totalBytes = await file.length();
    final raf = await file.open();
    try {
      final head = await raf.read(4096);
      final encoding = CharsetDetector.detect(head);
      final chapters = <TxtChapterInfo>[];
      var lastTitle = '';

      if (encoding == BookEncoding.utf16le ||
          encoding == BookEncoding.utf16be) {
        await _scanUtf16(raf, encoding, chapters, (t) => lastTitle = t);
      } else {
        await _scanByteOriented(raf, encoding, chapters, (t) => lastTitle = t);
      }
      return TxtParseResult(
        encoding: encoding,
        chapters: chapters,
        totalBytes: totalBytes,
      );
    } finally {
      await raf.close();
    }
  }

  /// UTF-8 / GBK：多字节序列不包含 0x0A，可直接在字节流上按 \n 切行，偏移精确
  static Future<void> _scanByteOriented(
    RandomAccessFile raf,
    BookEncoding encoding,
    List<TxtChapterInfo> out,
    void Function(String) onTitle,
  ) async {
    var carry = <int>[]; // 当前尚未结束的行的字节
    var lineStart = 0; // 当前行起始绝对字节偏移
    var bufBase = 0; // 本轮 buf[0] 的绝对偏移

    while (true) {
      final chunk = await raf.read(_chunkSize);
      if (chunk.isEmpty) break;
      final buf = <int>[...carry, ...chunk];
      bufBase = bufBase - carry.length; // 先回退旧 carry 占位，下面按 buf 重算
      bufBase = bufBase < 0 ? 0 : bufBase;

      var lineBegin = 0;
      for (var i = 0; i < buf.length; i++) {
        if (buf[i] == 0x0A) {
          var end = i;
          if (end > lineBegin && buf[end - 1] == 0x0D) end--; // 去 \r
          _handleLine(
              buf.sublist(lineBegin, end), lineStart, encoding, out, onTitle);
          lineBegin = i + 1;
          lineStart = bufBase + i + 1;
        } else if (i - lineBegin >= _maxLineBytes) {
          _handleLine(
              buf.sublist(lineBegin, i), lineStart, encoding, out, onTitle);
          lineBegin = i;
          lineStart = bufBase + i;
        }
      }
      carry = buf.sublist(lineBegin);
      bufBase = bufBase + buf.length;
    }
    if (carry.isNotEmpty) {
      _handleLine(carry, lineStart, encoding, out, onTitle);
    }
  }

  /// UTF-16：按码元流处理；每个码元恒占 2 字节，故字节偏移 = 2 × 码元下标（精确）
  static Future<void> _scanUtf16(
    RandomAccessFile raf,
    BookEncoding encoding,
    List<TxtChapterInfo> out,
    void Function(String) onTitle,
  ) async {
    await raf.setPosition(0);
    var carry = <int>[]; // 保留奇数尾字节
    var unitIndex = 0; // 已消费码元数
    var lineStartUnit = 0; // 当前行起始码元下标
    var lineUnits = <int>[];

    void flushLine() {
      var s = String.fromCharCodes(lineUnits);
      while (s.isNotEmpty && (s.codeUnitAt(s.length - 1) == 0x0D)) {
        s = s.substring(0, s.length - 1);
      }
      _handleTextLine(s, lineStartUnit * 2, out, onTitle);
      lineUnits = <int>[];
      lineStartUnit = unitIndex;
    }

    while (true) {
      final chunk = await raf.read(_chunkSize);
      if (chunk.isEmpty) break;
      final all = <int>[...carry, ...chunk];
      final usable = all.length - (all.length & 1); // 保留偶数对齐
      carry = usable < all.length ? all.sublist(usable) : const <int>[];
      final text = CharsetDecoder.decode(all.sublist(0, usable), encoding);
      for (final unit in text.codeUnits) {
        unitIndex++;
        if (unit == 0x0A) {
          flushLine();
        } else {
          lineUnits.add(unit);
        }
      }
    }
    if (lineUnits.isNotEmpty) flushLine();
  }

  static void _handleLine(
    List<int> rawBytes,
    int byteOffset,
    BookEncoding encoding,
    List<TxtChapterInfo> out,
    void Function(String) onTitle,
  ) {
    final line = CharsetDecoder.decode(rawBytes, encoding);
    _handleTextLine(line, byteOffset, out, onTitle);
  }

  static void _handleTextLine(
    String line,
    int byteOffset,
    List<TxtChapterInfo> out,
    void Function(String) onTitle,
  ) {
    final t = _cleanTitle(line);
    if (t == null) return;
    // 相邻重复标题去重（网文常见"第X章"单独占一行 + "第X章 标题"占一行的情况）
    if (out.isNotEmpty && out.last.title == t) return;
    out.add(TxtChapterInfo(t, byteOffset));
    onTitle(t);
  }

  /// 判定是否章节标题；是则返回清洗后的标题
  static String? _cleanTitle(String raw) {
    var t = raw.trim();
    // 去零宽字符与全角空格混排
    t = t.replaceAll(RegExp(r'[\u200B\u200C\u200D\uFEFF]'), '');
    if (t.isEmpty || t.length > 60) return null;
    if (_cnChapter.hasMatch(t) || _enChapter.hasMatch(t)) return t;
    return null;
  }

  /// 读取章节正文：[startByte, endByte) 字节区间，解码后去掉标题行
  static Future<String> readChapterText(
    String path,
    BookEncoding encoding,
    int startByte,
    int? endByte,
  ) async {
    final raf = await File(path).open();
    try {
      final total = await raf.length();
      final end = (endByte == null || endByte > total) ? total : endByte;
      final len = (end - startByte <= 0) ? 0 : end - startByte;
      await raf.setPosition(startByte);
      final bytes = await raf.read(len);
      var text = CharsetDecoder.decode(bytes, encoding);
      // 首行是章节标题本身，跳过
      final idx = text.indexOf('\n');
      if (idx >= 0) text = text.substring(idx + 1);
      return text;
    } finally {
      await raf.close();
    }
  }
}
