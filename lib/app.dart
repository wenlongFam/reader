import 'package:flutter/material.dart';

import 'core/router.dart';

class WenlongApp extends StatelessWidget {
  const WenlongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '文龙阅读器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF8B6F47),
        useMaterial3: true,
        fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei'],
      ),
      routerConfig: appRouter,
    );
  }
}
