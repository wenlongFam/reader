import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/database.dart';
import '../../import/domain/import_service.dart';

/// 书库流：按最近阅读时间倒序
final booksProvider = StreamProvider<List<Book>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.books)
        ..orderBy([(b) => OrderingTerm.desc(b.lastReadAt)]))
      .watch();
});

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('书库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('书库加载失败：$e')),
        data: (list) {
          if (list.isEmpty) return const _EmptyHint();
          return RefreshIndicator(
            onRefresh: () async {},
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final book = list[i];
                return ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${book.format.toUpperCase()} · ${book.totalBytes == 0 ? '—' : _fmtSize(book.totalBytes)}'
                    '${book.lastReadAt == null ? '' : ' · ${_fmtTime(book.lastReadAt!)}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onTap: () => context.push('/reader/${book.id}'),
                  onLongPress: () => _confirmDelete(context, ref, book),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.upload_file),
        label: const Text('导入书籍'),
        onPressed: () => _pickAndImport(context, ref),
      ),
    );
  }

  Future<void> _pickAndImport(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'epub'],
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ImportService(ref.read(appDatabaseProvider))
          .importFile(path);
      messenger.showSnackBar(SnackBar(
        content: Text('《${result.title}》导入成功，共 ${result.chapterCount} 章'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Book book) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定从书库移除《${book.title}》吗？\n（不会删除原文件）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = ref.read(appDatabaseProvider);
              await db.transaction(() async {
                await (db.delete(db.chapters)
                      ..where((c) => c.bookId.equals(book.id)))
                    .go();
                await (db.delete(db.readingProgresses)
                      ..where((p) => p.bookId.equals(book.id)))
                    .go();
                await (db.delete(db.bookmarks)
                      ..where((m) => m.bookId.equals(book.id)))
                    .go();
                await (db.delete(db.books)..where((b) => b.id.equals(book.id)))
                    .go();
              });
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  static String _fmtSize(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)}MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)}KB';
    return '$bytes B';
  }

  static String _fmtTime(DateTime t) =>
      '${t.month}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_stories_outlined,
              size: 72, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text('还没有书，点右下角导入 TXT / EPUB',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
