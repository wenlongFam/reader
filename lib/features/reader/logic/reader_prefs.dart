import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReadingMode { page, scroll }

/// 阅读偏好：跨书全局生效，SharedPreferences 持久化
class ReaderPrefs {
  final int themeIndex; // kReadingThemes 下标：0 白 / 1 米黄 / 2 夜间
  final double fontSize; // 14 ~ 28
  final ReadingMode mode;
  final double brightness; // 0.3 ~ 1.0（1.0 = 不加暗罩）

  const ReaderPrefs({
    this.themeIndex = 1,
    this.fontSize = 18,
    this.mode = ReadingMode.page,
    this.brightness = 1.0,
  });

  ReaderPrefs copyWith({
    int? themeIndex,
    double? fontSize,
    ReadingMode? mode,
    double? brightness,
  }) {
    return ReaderPrefs(
      themeIndex: themeIndex ?? this.themeIndex,
      fontSize: fontSize ?? this.fontSize,
      mode: mode ?? this.mode,
      brightness: brightness ?? this.brightness,
    );
  }
}

class ReaderPrefsController extends StateNotifier<ReaderPrefs> {
  ReaderPrefsController() : super(const ReaderPrefs()) {
    _load();
  }

  static const _kTheme = 'reader.themeIndex';
  static const _kFontSize = 'reader.fontSize';
  static const _kMode = 'reader.mode';
  static const _kBrightness = 'reader.brightness';

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    state = ReaderPrefs(
      themeIndex: sp.getInt(_kTheme) ?? 1,
      fontSize: sp.getDouble(_kFontSize) ?? 18,
      mode: (sp.getInt(_kMode) ?? 0) == 1
          ? ReadingMode.scroll
          : ReadingMode.page,
      brightness: sp.getDouble(_kBrightness) ?? 1.0,
    );
  }

  Future<void> update(ReaderPrefs prefs) async {
    state = prefs;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kTheme, prefs.themeIndex);
    await sp.setDouble(_kFontSize, prefs.fontSize);
    await sp.setInt(_kMode, prefs.mode == ReadingMode.scroll ? 1 : 0);
    await sp.setDouble(_kBrightness, prefs.brightness);
  }
}

final readerPrefsProvider =
    StateNotifierProvider<ReaderPrefsController, ReaderPrefs>(
        (ref) => ReaderPrefsController());
