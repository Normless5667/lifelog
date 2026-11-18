import 'package:flutter/material.dart';

import '../db/repo.dart';

/// 全局界面偏好控制器：
/// - 主题模式（跟随系统 / 浅色 / 深色）
/// - 字体缩放（小 0.9 / 标准 1.0 / 大 1.15）
/// - 语言切换（跟随系统 system / 中文 zh / English en），挂载至 MaterialApp.locale
class AppPrefsController extends ChangeNotifier {
  AppPrefsController._();
  static final AppPrefsController instance = AppPrefsController._();

  ThemeMode _themeMode = ThemeMode.system;
  double _textScale = 1.0;
  String _lang = 'zh'; // 'system' | 'zh' | 'en'

  ThemeMode get themeMode => _themeMode;
  double get textScale => _textScale;
  String get lang => _lang;

  bool get isEn {
    if (_lang == 'en') return true;
    if (_lang == 'zh') return false;
    return WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'en';
  }

  /// 传给 MaterialApp.locale；当为 null 时跟随系统语言
  Locale? get localeOverride {
    if (_lang == 'en') return const Locale('en');
    if (_lang == 'zh') return const Locale('zh');
    return null;
  }

  Future<void> load() async {
    final tm = await Repo.getKv('pref_theme_mode') ?? 'system';
    final sc = double.tryParse(await Repo.getKv('pref_text_scale') ?? '') ?? 1.0;
    final lg = await Repo.getKv('pref_lang') ?? 'zh';
    _themeMode = tm == 'dark'
        ? ThemeMode.dark
        : (tm == 'light' ? ThemeMode.light : ThemeMode.system);
    _textScale = sc.clamp(0.85, 1.25);
    _lang = (lg == 'en' || lg == 'zh' || lg == 'system') ? lg : 'zh';
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final s = mode == ThemeMode.dark ? 'dark' : (mode == ThemeMode.light ? 'light' : 'system');
    await Repo.setKv('pref_theme_mode', s);
    notifyListeners();
  }

  Future<void> setTextScale(double scale) async {
    _textScale = scale;
    await Repo.setKv('pref_text_scale', '$scale');
    notifyListeners();
  }

  Future<void> setLang(String langCode) async {
    _lang = langCode;
    await Repo.setKv('pref_lang', langCode);
    notifyListeners();
  }
}
