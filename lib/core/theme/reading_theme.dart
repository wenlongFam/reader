import 'package:flutter/material.dart';

/// 阅读主题 Token：MVP 三套预设（白 / 米黄 / 夜间）。
/// 颜色取值参考主流阅读器：夜间 #121512 深灰绿底、米黄 #F5EFDC 护眼底、纯白 #FFFFFF。
class ReadingTheme {
  final String name;
  final Color background;
  final Color text;
  final Color secondaryText; // 页眉页脚、章节名弱化色

  const ReadingTheme({
    required this.name,
    required this.background,
    required this.text,
    required this.secondaryText,
  });
}

const kReadingThemes = <ReadingTheme>[
  ReadingTheme(
    name: '白',
    background: Color(0xFFFFFFFF),
    text: Color(0xFF262626),
    secondaryText: Color(0xFF999999),
  ),
  ReadingTheme(
    name: '米黄',
    background: Color(0xFFF5EFDC),
    text: Color(0xFF3B3226),
    secondaryText: Color(0xFF9C8E72),
  ),
  ReadingTheme(
    name: '夜间',
    background: Color(0xFF121512),
    text: Color(0xFFB8B8B2),
    secondaryText: Color(0xFF5C5F58),
  ),
];

/// 排版参数 Token：分页引擎（M2）与设置面板共同消费
class ReaderTypography {
  final double fontSize; // 正文字号（可调 14~28）
  final double lineHeight; // 行高倍数
  final double paragraphSpacing; // 段间距
  final double horizontalPadding; // 页面左右留白

  const ReaderTypography({
    this.fontSize = 18,
    this.lineHeight = 1.7,
    this.paragraphSpacing = 8,
    this.horizontalPadding = 20,
  });

  ReaderTypography copyWith({double? fontSize}) => ReaderTypography(
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight,
        paragraphSpacing: paragraphSpacing,
        horizontalPadding: horizontalPadding,
      );
}
