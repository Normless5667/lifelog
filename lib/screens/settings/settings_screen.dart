import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../db/repo.dart';
import '../../services/ai_service.dart';
import '../../services/app_prefs.dart';
import '../../services/settings_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import 'about_screen.dart';
import 'notification_diagnostics_screen.dart';

/// 设置页 v1.2：
/// - API Base URL 预设下拉（DeepSeek / OpenAI / 通义千问 / 自定义，只填 deepseek 自动补全路径）
/// - 模型名称预设下拉（deepseek-chat / deepseek-reasoner / 自定义）
/// - 外观与语言（深色模式跟随系统、三档字号调节、中文/English 切换）
/// - 通知与震动诊断页入口
/// - JSON / CSV 数据导出
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

  static const _chatBasePresets = <(String label, String url)>[
    ('DeepSeek (默认)', 'https://api.deepseek.com'),
    ('OpenAI', 'https://api.openai.com/v1'),
    ('通义千问 (阿里云)', 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
  ];

  static const _chatModelPresets = <String>[
    'deepseek-chat',
    'deepseek-reasoner',
    'qwen-plus',
    'gpt-4o-mini',
  ];

  static const _visionPresets = <(String label, String url, String model)>[
    ('DeepSeek Flash', 'https://api.deepseek.com', 'deepseek-flash'),
    ('通义千问 VL (阿里云百炼)', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-vl-max'),
    ('智谱 GLM-4V', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4v-flash'),
    ('OpenAI GPT-4o mini', 'https://api.openai.com/v1', 'gpt-4o-mini'),
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
    super.dispose();
  }

  Future<void> _load() async {
    final chat = await SettingsService.chatConfig();
    final same = await SettingsService.visionSameAsChat();
    final vis = await SettingsService.visionConfig(raw: true);
    if (!mounted) return;
    setState(() {
      _chatUrl.text = chat.baseUrl;
      _chatKey.text = chat.apiKey;
      _chatModel.text = chat.model;
      _visionSame = same;
      _visionUrl.text = vis.baseUrl;
      _visionKey.text = vis.apiKey;
      _visionModel.text = vis.model;
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
    toast(context, '设置已保存');
  }

  Future<void> _test(AiConfig cfg) async {
    await _save();
    setState(() => _testing = true);
    try {
      final reply = await AiService.testConfig(cfg);
      if (!mounted) return;
      toast(context, '连接成功：$reply');
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
        subject: '生活助手 数据备份 (JSON)',
      ),
    );
  }

  Future<void> _exportCsv() async {
    final data = await Repo.exportAll();
    final buf = StringBuffer();
    buf.writeln('=== 饮食记录 (meals) ===');
    buf.writeln('日期,餐次,食物名称,份量,热量(kcal),蛋白质(g),碳水(g),脂肪(g)');
    for (final m in (data['meals'] as List? ?? const [])) {
      buf.writeln('${m['date']},${m['meal_type']},"${m['name']}","${m['amount'] ?? ''}",${m['calories']},${m['protein']},${m['carbs']},${m['fat']}');
    }
    buf.writeln('\n=== 身体记录 (body_records) ===');
    buf.writeln('日期,体重(kg),体脂率(%),腰围(cm)');
    for (final b in (data['body_records'] as List? ?? const [])) {
      buf.writeln('${b['date']},${b['weight'] ?? ''},${b['body_fat'] ?? ''},${b['waist'] ?? ''}');
    }
    buf.writeln('\n=== 有氧记录 (cardio_records) ===');
    buf.writeln('日期,类型,时长(分钟),距离(km),消耗(kcal)');
    for (final c in (data['cardio_records'] as List? ?? const [])) {
      buf.writeln('${c['date']},${c['type']},${c['duration_minutes']},${c['distance_km'] ?? ''},${c['calories']}');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/life_assistant_export_${today()}.csv');
    await file.writeAsString('\uFEFF${buf.toString()}');
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: '生活助手 表格导出 (CSV)',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefsController.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(prefs.tr('设置', 'Settings')),
            actions: [
              TextButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: Text(prefs.tr('保存', 'Save')),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SectionTitle(
                      prefs.tr('外观、字号与语言', 'Appearance, Font & Language'),
                      icon: Icons.palette_rounded,
                      iconColor: const Color(0xFF2B5B84),
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(prefs.tr('深色模式', 'Theme Mode'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            SegmentedButton<ThemeMode>(
                              segments: [
                                ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_rounded), label: Text(prefs.tr('跟随系统', 'System'))),
                                ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_rounded), label: Text(prefs.tr('浅色', 'Light'))),
                                ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_rounded), label: Text(prefs.tr('深色', 'Dark'))),
                              ],
                              selected: {prefs.themeMode},
                              onSelectionChanged: (s) => prefs.setThemeMode(s.first),
                            ),
                            const SizedBox(height: 14),
                            Text(prefs.tr('字体大小（户外阅读建议选大）', 'Font Size'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            SegmentedButton<double>(
                              segments: [
                                ButtonSegment(value: 0.9, label: Text(prefs.tr('小', 'Small'))),
                                ButtonSegment(value: 1.0, label: Text(prefs.tr('标准', 'Medium'))),
                                ButtonSegment(value: 1.15, label: Text(prefs.tr('大', 'Large'))),
                              ],
                              selected: {prefs.textScale},
                              onSelectionChanged: (s) => prefs.setTextScale(s.first),
                            ),
                            const SizedBox(height: 14),
                            Text(prefs.tr('界面语言 / Language', 'Language'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'zh', icon: Icon(Icons.translate_rounded), label: Text('简体中文')),
                                ButtonSegment(value: 'en', icon: Icon(Icons.language_rounded), label: Text('English')),
                              ],
                              selected: {prefs.lang == 'en' ? 'en' : 'zh'},
                              onSelectionChanged: (s) => prefs.setLang(s.first),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SectionTitle(
                      prefs.tr('对话与建议模型（支持一键预设）', 'Chat AI Model (DeepSeek / OpenAI)'),
                      icon: Icons.smart_toy_rounded,
                      iconColor: const Color(0xFFFF7A22),
                    ),
                    const Text(
                      '支持点选下方服务商预设，或直接输入 deepseek / 域名（系统会自动补全 /chat/completions）。API Key 加密保存在本机。',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _chatBasePresets.map((p) {
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
                      decoration: const InputDecoration(
                        labelText: 'Base URL（可直接填 deepseek 或完整地址）',
                        hintText: 'https://api.deepseek.com',
                        prefixIcon: Icon(Icons.link_rounded, color: Color(0xFF2B5B84)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _chatKey,
                      obscureText: _obscureChat,
                      decoration: InputDecoration(
                        labelText: 'API Key',
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
                      decoration: const InputDecoration(
                        labelText: '模型名称（可点上方预设或手填）',
                        hintText: 'deepseek-chat / deepseek-reasoner',
                        prefixIcon: Icon(Icons.memory_rounded, color: Color(0xFF26A69A)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: _testing ? null : () => _test(_currentChat()),
                        icon: const Icon(Icons.bolt_rounded),
                        label: Text(_testing ? '测试中…' : '测试连接'),
                      ),
                    ),
                    const Divider(height: 28),
                    const SectionTitle('拍照识图模型（方案 A）', icon: Icons.camera_enhance_rounded, iconColor: Color(0xFF26A69A)),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('与对话模型共用同一套配置'),
                      subtitle: const Text('若当前对话模型不支持图片输入，请关闭此开关并点选下方视觉模型'),
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
                        decoration: const InputDecoration(
                          labelText: '识图 Base URL',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _visionKey,
                        obscureText: _obscureVision,
                        decoration: InputDecoration(
                          labelText: '识图 API Key',
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
                        decoration: const InputDecoration(
                          labelText: '识图模型名称',
                          hintText: '如 qwen-vl-max / deepseek-flash',
                          prefixIcon: Icon(Icons.visibility_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _testing ? null : () => _test(_currentVision()),
                          icon: const Icon(Icons.bolt_rounded),
                          label: Text(_testing ? '测试中…' : '测试识图接口'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('保存 AI 配置'),
                    ),
                    const Divider(height: 28),
                    const SectionTitle('系统通知与数据备份', icon: Icons.security_rounded, iconColor: Color(0xFF42A5F5)),
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
                            title: const Text('通知与震动诊断页（ColorOS 必看）', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('排查为什么没响、一键开启重要通知与全屏横幅'),
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
                            title: const Text('导出完整备份 (JSON)', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('包含课表、饮食、力量训练、有氧、身体记录'),
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
                            title: const Text('导出 Excel 表格 (CSV)', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('方便在电脑或手机表格中查看饮食、体重与有氧明细'),
                            trailing: const Icon(Icons.ios_share_rounded),
                            onTap: _exportCsv,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset('assets/icon/dafeiyu_mascot.png', width: 40, height: 40, fit: BoxFit.cover),
                            ),
                            title: const Text('关于生活助手', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('版本 v1.2.0 · 由大肥鱼协助开发'),
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
