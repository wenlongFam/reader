import 'package:flutter/material.dart';

/// 设置页 M0 占位。M3 在此接入：字号（14~28）、行距、三套阅读主题、亮度、阅读模式（翻页/滚动）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: const [
          SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.text_fields_outlined),
            title: Text('字号 / 行距 / 主题'),
            subtitle: Text('M3 实现（阅读器设置面板）'),
          ),
          ListTile(
            leading: Icon(Icons.wb_sunny_outlined),
            title: Text('亮度与夜间模式'),
            subtitle: Text('M3 实现'),
          ),
          ListTile(
            leading: Icon(Icons.auto_stories_outlined),
            title: Text('阅读模式（翻页 / 滚动）'),
            subtitle: Text('M2 实现'),
          ),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于'),
            subtitle: Text('文龙阅读器 v0.1.0 · MVP'),
          ),
        ],
      ),
    );
  }
}
