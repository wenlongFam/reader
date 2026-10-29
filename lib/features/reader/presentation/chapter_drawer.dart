import 'package:flutter/material.dart';

/// 章节目录抽屉（F6）：底部上滑弹出，当前章节高亮，点击跳转
Future<void> showChapterDrawer(
  BuildContext context, {
  required List<String> titles,
  required int current,
  required ValueChanged<int> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ChapterSheet(
      titles: titles,
      current: current,
      onSelected: onSelected,
    ),
  );
}

class _ChapterSheet extends StatelessWidget {
  final List<String> titles;
  final int current;
  final ValueChanged<int> onSelected;

  const _ChapterSheet({
    required this.titles,
    required this.current,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text('目录 · 共 ${titles.length} 章',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: titles.length,
                itemExtent: 48,
                itemBuilder: (context, i) {
                  final isCurrent = i == current;
                  return ListTile(
                    dense: true,
                    selected: isCurrent,
                    selectedTileColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    title: Text(
                      titles[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        fontWeight:
                            isCurrent ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      onSelected(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
