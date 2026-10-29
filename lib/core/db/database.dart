import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// 书籍表：导入时一次性写入的元数据
class Books extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()(); // 书名（取文件名或 EPUB 元数据）
  TextColumn get author => text().nullable()();
  TextColumn get format => text()(); // 'txt' | 'epub'
  TextColumn get filePath => text()(); // 原文件路径（正文按需读取）
  TextColumn get encoding => text().nullable()(); // txt 编码标记，如 gbk/utf8
  IntColumn get totalBytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get importedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastReadAt => dateTime().nullable()(); // 书库按此排序
}

/// 章节索引：只存标题 + 起始字节偏移，正文按需读取（支持 100MB+ 全本秒开）
class Chapters extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId => integer().references(Books, #id)();
  IntColumn get seq => integer()(); // 章节序号，从 0 开始
  TextColumn get title => text()();
  IntColumn get byteOffset => integer()(); // 章节正文起始字节偏移
  TextColumn get content => text().nullable()(); // EPUB 章节正文缓存；TXT 为空（按 byteOffset 从原文件读取）
}

/// 阅读进度：一本书一条（bookId 为主键），粒度到章节内字符偏移
class ReadingProgresses extends Table {
  IntColumn get bookId => integer()();
  IntColumn get chapterIndex => integer()();
  IntColumn get charOffset => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {bookId};
}

/// 书签
class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId => integer().references(Books, #id)();
  IntColumn get chapterIndex => integer()();
  IntColumn get charOffset => integer()();
  TextColumn get excerpt => text()(); // 书签所在位置摘句
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Books, Chapters, ReadingProgresses, Bookmarks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'wenlong_reader.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// 全局数据库单例
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
