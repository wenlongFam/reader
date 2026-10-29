import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class EpubChapterInfo {
  final String title;
  final String plainText;
  const EpubChapterInfo(this.title, this.plainText);
}

class EpubParseResult {
  final String title;
  final String? author;
  final List<EpubChapterInfo> chapters;
  const EpubParseResult({
    required this.title,
    this.author,
    required this.chapters,
  });
}

/// EPUB 轻量解析（MVP 策略：EPUB 按"结构化 TXT"处理，只取纯文本，不渲染富文本/图片）：
/// zip 解包 → container.xml 找 OPF → 按 spine 顺序抽章节 → 剥标签取纯文本。
/// 章节正文全量入 SQLite（Chapters.content），阅读时不再触碰原文件。
class EpubParser {
  static Future<EpubParseResult> parse(String path) async {
    final bytes = await File(path).readAsBytes();
    final Archive archive = ZipDecoder().decodeBytes(bytes);

    // 1. META-INF/container.xml → OPF 路径
    final containerXml = _readStringOrNull(archive, 'META-INF/container.xml');
    if (containerXml == null) {
      throw const FormatException('EPUB 缺少 META-INF/container.xml');
    }
    final opfPath = XmlDocument.parse(containerXml)
        .findAllElements('rootfile')
        .map((e) => e.getAttribute('full-path') ?? '')
        .firstWhere(
          (p) => p.isNotEmpty,
          orElse: () => throw const FormatException('EPUB 缺少 rootfile'),
        );

    // 2. OPF → manifest(id→href) + spine 阅读顺序
    final opf = XmlDocument.parse(_readStringOrNull(archive, opfPath) ?? '');
    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';
    final manifest = <String, String>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) manifest[id] = href;
    }
    final spineHrefs = <String>[];
    for (final ref in opf.findAllElements('itemref')) {
      final href = manifest[ref.getAttribute('idref')];
      if (href != null) spineHrefs.add(_join(opfDir, href));
    }

    // 3. 元数据：书名 / 作者
    String titleOf(String tag, String fallback) {
      for (final e in opf.findAllElements(tag)) {
        final t = e.innerText.trim();
        if (t.isNotEmpty) return t;
      }
      return fallback;
    }

    // 4. 按 spine 顺序抽取章节纯文本
    final chapters = <EpubChapterInfo>[];
    for (final href in spineHrefs) {
      final content = _readStringOrNull(archive, href);
      if (content == null) continue;
      final XmlDocument doc;
      try {
        doc = XmlDocument.parse(content);
      } on XmlException {
        continue; // 坏章节跳过，不让整本导入失败
      }
      String chapterTitle = '';
      for (final t in doc.findAllElements('title')) {
        final v = t.innerText.trim();
        if (v.isNotEmpty) {
          chapterTitle = v;
          break;
        }
      }
      if (chapterTitle.isEmpty) {
        for (final h in doc.findAllElements('h1')) {
          final v = h.innerText.trim();
          if (v.isNotEmpty) {
            chapterTitle = v;
            break;
          }
        }
      }
      final body = doc.findAllElements('body').map((b) => b.innerText).join('\n');
      chapters.add(EpubChapterInfo(
        chapterTitle.isEmpty ? '第${chapters.length + 1}节' : chapterTitle,
        _clean(body),
      ));
    }

    if (chapters.isEmpty) throw const FormatException('EPUB 内未找到可读章节');
    return EpubParseResult(
      title: titleOf('title', ''),
      author: titleOf('creator', '') ,
      chapters: chapters,
    );
  }

  /// 压缩 HTML 文本为干净段落：按行去空白、空行分段
  static String _clean(String s) {
    return s
        .replaceAll('\r', '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n\n');
  }

  /// 相对路径拼接 + URL 解码（EPUB href 常含 %20 等转义）
  static String _join(String dir, String href) {
    final raw = (href.startsWith('/') ? href.substring(1) : dir + href);
    return Uri.decodeComponent(raw.replaceAll('\\', '/'));
  }

  static String? _readStringOrNull(Archive archive, String name) {
    for (final f in archive.files) {
      if (f.name == name || f.name.endsWith('/$name')) {
        return f.content is List<int> ? String.fromCharCodes(f.content as List<int>) : null;
      }
    }
    return null;
  }
}
