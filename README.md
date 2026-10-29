# 文龙阅读器（wenlong_reader）

双端（Android / iOS）本地电子书阅读器 MVP。技术方案见 [docs/mvp-tech-plan.md](docs/mvp-tech-plan.md)。

## 技术栈

Flutter · Riverpod · drift(SQLite) · go_router · 自研 TXT 分章 / TextPainter 分页引擎

## 本地运行

```bash
# 1. 生成 android/ ios/ 平台目录（首次克隆后执行一次）
flutter create . --org com.wenlong --project-name wenlong_reader

# 2. 拉取依赖
flutter pub get

# 3. 生成 drift 代码（database.g.dart）
dart run build_runner build --delete-conflicting-outputs

# 4. 运行
flutter run
```

## 目录结构

```
lib/
├── main.dart                     # 入口
├── app.dart                      # MaterialApp + 主题
├── core/
│   ├── router.dart               # go_router 路由
│   ├── db/database.dart          # drift 表：Books/Chapters/Progress/Bookmarks
│   ├── theme/reading_theme.dart  # 阅读主题 Token（白/米黄/夜间）
│   └── util/charset.dart         # 编码探测（BOM → UTF-8 校验 → GBK 兜底）
└── features/
    ├── import/                   # TXT/EPUB 解析与导入服务
    ├── library/                  # 书库页
    ├── reader/                   # 阅读器（M2 实现分页引擎）
    └── settings/                 # 设置页
```

## 里程碑

- [x] M0 工程脚手架
- [ ] M1 导入 + 书库
- [ ] M2 阅读器核心（分页 + 续读）
- [ ] M3 阅读体验（字号/主题/书签）
- [ ] M4 打磨提审
