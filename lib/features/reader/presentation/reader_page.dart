import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/theme/reading_theme.dart';
import '../../import/domain/import_service.dart';

/// 阅读器 M0 骨架：整章滚动展示 + 章节切换 + 进度记录。
/// M2 将替换为 TextPainter 分页引擎（覆盖式翻页 + 滚动双模式），本页结构保留为容器。
class ReaderPage extends ConsumerStatefulWidget {
  final int bookId;
  const ReaderPage({super.key, required this.bookId});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  Book? _book;
  List<Chapter> _chapters = [];
  int _chapterIndex = 0;
  String _content = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    try {
      final book = await (db.select(db.books)
            ..where((b) => b.id.equals(widget.bookId)))
          .getSingleOrNull();
      if (book == null) {
        setState(() {
          _loading = false;
          _error = '书籍不存在（id=${widget.bookId}）';
        });
        return;
      }
      final chapters = await (db.select(db.chapters)
            ..where((c) => c.bookId.equals(widget.bookId))
            ..orderBy([(c) => OrderingTerm.asc(c.seq)]))
          .get();
      final progress = await (db.select(db.readingProgresses)
            ..where((p) => p.bookId.equals(widget.bookId)))
          .getSingleOrNull();
      final index =
          (progress?.chapterIndex ?? 0).clamp(0, chapters.isEmpty ? 0 : chapters.length - 1);

      setState(() {
        _book = book;
        _chapters = chapters;
        _chapterIndex = index;
      });
      await _loadChapter(index);

      // 恢复阅读：更新 lastReadAt
      await (db.update(db.books)..where((b) => b.id.equals(widget.bookId)))
          .write(BooksCompanion(lastReadAt: Value(DateTime.now())));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载失败：$e';
        });
      }
    }
  }

  Future<void> _loadChapter(int index) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await readChapterContent(
        ref.read(appDatabaseProvider),
        bookId: widget.bookId,
        seq: index,
      );
      setState(() {
        _chapterIndex = index;
        _content = text;
        _loading = false;
      });
      await _saveProgress();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '章节加载失败：$e';
        });
      }
    }
  }

  Future<void> _saveProgress() async {
    final db = ref.read(appDatabaseProvider);
    await db.into(db.readingProgresses).insertOnConflictUpdate(
          ReadingProgressesCompanion.insert(
            bookId: widget.bookId,
            chapterIndex: _chapterIndex,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = kReadingThemes[1]; // 默认米黄；M3 接设置面板
    final chapterTitle =
        _chapters.isEmpty ? '' : _chapters[_chapterIndex].title;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        foregroundColor: theme.text,
        elevation: 0,
        title: Text(
          chapterTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 15, color: theme.secondaryText),
        ),
        actions: [
          IconButton(
            tooltip: '上一章',
            icon: const Icon(Icons.chevron_left),
            onPressed: _chapterIndex > 0
                ? () => _loadChapter(_chapterIndex - 1)
                : null,
          ),
          IconButton(
            tooltip: '下一章',
            icon: const Icon(Icons.chevron_right),
            onPressed: _chapterIndex < _chapters.length - 1
                ? () => _loadChapter(_chapterIndex + 1)
                : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Text(
                      _content,
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.7,
                        color: theme.text,
                      ),
                    ),
                  ),
                ),
    );
  }
}
