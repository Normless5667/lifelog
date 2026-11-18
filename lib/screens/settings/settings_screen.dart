import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../db/repo.dart';
import '../../services/ai_service.dart';
import '../../services/app_prefs.dart';
import '../../services/settings_service.dart';
import '../../services/weather_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import 'about_screen.dart';
import 'notification_diagnostics_screen.dart';

/// 设置页：
/// - 外观与语言（跟随系统 / 简体中文 / English，三档字号调节）
/// - 天气城市与定位方式（GPS 优先 6h 缓存 + 手动固定城市防代理跑偏）
/// - API Base URL 与模型名称预设
/// - 通知与震动诊断页入口 + JSON / CSV 数据导出
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _chatUrl = TextEditingController();
  final _chatKey = TextEditingController();
  final _chatModel = TextEditingController();

  bool _visionSame = true;
  final _visionUrl = TextEditingController();
  final _visionKey = TextEditingController();
  final _visionModel = TextEditingController();

  bool _obscureChat = true;
  bool _obscureVision = true;
  bool _testing = false;
  bool _loading = true;

  String? _manualWeatherCity;
  final _customCityCtrl = TextEditingController();
  bool _searchingCity = false;

  static const _chatModelPresets = <String>[
    'deepseek-chat',
    'deepseek-reasoner',
    'qwen-plus',
    'gpt-4o-mini',
  ];

  static const _visionPresets = <(String label, String url, String model)>[
    ('DeepSeek Flash', 'https://api.deepseek.com', 'deepseek-flash'),
    ('Qwen-VL Max', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-vl-max'),
    ('GLM-4V Flash', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4v-flash'),
    ('GPT-4o mini', 'https://api.openai.com/v1', 'gpt-4o-mini'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _chatUrl.dispose();
    _chatKey.dispose();
    _chatModel.dispose();
    _visionUrl.dispose();
    _visionKey.dispose();
    _visionModel.dispose();
    _customCityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final chat = await SettingsService.chatConfig();
    final same = await SettingsService.visionSameAsChat();
    final vis = await SettingsService.visionConfig(raw: true);
    final manualCity = await WeatherService.getManualCity();
    if (!mounted) return;
    setState(() {
      _chatUrl.text = chat.baseUrl;
      _chatKey.text = chat.apiKey;
      _chatModel.text = chat.model;
      _visionSame = same;
      _visionUrl.text = vis.baseUrl;
      _visionKey.text = vis.apiKey;
      _visionModel.text = vis.model;
      _manualWeatherCity = manualCity?.city;
      _customCityCtrl.text = manualCity?.city ?? '';
      _loading = false;
    });
  }

  AiConfig _currentChat() => AiConfig(
        baseUrl: AiService.normalizeBaseUrl(_chatUrl.text),
        apiKey: _chatKey.text.trim(),
        model: _chatModel.text.trim().isEmpty ? 'deepseek-chat' : _chatModel.text.trim(),
      );

  AiConfig _currentVision() => _visionSame
      ? _currentChat()
      : AiConfig(
          baseUrl: AiService.normalizeBaseUrl(_visionUrl.text),
          apiKey: _visionKey.text.trim(),
          model: _visionModel.text.trim(),
        );

  Future<void> _save() async {
    final normalizedChat = _currentChat();
    _chatUrl.text = normalizedChat.baseUrl;
    _chatModel.text = normalizedChat.model;
    await SettingsService.saveChatConfig(normalizedChat);
    await SettingsService.setVisionSameAsChat(_visionSame);
    await SettingsService.saveVisionConfig(AiConfig(
      baseUrl: AiService.normalizeBaseUrl(_visionUrl.text),
      apiKey: _visionKey.text.trim(),
      model: _visionModel.text.trim(),
    ));
    if (!mounted) return;
    toast(context, context.l10n.commonSavedToast);
  }

  Future<void> _test(AiConfig cfg) async {
    await _save();
    setState(() => _testing = true);
    try {
      final reply = await AiService.testConfig(cfg);
      if (!mounted) return;
      toast(context, context.l10n.settingsTestSuccessToast(reply));
    } catch (e) {
      if (!mounted) return;
      showAiError(context, e);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _exportJson() async {
    final data = await Repo.exportAll();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/life_assistant_backup_${today()}.json');
    await file.writeAsString(jsonStr);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'life_assistant_backup.json',
      ),
    );
  }

  Future<void> _exportCsv() async {
    final data = await Repo.exportAll();
    final buf = StringBuffer();
    buf.writeln('=== meals ===');
    buf.writeln('date,meal_type,name,amount,calories,protein,carbs,fat');
    for (final m in (data['meals'] as List? ?? const [])) {
      buf.writeln('${m['date']},${m['meal_type']},"${m['name']}","${m['amount'] ?? ''}",${m['calories']},${m['protein']},${m['carbs']},${m['fat']}');
    }
    buf.writeln('\n=== body_records ===');
    buf.writeln('date,weight_kg,body_fat_pct,waist_cm');
    for (final b in (data['body_records'] as List? ?? const [])) {
      buf.writeln('${b['date']},${b['weight'] ?? ''},${b['body_fat'] ?? ''},${b['waist'] ?? ''}');
    }
    buf.writeln('\n=== cardio_records ===');
    buf.writeln('date,type,duration_minutes,distance_km,calories');
    for (final c in (data['cardio_records'] as List? ?? const [])) {
      buf.writeln('${c['date']},${c['type']},${c['duration_minutes']},${c['distance_km'] ?? ''},${c['calories']}');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/life_assistant_export_${today()}.csv');
    await file.writeAsString('\uFEFF${buf.toString()}');
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'life_assistant_export.csv',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefsController.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final l = context.l10n;
        final chatBasePresets = <(String label, String url)>[
          (l.settingsPresetDeepseek, 'https://api.deepseek.com'),
          (l.settingsPresetOpenai, 'https://api.openai.com/v1'),
          (l.settingsPresetQwen, 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(l.settingsTitle),
            actions: [
              TextButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: Text(l.commonSave),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SectionTitle(
                      l.settingsAppearanceSection,
                      icon: Icons.palette_rounded,
                      iconColor: const Color(0xFF2B5B84),
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.settingsThemeMode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            SegmentedButton<ThemeMode>(
                              segments: [
                                ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_rounded), label: Text(l.settingsThemeSystem)),
                                ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_rounded), label: Text(l.settingsThemeLight)),
                                ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_rounded), label: Text(l.settingsThemeDark)),
                              ],
                              selected: {prefs.themeMode},
                              onSelectionChanged: (s) => prefs.setThemeMode(s.first),
                            ),
                            const SizedBox(height: 14),
                            Text(l.settingsFontSize, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            SegmentedButton<double>(
                              segments: [
                                ButtonSegment(value: 0.9, label: Text(l.settingsFontSmall)),
                                ButtonSegment(value: 1.0, label: Text(l.settingsFontMedium)),
                                ButtonSegment(value: 1.15, label: Text(l.settingsFontLarge)),
                              ],
                              selected: {prefs.textScale},
                              onSelectionChanged: (s) => prefs.setTextScale(s.first),
                            ),
                            const SizedBox(height: 14),
                            Text(l.settingsLanguage, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              segments: [
                                ButtonSegment(value: 'system', icon: const Icon(Icons.phonelink_setup_rounded), label: Text(l.settingsLangSystem)),
                                ButtonSegment(value: 'zh', icon: const Icon(Icons.translate_rounded), label: Text(l.settingsLangZh)),
                                ButtonSegment(value: 'en', icon: const Icon(Icons.language_rounded), label: Text(l.settingsLangEn)),
                              ],
                              selected: {prefs.lang},
                              onSelectionChanged: (s) => prefs.setLang(s.first),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SectionTitle(
                      l.settingsWeatherSection,
                      icon: Icons.location_on_rounded,
                      iconColor: const Color(0xFF26A69A),
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _manualWeatherCity == null
                                  ? l.settingsWeatherModeAuto
                                  : l.settingsWeatherModeManual(_manualWeatherCity!),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l.settingsWeatherProxyHint,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                ChoiceChip(
                                  avatar: const Icon(Icons.my_location_rounded, size: 16),
                                  label: Text(l.settingsWeatherAutoChip),
                                  selected: _manualWeatherCity == null,
                                  onSelected: (_) async {
                                    await WeatherService.setAutoLocationMode();
                                    await WeatherService.getWeather(forceRefresh: true);
                                    if (!mounted) return;
                                    setState(() {
                                      _manualWeatherCity = null;
                                      _customCityCtrl.clear();
                                    });
                                    toast(context, l.settingsWeatherAutoToast);
                                  },
                                ),
                                ...WeatherService.presetCities.map((p) {
                                  final selected = _manualWeatherCity == p.city;
                                  final displayLabel = L10nHelper.weatherPresetLabel(context, p);
                                  return ChoiceChip(
                                    label: Text(displayLabel),
                                    selected: selected,
                                    onSelected: (_) async {
                                      await WeatherService.setManualCity(city: p.city, lat: p.lat, lon: p.lon);
                                      await WeatherService.getWeather(forceRefresh: true);
                                      if (!mounted) return;
                                      setState(() {
                                        _manualWeatherCity = p.city;
                                        _customCityCtrl.text = p.city;
                                      });
                                      toast(context, l.settingsWeatherLockedToast(displayLabel));
                                    },
                                  );
                                }),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _customCityCtrl,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      labelText: l.settingsWeatherCustomLabel,
                                      hintText: l.settingsWeatherCustomHint,
                                      prefixIcon: const Icon(Icons.location_city_rounded, size: 18),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonalIcon(
                                  onPressed: _searchingCity
                                      ? null
                                      : () async {
                                          final q = _customCityCtrl.text.trim();
                                          if (q.isEmpty) return;
                                          setState(() => _searchingCity = true);
                                          try {
                                            final resolved = await WeatherService.searchAndSetManualCity(q);
                                            await WeatherService.getWeather(forceRefresh: true);
                                            if (!mounted) return;
                                            setState(() {
                                              _manualWeatherCity = resolved;
                                              _customCityCtrl.text = resolved;
                                            });
                                            toast(context, l.settingsWeatherLockedToast(resolved));
                                          } catch (e) {
                                            if (!mounted) return;
                                            toast(context, e.toString().replaceAll('Exception: ', ''));
                                          } finally {
                                            if (mounted) setState(() => _searchingCity = false);
                                          }
                                        },
                                  icon: _searchingCity
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.search_rounded, size: 18),
                                  label: Text(l.settingsWeatherSetBtn),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SectionTitle(
                      l.settingsChatAiSection,
                      icon: Icons.smart_toy_rounded,
                      iconColor: const Color(0xFFFF7A22),
                    ),
                    Text(
                      l.settingsChatAiHint,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: chatBasePresets.map((p) {
                        final selected = _chatUrl.text.trim() == p.$2;
                        return ChoiceChip(
                          label: Text(p.$1),
                          selected: selected,
                          onSelected: (_) => setState(() {
                            _chatUrl.text = p.$2;
                            if (p.$2.contains('deepseek')) _chatModel.text = 'deepseek-chat';
                            if (p.$2.contains('openai')) _chatModel.text = 'gpt-4o-mini';
                            if (p.$2.contains('dashscope')) _chatModel.text = 'qwen-plus';
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _chatUrl,
                      decoration: InputDecoration(
                        labelText: l.settingsBaseUrlLabel,
                        hintText: 'https://api.deepseek.com',
                        prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFF2B5B84)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _chatKey,
                      obscureText: _obscureChat,
                      decoration: InputDecoration(
                        labelText: l.settingsApiKeyLabel,
                        hintText: 'sk-...',
                        prefixIcon: const Icon(Icons.key_rounded, color: Color(0xFFFF7A22)),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureChat ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscureChat = !_obscureChat),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      children: _chatModelPresets.map((m) {
                        return ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(m, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() => _chatModel.text = m),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _chatModel,
                      decoration: InputDecoration(
                        labelText: l.settingsModelNameLabel,
                        hintText: 'deepseek-chat / deepseek-reasoner',
                        prefixIcon: const Icon(Icons.memory_rounded, color: Color(0xFF26A69A)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: _testing ? null : () => _test(_currentChat()),
                        icon: const Icon(Icons.bolt_rounded),
                        label: Text(_testing ? l.settingsTestingBtn : l.settingsTestConnectionBtn),
                      ),
                    ),
                    const Divider(height: 28),
                    SectionTitle(l.settingsVisionSection, icon: Icons.camera_enhance_rounded, iconColor: const Color(0xFF26A69A)),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.settingsVisionSameSwitch),
                      subtitle: Text(l.settingsVisionSameSub),
                      value: _visionSame,
                      onChanged: (v) => setState(() => _visionSame = v),
                    ),
                    if (!_visionSame) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _visionPresets.map((p) {
                          return ActionChip(
                            label: Text(p.$1),
                            onPressed: () => setState(() {
                              _visionUrl.text = p.$2;
                              _visionModel.text = p.$3;
                              if (_visionKey.text.isEmpty && p.$2 == _chatUrl.text.trim()) {
                                _visionKey.text = _chatKey.text;
                              }
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _visionUrl,
                        decoration: InputDecoration(
                          labelText: l.settingsVisionBaseUrlLabel,
                          prefixIcon: const Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _visionKey,
                        obscureText: _obscureVision,
                        decoration: InputDecoration(
                          labelText: l.settingsVisionApiKeyLabel,
                          prefixIcon: const Icon(Icons.key_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureVision ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _obscureVision = !_obscureVision),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _visionModel,
                        decoration: InputDecoration(
                          labelText: l.settingsVisionModelLabel,
                          hintText: 'qwen-vl-max / deepseek-flash',
                          prefixIcon: const Icon(Icons.visibility_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _testing ? null : () => _test(_currentVision()),
                          icon: const Icon(Icons.bolt_rounded),
                          label: Text(_testing ? l.settingsTestingBtn : l.settingsTestVisionBtn),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(l.settingsSaveAiBtn),
                    ),
                    const Divider(height: 28),
                    SectionTitle(l.settingsSystemDataSection, icon: Icons.security_rounded, iconColor: const Color(0xFF42A5F5)),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF7A22).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.health_and_safety_rounded, color: Color(0xFFFF7A22)),
                            ),
                            title: Text(l.settingsDiagTileTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(l.settingsDiagTileSub),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const NotificationDiagnosticsScreen()),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF26A69A).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.data_object_rounded, color: Color(0xFF26A69A)),
                            ),
                            title: Text(l.settingsExportJsonTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(l.settingsExportJsonSub),
                            trailing: const Icon(Icons.ios_share_rounded),
                            onTap: _exportJson,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF42A5F5).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.table_chart_rounded, color: Color(0xFF42A5F5)),
                            ),
                            title: Text(l.settingsExportCsvTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(l.settingsExportCsvSub),
                            trailing: const Icon(Icons.ios_share_rounded),
                            onTap: _exportCsv,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset('assets/icon/dafeiyu_mascot.png', width: 40, height: 40, fit: BoxFit.cover),
                            ),
                            title: Text(l.settingsAboutTileTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(l.settingsAboutTileSub),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AboutScreen()),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
