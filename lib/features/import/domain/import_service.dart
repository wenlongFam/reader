import 'dart:io';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/util/charset.dart';
import '../data/epub_parser.dart';
import '../data/txt_parser.dart';

class ImportResult {
  final int bookId;
  final String title;
  final int chapterCount;
  const ImportResult({
    required this.bookId,
    required this.title,
    required this.chapterCount,
  });
}

/// 导入服务：文件 → 解析 → 入库（Book + Chapter 索引一次事务写入）
class ImportService {
  final AppDatabase _db;
  ImportService(this._db);

  Future<ImportResult> importFile(String path) async {
    final ext = path.toLowerCase().split('.').last;
    if (ext == 'epub') return _importEpub(path);
    return _importTxt(path); // txt 及其他文本格式一律按 TXT 处理
  }

  Future<ImportResult> _importTxt(String path) async {
    final result = await TxtParser.scanChapters(path);
    final title = _fileNameTitle(path);
    final chapters = result.chapters.isEmpty
        ? [const TxtChapterInfo('正文', 0)] // 无规律分章降级：整本一个章节
        : result.chapters;

    return _db.transaction(() async {
      final bookId = await _db.into(_db.books).insert(
            BooksCompanion.insert(
              title: title,
              format: 'txt',
              filePath: path,
              encoding: Value(result.encoding.name),
              totalBytes: Value(result.totalBytes),
            ),
          );
      for (var i = 0; i < chapters.length; i++) {
        await _db.into(_db.chapters).insert(
              ChaptersCompanion.insert(
                bookId: bookId,
                seq: i,
                title: chapters[i].title,
                byteOffset: chapters[i].byteOffset,
              ),
            );
      }
      return ImportResult(
        bookId: bookId,
        title: title,
        chapterCount: chapters.length,
      );
    });
  }

  Future<ImportResult> _importEpub(String path) async {
    final result = await EpubParser.parse(path);
    final title = result.title.isNotEmpty ? result.title : _fileNameTitle(path);

    return _db.transaction(() async {
      final bookId = await _db.into(_db.books).insert(
            BooksCompanion.insert(
              title: title,
              author: Value(result.author),
              format: 'epub',
              filePath: path,
              encoding: const Value('utf8'),
            ),
          );
      for (var i = 0; i < result.chapters.length; i++) {
        await _db.into(_db.chapters).insert(
              ChaptersCompanion.insert(
                bookId: bookId,
                seq: i,
                title: result.chapters[i].title,
                byteOffset: 0,
                content: Value(result.chapters[i].plainText),
              ),
            );
      }
      return ImportResult(
        bookId: bookId,
        title: title,
        chapterCount: result.chapters.length,
      );
    });
  }

  /// 文件名 → 书名：去扩展名，去常见网文广告后缀
  static String _fileNameTitle(String path) {
    var name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]|【.*?】|（.*?）'), '')
        .trim();
  }
}

/// 阅读器取正文入口：EPUB 读缓存字段，TXT 按字节偏移读原文件
Future<String> readChapterContent(
  AppDatabase db, {
  required int bookId,
  required int seq,
}) async {
  final chapter = await (db.select(db.chapters)
        ..where((c) => c.bookId.equals(bookId) & c.seq.equals(seq)))
      .getSingleOrNull();
  if (chapter == null) return '';
  if (chapter.content != null) return chapter.content!;

  final book = await (db.select(db.books)
        ..where((b) => b.id.equals(bookId)))
      .getSingleOrNull();
  if (book == null) return '';

  final next = await (db.select(db.chapters)
        ..where((c) => c.bookId.equals(bookId) & c.seq.equals(seq + 1)))
      .getSingleOrNull();
  final encoding = BookEncoding.values
      .firstWhere((e) => e.name == (book.encoding ?? 'gbk'),
          orElse: () => BookEncoding.gbk);
  return TxtParser.readChapterText(
    book.filePath,
    encoding,
    chapter.byteOffset,
    next?.byteOffset,
  );
}
