import 'package:go_router/go_router.dart';

import '../features/library/presentation/library_page.dart';
import '../features/reader/presentation/reader_page.dart';
import '../features/settings/presentation/settings_page.dart';

/// 路由：
/// /            书库（首页）
/// /reader/:id  阅读器
/// /settings    设置
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'library',
      builder: (context, state) => const LibraryPage(),
    ),
    GoRoute(
      path: '/reader/:id',
      name: 'reader',
      builder: (context, state) {
        final bookId = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
        return ReaderPage(bookId: bookId);
      },
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],
);
