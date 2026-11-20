import 'package:flutter/material.dart';

import '../db/repo.dart';

/// 应用三套视觉皮肤：默认浅色 / 常规深色 / Gemini 深夜黑
enum AppSkin { light, dark, midnight }

/// 全局界面偏好控制器：
/// - 皮肤选择（默认浅色 / 深色 / 深夜黑，兼容旧版 pref_theme_mode）
/// - 字体缩放（小 0.9 / 标准 1.0 / 大 1.15）
/// - 语言切换（跟随系统 system / 中文 zh / English en），挂载至 MaterialApp.locale
class AppPrefsController extends ChangeNotifier {
  AppPrefsController._();
  static final AppPrefsController instance = AppPrefsController._();

  AppSkin _skin = AppSkin.light;
  ThemeMode _themeMode = ThemeMode.light;
  double _textScale = 1.0;
  String _lang = 'zh'; // 'system' | 'zh' | 'en'

  AppSkin get skin => _skin;
  bool get isMidnight => _skin == AppSkin.midnight;
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
    final savedSkin = await Repo.getKv('pref_app_skin');
    final tm = await Repo.getKv('pref_theme_mode') ?? 'light';
    final sc = double.tryParse(await Repo.getKv('pref_text_scale') ?? '') ?? 1.0;
    final lg = await Repo.getKv('pref_lang') ?? 'zh';

    if (savedSkin == 'midnight') {
      _skin = AppSkin.midnight;
      _themeMode = ThemeMode.dark;
    } else if (savedSkin == 'dark') {
      _skin = AppSkin.dark;
      _themeMode = ThemeMode.dark;
    } else if (savedSkin == 'light') {
      _skin = AppSkin.light;
      _themeMode = ThemeMode.light;
    } else {
      // 兼容升级：读取旧版 pref_theme_mode
      if (tm == 'dark') {
        _skin = AppSkin.dark;
        _themeMode = ThemeMode.dark;
      } else {
        _skin = AppSkin.light;
        _themeMode = tm == 'system' ? ThemeMode.system : ThemeMode.light;
      }
    }

    _textScale = sc.clamp(0.85, 1.25);
    _lang = (lg == 'en' || lg == 'zh' || lg == 'system') ? lg : 'zh';
    notifyListeners();
  }

  Future<void> setSkin(AppSkin next) async {
    _skin = next;
    _themeMode = next == AppSkin.light ? ThemeMode.light : ThemeMode.dark;
    final keyVal = switch (next) {
      AppSkin.light => 'light',
      AppSkin.dark => 'dark',
      AppSkin.midnight => 'midnight',
    };
    await Repo.setKv('pref_app_skin', keyVal);
    await Repo.setKv('pref_theme_mode', next == AppSkin.light ? 'light' : 'dark');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == ThemeMode.dark) {
      await setSkin(AppSkin.dark);
    } else {
      await setSkin(AppSkin.light);
    }
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
