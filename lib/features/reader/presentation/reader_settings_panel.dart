import 'package:flutter/material.dart';

import '../../../core/theme/reading_theme.dart';
import '../logic/reader_prefs.dart';

/// 阅读设置面板（F4）：模式切换 / 字号 / 主题 / 亮度，即改即见
class ReaderSettingsPanel extends StatelessWidget {
  final ReaderPrefs prefs;
  final ValueChanged<ReaderPrefs> onChanged;

  const ReaderSettingsPanel({
    super.key,
    required this.prefs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 阅读模式
          Row(
            children: [
              const Icon(Icons.auto_stories_outlined, size: 20),
              const SizedBox(width: 8),
              Text('阅读模式', style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              SegmentedButton<ReadingMode>(
                segments: const [
                  ButtonSegment(value: ReadingMode.page, label: Text('翻页')),
                  ButtonSegment(value: ReadingMode.scroll, label: Text('滚动')),
                ],
                selected: {prefs.mode},
                onSelectionChanged: (s) =>
                    onChanged(prefs.copyWith(mode: s.first)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 字号
          Row(
            children: [
              const Icon(Icons.text_fields_outlined, size: 20),
              const SizedBox(width: 8),
              const Text('A-'),
              Expanded(
                child: Slider(
                  value: prefs.fontSize,
                  min: 14,
                  max: 28,
                  divisions: 14,
                  label: prefs.fontSize.toStringAsFixed(0),
                  onChanged: (v) => onChanged(prefs.copyWith(fontSize: v)),
                ),
              ),
              const Text('A+'),
            ],
          ),
          const SizedBox(height: 4),
          // 主题
          Row(
            children: [
              const Icon(Icons.palette_outlined, size: 20),
              const SizedBox(width: 8),
              ...List.generate(kReadingThemes.length, (i) {
                final t = kReadingThemes[i];
                final selected = i == prefs.themeIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onChanged(prefs.copyWith(themeIndex: i)),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: t.background,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade400,
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        t.name,
                        style: TextStyle(
                            fontSize: 12, color: t.secondaryText),
                      ),
                    ),
                  ),
                );
              }),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 4),
          // 亮度
          Row(
            children: [
              const Icon(Icons.brightness_6_outlined, size: 20),
              Expanded(
                child: Slider(
                  value: prefs.brightness,
                  min: 0.3,
                  max: 1.0,
                  onChanged: (v) => onChanged(prefs.copyWith(brightness: v)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
