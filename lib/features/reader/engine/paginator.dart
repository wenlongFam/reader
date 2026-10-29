import 'package:flutter/painting.dart';

/// 一页 = 章节文本的 [start, end) 字符区间。
/// 进度粒度即字符偏移：续读时找到包含该偏移的页即可精确还原。
class PageSlice {
  final int start;
  final int end;
  const PageSlice(this.start, this.end);

  bool contains(int charOffset) => charOffset >= start && charOffset < end;
}

/// 分页引擎：把章节纯文本按当前排版样式与视口大小切成页面。
///
/// 实现：对每页用 TextPainter 测量高度，二分查找能塞进一页的最大字符区间。
/// 章节内单线程执行；结果随字号/视口变化由阅读器触发整章重排并按偏移回位。
class Paginator {
  /// 将 [text] 按 [style] 排版、适配 [viewport]（正文可用区域），返回页序列。
  static List<PageSlice> paginate(
    String text,
    TextStyle style,
    Size viewport,
  ) {
    if (text.isEmpty || viewport.width <= 0 || viewport.height <= 0) {
      return const [PageSlice(0, 0)];
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    final slices = <PageSlice>[];
    var start = 0;

    while (start < text.length) {
      // 跳过页首空白（章节结尾的连续换行不占新页）
      while (start < text.length && _isWhitespace(text.codeUnitAt(start))) {
        start++;
      }
      if (start >= text.length) break;

      // 剩余全部能放进一页 → 收尾
      if (_fits(tp, text, start, text.length, style, viewport)) {
        slices.add(PageSlice(start, text.length));
        break;
      }

      // 二分：找最大 end 使 [start, end) 排版高度 ≤ 视口高
      var lo = start + 1;
      var hi = text.length;
      while (hi - lo > 1) {
        final mid = (lo + hi) >> 1;
        if (_fits(tp, text, start, mid, style, viewport)) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      // 极端小视口下一行都放不下时，至少推进 1 字符防止死循环
      final end = lo > start ? lo : start + 1;
      slices.add(PageSlice(start, end));
      start = end;
    }

    tp.dispose();
    return slices;
  }

  /// 找到包含 [charOffset] 的页下标（用于续读定位）
  static int pageIndexFor(List<PageSlice> pages, int charOffset) {
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].contains(charOffset)) return i;
    }
    return 0;
  }

  static bool _fits(TextPainter tp, String text, int start, int end,
      TextStyle style, Size viewport) {
    tp.text = TextSpan(text: text.substring(start, end), style: style);
    tp.layout(maxWidth: viewport.width);
    return tp.height <= viewport.height;
  }

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0A ||
      codeUnit == 0x0D || codeUnit == 0x3000;
}
