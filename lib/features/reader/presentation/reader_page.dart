import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/database.dart';
import '../../../core/theme/reading_theme.dart';
import '../../import/domain/import_service.dart';
import '../engine/paginator.dart';
import '../logic/reader_prefs.dart';
import 'chapter_drawer.dart';
import 'reader_settings_panel.dart';

/// 阅读器（M2/M3）：
/// - 翻页模式：分页引擎切片 + PageView，左右分区点击翻页，中键呼出菜单
/// - 滚动模式：整章连续滚动
/// - 进度：(章节, 章节内字符偏移) 四时机落库，续读精确回页
/// - 菜单：顶栏（返回/书签/目录）+ 底栏（切章/设置面板）
class ReaderPage extends ConsumerStatefulWidget {
  final int bookId;
  const ReaderPage({super.key, required this.bookId});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  Book? _book;
  List<Chapter> _chapters = const [];
  int _chapterIndex = 0;
  String _content = '';
  List<PageSlice> _pages = const [];
  Size? _paginatedViewport;
  int _pendingRestoreOffset = 0;
  double? _pendingScrollRatio;
  bool _jumpToEnd = false;

  bool _loading = true;
  String? _error;
  bool _menuVisible = false;

  PageController? _pageController;
  ScrollController? _scrollController;
  int _currentPage = 0;
  double _lastSavedRatio = 0;

  AppDatabase get _db => ref.read(appDatabaseProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // 兜底保存进度
    _saveProgress();
    _pageController?.dispose();
    _scrollController?.dispose();
    super.dispose();
  }

  // ---------- 数据加载 ----------

  Future<void> _load() async {
    try {
      final book = await ( _db.select(_db.books)
            ..where((b) => b.id.equals(widget.bookId)))
          .getSingleOrNull();
      if (book == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = '书籍不存在（id=${widget.bookId}）';
          });
        }
        return;
      }
      final chapters = await (_db.select(_db.chapters)
            ..where((c) => c.bookId.equals(widget.bookId))
            ..orderBy([(c) => OrderingTerm.asc(c.seq)]))
          .get();
      final progress = await (_db.select(_db.readingProgresses)
            ..where((p) => p.bookId.equals(widget.bookId)))
          .getSingleOrNull();
      final index = (progress?.chapterIndex ?? 0)
          .clamp(0, chapters.isEmpty ? 0 : chapters.length - 1)
          .toInt();

      _book = book;
      _chapters = chapters;
      _chapterIndex = index;
      _pendingRestoreOffset = progress?.charOffset ?? 0;
      await _loadContent(index, restoreOffset: _pendingRestoreOffset);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载失败：$e';
        });
      }
    }
  }

  Future<void> _loadChapter(int index,
      {int? restoreOffset, bool jumpToEnd = false}) async {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _loading = true;
      _error = null;
      _menuVisible = false;
      _jumpToEnd = jumpToEnd;
      _pendingRestoreOffset = restoreOffset ?? 0;
      _pages = const [];
      _paginatedViewport = null; // 触发 LayoutBuilder 重新分页
    });
    await _loadContent(index, restoreOffset: restoreOffset ?? 0);
  }

  Future<void> _loadContent(int index, {required int restoreOffset}) async {
    try {
      final text = await readChapterContent(_db,
          bookId: widget.bookId, seq: index);
      if (!mounted) return;
      setState(() {
        _chapterIndex = index;
        _content = text;
        _loading = false;
        _lastSavedRatio = 0;
      });
      await _saveProgress(offset: restoreOffset, chapterIndex: index);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '章节加载失败：$e';
        });
      }
    }
  }

  // ---------- 分页 ----------

  void _paginate(Size vp, {int? restoreOffset, bool jumpToEnd = false}) {
    final prefs = ref.read(readerPrefsProvider);
    _pages = Paginator.paginate(_content, _bodyStyle(prefs), vp);
    _paginatedViewport = vp;

    final restore = restoreOffset ?? _pendingRestoreOffset;
    _pendingRestoreOffset = 0;
    final jumpEnd = jumpToEnd || _jumpToEnd;
    _jumpToEnd = false;

    if (prefs.mode == ReadingMode.page) {
      final idx = jumpEnd
          ? (_pages.isEmpty ? 0 : _pages.length - 1)
          : Paginator.pageIndexFor(_pages, restore);
      _currentPage = idx;
      _swapPageController(PageController(initialPage: idx));
    } else {
      if (jumpEnd && _content.isNotEmpty) {
        _pendingScrollRatio = 1.0;
      } else if (restore > 0 && _content.isNotEmpty) {
        _pendingScrollRatio = restore / _content.length;
      }
      _swapScrollController(ScrollController()..addListener(_onScroll));
    }
  }

  /// 换控制器：旧控制器等旧 widget 卸载后再释放，避免 build 期间 dispose 报错
  void _swapPageController(PageController next) {
    final old = _pageController;
    _pageController = next;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _swapScrollController(ScrollController next) {
    final old = _scrollController;
    _scrollController = next;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _onScroll() {
    final c = _scrollController;
    if (c == null || !c.hasClients || _content.isEmpty) return;
    final max = c.position.maxScrollExtent;
    if (max <= 0) return;
    final ratio = (c.offset / max).clamp(0.0, 1.0);
    // 节流：滚动超过 2% 才落库，避免高频写 SQLite
    if ((ratio - _lastSavedRatio).abs() > 0.02) {
      _lastSavedRatio = ratio;
      _saveProgress(
          offset: (ratio * _content.length).round(), chapterIndex: _chapterIndex);
    }
  }

  int _currentStartOffsetFor(ReadingMode mode) {
    if (mode == ReadingMode.page) {
      final i = (_pageController?.hasClients ?? false)
          ? (_pageController!.page?.round() ?? _currentPage)
          : _currentPage;
      if (i >= 0 && i < _pages.length) return _pages[i].start;
      return 0;
    }
    final c = _scrollController;
    if ((c?.hasClients ?? false) && _content.isNotEmpty) {
      final max = c!.position.maxScrollExtent;
      final r = max > 0 ? (c.offset / max).clamp(0.0, 1.0) : 0.0;
      return (r * _content.length).round();
    }
    return 0;
  }

  // ---------- 进度 ----------

  Future<void> _saveProgress({int? offset, int? chapterIndex}) async {
    try {
      final ch = chapterIndex ?? _chapterIndex;
      final off = offset ?? _currentStartOffsetFor(
          ref.read(readerPrefsProvider).mode);
      await _db.into(_db.readingProgresses).insertOnConflictUpdate(
            ReadingProgressesCompanion.insert(
              bookId: Value(widget.bookId),
              chapterIndex: ch,
              charOffset: Value(off),
              updatedAt: Value(DateTime.now()),
            ),
          );
      await (_db.update(_db.books)..where((b) => b.id.equals(widget.bookId)))
          .write(BooksCompanion(lastReadAt: Value(DateTime.now())));
    } catch (_) {
      // 进度落库失败不打断阅读
    }
  }

  // ---------- 交互 ----------

  void _onTap(double dx) {
    if (_menuVisible) {
      setState(() => _menuVisible = false);
      return;
    }
    if (ref.read(readerPrefsProvider).mode == ReadingMode.page) {
      final w = MediaQuery.of(context).size.width;
      if (dx < w * 0.3) {
        _pageStep(-1);
        return;
      }
      if (dx > w * 0.7) {
        _pageStep(1);
        return;
      }
    }
    setState(() => _menuVisible = true);
  }

  void _pageStep(int delta) {
    final ctrl = _pageController;
    if (ctrl == null || _pages.isEmpty) return;
    final cur = ctrl.hasClients ? (ctrl.page?.round() ?? 0) : _currentPage;
    final target = cur + delta;
    if (target >= 0 && target < _pages.length) {
      ctrl.animateToPage(target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut);
    } else if (target < 0) {
      _loadChapter(_chapterIndex - 1, jumpToEnd: true);
    } else {
      _loadChapter(_chapterIndex + 1);
    }
  }

  Future<void> _addBookmark() async {
    final prefs = ref.read(readerPrefsProvider);
    final off = _currentStartOffsetFor(prefs.mode)
        .clamp(0, _content.isEmpty ? 0 : _content.length - 1)
        .toInt();
    final excerpt = _content.isEmpty
        ? (_chapters.isEmpty ? '' : _chapters[_chapterIndex].title)
        : _content
            .substring(off, (_content.length < off + 40)
                ? _content.length
                : off + 40)
            .replaceAll('\n', ' ');
    await _db.into(_db.bookmarks).insert(BookmarksCompanion.insert(
          bookId: widget.bookId,
          chapterIndex: _chapterIndex,
          charOffset: off,
          excerpt: excerpt.trim(),
        ));
    if (mounted) {
      setState(() => _menuVisible = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加书签'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _showBookmarks() async {
    final list = await (_db.select(_db.bookmarks)
          ..where((m) => m.bookId.equals(widget.bookId))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
        .get();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('书签 · ${list.length}',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('还没有书签')),
              ),
            for (final bm in list)
              ListTile(
                leading: const Icon(Icons.bookmark_outlined),
                title: Text(bm.excerpt, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    _chapterTitle(bm.chapterIndex),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.bodySmall),
                onTap: () {
                  Navigator.pop(ctx);
                  _loadChapter(bm.chapterIndex, restoreOffset: bm.charOffset);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _chapterTitle(int index) {
    if (index < 0 || index >= _chapters.length) return '未知章节';
    return _chapters[index].title;
  }

  void _showToc() {
    setState(() => _menuVisible = false);
    showChapterDrawer(
      context,
      titles: _chapters.map((c) => c.title).toList(),
      current: _chapterIndex,
      onSelected: (i) => _loadChapter(i),
    );
  }

  // ---------- 构建 ----------

  TextStyle _bodyStyle(ReaderPrefs p) {
    final t = kReadingThemes[p.themeIndex.clamp(0, kReadingThemes.length - 1)];
    return TextStyle(fontSize: p.fontSize, height: 1.7, color: t.text);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(readerPrefsProvider);

    // 字号/模式变化：按当前阅读位置整章重排并回位
    ref.listen<ReaderPrefs>(readerPrefsProvider, (prev, next) {
      if (prev == null || _content.isEmpty) return;
      if (prev.fontSize != next.fontSize || prev.mode != next.mode) {
        final vp = _paginatedViewport;
        if (vp != null) {
          _paginate(vp, restoreOffset: _currentStartOffsetFor(prev.mode));
          setState(() {});
        }
      }
    });

    final theme = kReadingThemes[prefs.themeIndex.clamp(0, kReadingThemes.length - 1)];

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          // 正文渲染区：左右 20 / 上下 16 内边距，与分页测量保持一致
          final vp = Size(
            (constraints.maxWidth - 40).clamp(1.0, double.infinity).toDouble(),
            (constraints.maxHeight - 32).clamp(1.0, double.infinity).toDouble(),
          );
          if (_paginatedViewport != vp) {
            _paginate(vp);
          }

          Widget body;
          if (_loading) {
            body = const Center(child: CircularProgressIndicator());
          } else if (_error != null) {
            body = Center(child: Text(_error!, textAlign: TextAlign.center));
          } else if (prefs.mode == ReadingMode.page) {
            body = _buildPageView(prefs);
          } else {
            body = _buildScrollView(prefs);
          }

          return Stack(
            children: [
              body,
              // 亮度罩（夜间调暗）
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black
                        .withOpacity((1 - prefs.brightness)
                            .clamp(0.0, 0.7)
                            .toDouble()),
                  ),
                ),
              ),
              if (_menuVisible) _buildMenu(),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildPageView(ReaderPrefs prefs) {
    if (_pages.isEmpty) return const SizedBox.expand();
    return PageView.builder(
      controller: _pageController,
      itemCount: _pages.length,
      onPageChanged: (i) {
        _currentPage = i;
        _saveProgress(offset: _pages[i].start);
      },
      itemBuilder: (context, i) {
        final slice = _pages[i];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _onTap(d.globalPosition.dx),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Text(
              _content.substring(slice.start, slice.end),
              style: _bodyStyle(prefs),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScrollView(ReaderPrefs prefs) {
    // 滚动模式恢复：等布局完成后跳到目标比例位置
    final ratio = _pendingScrollRatio;
    if (ratio != null) {
      _pendingScrollRatio = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _scrollController;
        if (c != null && c.hasClients) {
          c.jumpTo(c.position.maxScrollExtent * ratio);
        }
      });
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _onTap(d.globalPosition.dx),
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Text(_content, style: _bodyStyle(prefs)),
      ),
    );
  }

  Widget _buildMenu() {
    final prefs = ref.watch(readerPrefsProvider);
    final barColor = Theme.of(context).colorScheme.surface;
    return Stack(
      children: [
        // 遮罩：点击空白收起菜单
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _menuVisible = false),
            child: Container(color: Colors.black38),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              // 顶栏
              Container(
                color: barColor,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        _book?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '添加书签',
                      icon: const Icon(Icons.bookmark_add_outlined),
                      onPressed: _addBookmark,
                    ),
                    IconButton(
                      tooltip: '书签列表',
                      icon: const Icon(Icons.bookmarks_outlined),
                      onPressed: _showBookmarks,
                    ),
                    IconButton(
                      tooltip: '目录',
                      icon: const Icon(Icons.menu_book_outlined),
                      onPressed: _showToc,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // 底栏：切章 + 页码 + 设置面板
              Container(
                color: barColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: _chapterIndex > 0
                              ? () => _loadChapter(_chapterIndex - 1)
                              : null,
                          child: const Text('上一章'),
                        ),
                        Expanded(
                          child: Text(
                            prefs.mode == ReadingMode.page && _pages.isNotEmpty
                                ? '${_currentPage + 1} / ${_pages.length} 页'
                                : _chapterTitle(_chapterIndex),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: _chapterIndex < _chapters.length - 1
                              ? () => _loadChapter(_chapterIndex + 1)
                              : null,
                          child: const Text('下一章'),
                        ),
                      ],
                    ),
                    ReaderSettingsPanel(
                      prefs: prefs,
                      onChanged: (p) =>
                          ref.read(readerPrefsProvider.notifier).update(p),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
