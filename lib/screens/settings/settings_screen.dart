import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../db/repo.dart';
import '../../debug/debug_server.dart';
import '../../services/academic_calendar_service.dart';
import '../../services/ai_service.dart';
import '../../services/app_prefs.dart';
import '../../services/settings_service.dart';
import '../../services/usage_telemetry_service.dart';
import '../../services/weather_service.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import 'about_screen.dart';
import 'battery_diagnostics_screen.dart';
import 'notification_diagnostics_screen.dart';
import 'semester_settings_screen.dart';

/// 设置页（v2.0）：
/// - 外观与语言（跟随系统 / 简体中文 / English，三档字号调节）
/// - 天气城市与定位方式（GPS 优先 6h 缓存 + 手动固定城市防代理跑偏）
/// - API Base URL 与模型名称预设
/// - 使用遥测统计、耗电/通知诊断、桌面小组件引导与 JSON / CSV 导出
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
  bool _usageEnabled = true;
  int _usageEventCount = 0;
  AcademicTerm? _activeTerm;

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
    final usageCount = await UsageTelemetryService.instance.getEventCount();
    final activeTerm = await AcademicCalendarService.getActiveTerm();
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
      _usageEnabled = UsageTelemetryService.instance.isEnabled;
      _usageEventCount = usageCount;
      _activeTerm = activeTerm;
      _loading = false;
    });
  }

  bool _debugServerBusy = false;

  Future<void> _toggleDebugServer(bool enable) async {
    if (_debugServerBusy) return;
    final l = context.l10n;
    setState(() => _debugServerBusy = true);
    try {
      if (enable) {
        await DebugServer.instance.start();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(
              Icons.warning_amber_rounded,
              color: AppColors.danger(ctx),
              size: 32,
            ),
            title: Text(l.debugServerWarnTitle),
            content: Text(l.debugServerWarnBody),
            actions: [
              FilledButton(
                key: const ValueKey('debug_server_warn_ack_btn'),
                onPressed: () => Navigator.pop(ctx),
                child: Text(l.debugServerWarnAck),
              ),
            ],
          ),
        );
      } else {
        await DebugServer.instance.stop(reason: 'settings_switch');
        if (!mounted) return;
        toast(context, l.debugServerStoppedToast);
      }
    } catch (e) {
      if (!mounted) return;
      toast(context, l.debugServerStartFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _debugServerBusy = false);
    }
  }

  Widget _buildDeveloperDebugCard(BuildContext context) {
    final l = context.l10n;
    final danger = AppColors.danger(context);
    final srv = DebugServer.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([srv, srv.config]),
      builder: (context, _) {
        final running = srv.isRunning;
        final url = srv.connectUrl ?? '';
        final token = srv.token ?? '';
        return SurfaceCard(
          padding: AppSpacing.cardPadding,
          backgroundColor: running ? AppColors.softBg(context, danger) : null,
          borderColor: running ? AppColors.softBorder(context, danger) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                key: const ValueKey('settings_debug_server_switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  l.debugServerSwitchTitle,
                  style: AppTypography.cardTitle(
                    context,
                    color: running ? danger : null,
                  ),
                ),
                subtitle: Text(
                  running
                      ? l.debugServerSwitchSubOn(srv.clientCount)
                      : l.debugServerSwitchSubOff,
                  style: AppTypography.bodySecondary(context),
                ),
                value: running,
                onChanged: _debugServerBusy ? null : _toggleDebugServer,
              ),
              if (running && url.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l.debugServerUrlLabel,
                  style: AppTypography.caption(context),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: AppRadius.bMd,
                    border: Border.all(color: AppColors.softBorder(context, danger)),
                  ),
                  child: SelectableText(
                    url,
                    key: const ValueKey('settings_debug_server_url'),
                    style: AppTypography.body(context).copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.debugServerTokenLabel(token),
                  style: AppTypography.caption(context),
                ),
                const SizedBox(height: 2),
                Text(
                  l.debugServerLiveConfigPreview(
                    srv.config.fxRate.toString(),
                    srv.config.threshold.toStringAsFixed(2),
                  ),
                  style: AppTypography.caption(context),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.tonalIcon(
                  key: const ValueKey('settings_debug_server_copy_btn'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (!context.mounted) return;
                    toast(context, l.debugServerCopiedToast);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: Text(l.debugServerCopyUrlBtn),
                ),
              ],
            ],
          ),
        );
      },
    );
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
      buf.writeln(
          '${m['date']},${m['meal_type']},"${m['name']}","${m['amount'] ?? ''}",${m['calories']},${m['protein']},${m['carbs']},${m['fat']}');
    }
    buf.writeln('\n=== body_records ===');
    buf.writeln('date,weight_kg,body_fat_pct,waist_cm');
    for (final b in (data['body_records'] as List? ?? const [])) {
      buf.writeln('${b['date']},${b['weight'] ?? ''},${b['body_fat'] ?? ''},${b['waist'] ?? ''}');
    }
    buf.writeln('\n=== cardio_records ===');
    buf.writeln('date,type,duration_minutes,distance_km,calories');
    for (final c in (data['cardio_records'] as List? ?? const [])) {
      buf.writeln(
          '${c['date']},${c['type']},${c['duration_minutes']},${c['distance_km'] ?? ''},${c['calories']}');
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

  Future<void> _openUsageExportDialog() async {
    final l = context.l10n;
    int? selectedDays = 7;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final primary = AppColors.primary(ctx);
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(ctx, primary),
                    borderRadius: AppRadius.bMd,
                  ),
                  child: Icon(Icons.analytics_rounded, color: primary, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(l.usageExportDialogTitle, style: AppTypography.sectionTitle(ctx)),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.usageExportRangeLabel, style: AppTypography.badge(ctx)),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    ChoiceChip(
                      label: Text(l.usageRange1d),
                      selected: selectedDays == 1,
                      onSelected: (_) => setD(() => selectedDays = 1),
                    ),
                    ChoiceChip(
                      label: Text(l.usageRange7d),
                      selected: selectedDays == 7,
                      onSelected: (_) => setD(() => selectedDays = 7),
                    ),
                    ChoiceChip(
                      label: Text(l.usageRange30d),
                      selected: selectedDays == 30,
                      onSelected: (_) => setD(() => selectedDays = 30),
                    ),
                    ChoiceChip(
                      label: Text(l.usageRangeAll),
                      selected: selectedDays == null,
                      onSelected: (_) => setD(() => selectedDays = null),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await UsageTelemetryService.instance.exportAndShare(
                      format: 'json',
                      days: selectedDays,
                    );
                  },
                  icon: const Icon(Icons.data_object_rounded, size: 18),
                  label: Text(l.usageExportJsonBtn),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await UsageTelemetryService.instance.exportAndShare(
                      format: 'csv',
                      days: selectedDays,
                    );
                  },
                  icon: const Icon(Icons.table_chart_rounded, size: 18),
                  label: Text(l.usageExportCsvBtn),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmClearAllCourses() async {
    final l = context.l10n;
    final courses = await Repo.getCourses();
    if (!mounted) return;
    if (courses.isEmpty) {
      toast(context, l.scheduleAlreadyEmptyToast);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.scheduleClearConfirmTitle, style: AppTypography.sectionTitle(ctx)),
        content: Text(l.scheduleClearConfirmDesc(courses.length), style: AppTypography.body(ctx)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger(ctx),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.scheduleClearConfirmBtn),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await Repo.clearAllCourses();
    if (!mounted) return;
    toast(context, l.scheduleClearedToast(deleted));
  }

  Widget _systemTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required IconData trailingIcon,
    required VoidCallback onTap,
    Widget? customLeading,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            customLeading ??
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, color),
                    borderRadius: AppRadius.bMd,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.cardTitle(context)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.bodySecondary(context)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(trailingIcon, size: 20, color: AppColors.textTertiary(context)),
          ],
        ),
      ),
    );
  }

  ButtonStyle _segmentedStyle(BuildContext context, Color accentColor) {
    return SegmentedButton.styleFrom(
      backgroundColor: AppColors.surfaceSubtle(context),
      selectedBackgroundColor: AppColors.softBg(
        context,
        accentColor,
        lightAlpha: 0.14,
        darkAlpha: 0.22,
      ),
      selectedForegroundColor: accentColor,
      foregroundColor: AppColors.textSecondary(context),
      side: BorderSide(color: AppColors.border(context)),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefsController.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final l = context.l10n;
        final primary = AppColors.primary(context);
        final teal = AppColors.teal(context);
        final accent = AppColors.accent(context);
        final aiColor = AppColors.moduleAi(context);
        final scheduleColor = AppColors.moduleSchedule(context);

        final chatBasePresets = <(String label, String url)>[
          (l.settingsPresetDeepseek, 'https://api.deepseek.com'),
          (l.settingsPresetOpenai, 'https://api.openai.com/v1'),
          (l.settingsPresetQwen, 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
        ];

        return Scaffold(
          appBar: AppBar(
            titleSpacing: AppSpacing.sm,
            title: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.softBg(context, primary, lightAlpha: 0.12, darkAlpha: 0.20),
                    borderRadius: AppRadius.bSm,
                    border: Border.all(color: AppColors.softBorder(context, primary)),
                  ),
                  child: Icon(Icons.settings_rounded, color: primary, size: 18),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    l.settingsTitle,
                    style: AppTypography.pageTitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.softBg(context, primary),
                    foregroundColor: primary,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
                  ),
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: Text(l.commonSave),
                ),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xxxl,
                  ),
                  children: [
                    SectionTitle(
                      l.settingsAppearanceSection,
                      icon: Icons.palette_rounded,
                      iconColor: primary,
                    ),
                    SurfaceCard(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(l.settingsSkinTitle, style: AppTypography.badge(context)),
                          const SizedBox(height: AppSpacing.sm),
                          SegmentedButton<AppSkin>(
                            key: const ValueKey('settings_skin_selector'),
                            style: _segmentedStyle(context, primary),
                            segments: [
                              ButtonSegment(
                                value: AppSkin.light,
                                icon: const Icon(Icons.light_mode_rounded, size: 17),
                                label: Text(l.settingsSkinLight),
                              ),
                              ButtonSegment(
                                value: AppSkin.dark,
                                icon: const Icon(Icons.dark_mode_rounded, size: 17),
                                label: Text(l.settingsSkinDark),
                              ),
                              ButtonSegment(
                                value: AppSkin.midnight,
                                icon: const Icon(Icons.nights_stay_rounded, size: 17),
                                label: Text(l.settingsSkinMidnight),
                              ),
                            ],
                            selected: {prefs.skin},
                            onSelectionChanged: (s) => prefs.setSkin(s.first),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(l.settingsFontSize, style: AppTypography.badge(context)),
                          const SizedBox(height: AppSpacing.sm),
                          SegmentedButton<double>(
                            style: _segmentedStyle(context, primary),
                            segments: [
                              ButtonSegment(value: 0.9, label: Text(l.settingsFontSmall)),
                              ButtonSegment(value: 1.0, label: Text(l.settingsFontMedium)),
                              ButtonSegment(value: 1.15, label: Text(l.settingsFontLarge)),
                            ],
                            selected: {prefs.textScale},
                            onSelectionChanged: (s) => prefs.setTextScale(s.first),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(l.settingsLanguage, style: AppTypography.badge(context)),
                          const SizedBox(height: AppSpacing.sm),
                          SegmentedButton<String>(
                            style: _segmentedStyle(context, primary),
                            segments: [
                              ButtonSegment(
                                value: 'system',
                                icon: const Icon(Icons.phonelink_setup_rounded, size: 17),
                                label: Text(l.settingsLangSystem),
                              ),
                              ButtonSegment(
                                value: 'zh',
                                icon: const Icon(Icons.translate_rounded, size: 17),
                                label: Text(l.settingsLangZh),
                              ),
                              ButtonSegment(
                                value: 'en',
                                icon: const Icon(Icons.language_rounded, size: 17),
                                label: Text(l.settingsLangEn),
                              ),
                            ],
                            selected: {prefs.lang},
                            onSelectionChanged: (s) => prefs.setLang(s.first),
                          ),
                        ],
                      ),
                    ),
                    SectionTitle(
                      l.settingsWeatherSection,
                      icon: Icons.location_on_rounded,
                      iconColor: teal,
                    ),
                    SurfaceCard(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _manualWeatherCity == null
                                ? l.settingsWeatherModeAuto
                                : l.settingsWeatherModeManual(_manualWeatherCity!),
                            style: AppTypography.cardTitle(context),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(l.settingsWeatherProxyHint, style: AppTypography.bodySecondary(context)),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              ChoiceChip(
                                avatar: Icon(Icons.my_location_rounded, size: 15, color: teal),
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
                                  if (context.mounted) toast(context, l.settingsWeatherAutoToast);
                                },
                              ),
                              ...WeatherService.presetCities.map((p) {
                                final selected = _manualWeatherCity == p.city;
                                final displayLabel = L10nHelper.weatherPresetLabel(context, p);
                                return ChoiceChip(
                                  label: Text(displayLabel),
                                  selected: selected,
                                  onSelected: (_) async {
                                    await WeatherService.setManualCity(
                                      city: p.city,
                                      lat: p.lat,
                                      lon: p.lon,
                                    );
                                    await WeatherService.getWeather(forceRefresh: true);
                                    if (!mounted) return;
                                    setState(() {
                                      _manualWeatherCity = p.city;
                                      _customCityCtrl.text = p.city;
                                    });
                                    if (context.mounted) {
                                      toast(context, l.settingsWeatherLockedToast(displayLabel));
                                    }
                                  },
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _customCityCtrl,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: l.settingsWeatherCustomLabel,
                                    hintText: l.settingsWeatherCustomHint,
                                    prefixIcon: Icon(
                                      Icons.location_city_rounded,
                                      size: 18,
                                      color: teal,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              FilledButton.tonalIcon(
                                onPressed: _searchingCity
                                    ? null
                                    : () async {
                                        final q = _customCityCtrl.text.trim();
                                        if (q.isEmpty) return;
                                        setState(() => _searchingCity = true);
                                        try {
                                          final resolved =
                                              await WeatherService.searchAndSetManualCity(q);
                                          await WeatherService.getWeather(forceRefresh: true);
                                          if (!mounted) return;
                                          setState(() {
                                            _manualWeatherCity = resolved;
                                            _customCityCtrl.text = resolved;
                                          });
                                          if (context.mounted) {
                                            toast(context, l.settingsWeatherLockedToast(resolved));
                                          }
                                        } catch (e) {
                                          if (!mounted) return;
                                          if (context.mounted) {
                                            toast(context, e.toString().replaceAll('Exception: ', ''));
                                          }
                                        } finally {
                                          if (mounted) setState(() => _searchingCity = false);
                                        }
                                      },
                                icon: _searchingCity
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.search_rounded, size: 17),
                                label: Text(l.settingsWeatherSetBtn),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SectionTitle(
                      l.settingsChatAiSection,
                      icon: Icons.smart_toy_rounded,
                      iconColor: aiColor,
                    ),
                    SurfaceCard(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(l.settingsChatAiHint, style: AppTypography.bodySecondary(context)),
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs + 2,
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
                          const SizedBox(height: AppSpacing.md),
                          TextField(
                            controller: _chatUrl,
                            decoration: InputDecoration(
                              labelText: l.settingsBaseUrlLabel,
                              hintText: 'https://api.deepseek.com',
                              prefixIcon: Icon(Icons.link_rounded, color: primary, size: 18),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextField(
                            controller: _chatKey,
                            obscureText: _obscureChat,
                            decoration: InputDecoration(
                              labelText: l.settingsApiKeyLabel,
                              hintText: 'sk-...',
                              prefixIcon: Icon(Icons.key_rounded, color: accent, size: 18),
                              suffixIcon: IconButton(
                                icon: Icon(_obscureChat ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _obscureChat = !_obscureChat),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.xs + 2,
                            runSpacing: AppSpacing.xs + 2,
                            children: _chatModelPresets.map((m) {
                              return ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(m, style: AppTypography.badge(context)),
                                onPressed: () => setState(() => _chatModel.text = m),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            controller: _chatModel,
                            decoration: InputDecoration(
                              labelText: l.settingsModelNameLabel,
                              hintText: 'deepseek-chat / deepseek-reasoner',
                              prefixIcon: Icon(Icons.memory_rounded, color: teal, size: 18),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              onPressed: _testing ? null : () => _test(_currentChat()),
                              icon: const Icon(Icons.bolt_rounded, size: 17),
                              label: Text(_testing ? l.settingsTestingBtn : l.settingsTestConnectionBtn),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SectionTitle(
                      l.settingsVisionSection,
                      icon: Icons.camera_enhance_rounded,
                      iconColor: teal,
                    ),
                    SurfaceCard(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l.settingsVisionSameSwitch, style: AppTypography.cardTitle(context)),
                            subtitle: Text(
                              l.settingsVisionSameSub,
                              style: AppTypography.bodySecondary(context),
                            ),
                            value: _visionSame,
                            onChanged: (v) => setState(() => _visionSame = v),
                          ),
                          if (!_visionSame) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.xs + 2,
                              runSpacing: AppSpacing.xs + 2,
                              children: _visionPresets.map((p) {
                                return ActionChip(
                                  label: Text(p.$1),
                                  onPressed: () => setState(() {
                                    _visionUrl.text = p.$2;
                                    _visionModel.text = p.$3;
                                    if (_visionKey.text.isEmpty &&
                                        p.$2 == _chatUrl.text.trim()) {
                                      _visionKey.text = _chatKey.text;
                                    }
                                  }),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              controller: _visionUrl,
                              decoration: InputDecoration(
                                labelText: l.settingsVisionBaseUrlLabel,
                                prefixIcon: const Icon(Icons.link_rounded, size: 18),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              controller: _visionKey,
                              obscureText: _obscureVision,
                              decoration: InputDecoration(
                                labelText: l.settingsVisionApiKeyLabel,
                                prefixIcon: const Icon(Icons.key_rounded, size: 18),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureVision ? Icons.visibility : Icons.visibility_off,
                                  ),
                                  onPressed: () => setState(() => _obscureVision = !_obscureVision),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              controller: _visionModel,
                              decoration: InputDecoration(
                                labelText: l.settingsVisionModelLabel,
                                hintText: 'qwen-vl-max / deepseek-flash',
                                prefixIcon: const Icon(Icons.visibility_rounded, size: 18),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed: _testing ? null : () => _test(_currentVision()),
                                icon: const Icon(Icons.bolt_rounded, size: 17),
                                label: Text(
                                  _testing ? l.settingsTestingBtn : l.settingsTestVisionBtn,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: Text(l.settingsSaveAiBtn),
                          ),
                        ],
                      ),
                    ),
                    SectionTitle(
                      l.usageSectionTitle,
                      icon: Icons.bar_chart_rounded,
                      iconColor: primary,
                    ),
                    SurfaceCard(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l.usageSwitchTitle, style: AppTypography.cardTitle(context)),
                            subtitle: Text(
                              l.usageCountSub(_usageEventCount),
                              style: AppTypography.bodySecondary(context),
                            ),
                            value: _usageEnabled,
                            onChanged: (v) async {
                              await UsageTelemetryService.instance.setEnabled(v);
                              final cnt = await UsageTelemetryService.instance.getEventCount();
                              if (!mounted) return;
                              setState(() {
                                _usageEnabled = v;
                                _usageEventCount = cnt;
                              });
                            },
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: _openUsageExportDialog,
                                  icon: const Icon(Icons.ios_share_rounded, size: 17),
                                  label: Text(l.usageExportBtn),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm + 2),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  if (await confirm(context, l.usageClearConfirm)) {
                                    await UsageTelemetryService.instance.clearAll();
                                    final cnt =
                                        await UsageTelemetryService.instance.getEventCount();
                                    if (!context.mounted) return;
                                    setState(() => _usageEventCount = cnt);
                                    toast(context, l.usageClearedToast);
                                  }
                                },
                                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                                label: Text(l.usageClearBtn),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SectionTitle(
                      l.debugServerSectionTitle,
                      icon: Icons.terminal_rounded,
                      iconColor: AppColors.danger(context),
                    ),
                    _buildDeveloperDebugCard(context),
                    SectionTitle(
                      l.settingsSystemDataSection,
                      icon: Icons.security_rounded,
                      iconColor: scheduleColor,
                    ),
                    SurfaceCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _systemTile(
                            icon: Icons.calendar_month_rounded,
                            color: scheduleColor,
                            title: l.semesterSettingsTitle,
                            subtitle: _activeTerm != null
                                ? l.semesterSettingsTileSub(
                                    _activeTerm!.localizedName(isEn: context.isEnLocale),
                                    fmtDate(_activeTerm!.week1Start),
                                    _activeTerm!.totalWeeks,
                                  )
                                : l.scheduleSemesterSettingsAction,
                            trailingIcon: Icons.chevron_right_rounded,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SemesterSettingsScreen(),
                                ),
                              );
                              if (mounted) _load();
                            },
                          ),
                          const Divider(height: 1),
                          _systemTile(
                            icon: Icons.battery_charging_full_rounded,
                            color: teal,
                            title: l.batteryDiagTitle,
                            subtitle: l.batteryDiagTileSub,
                            trailingIcon: Icons.chevron_right_rounded,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const BatteryDiagnosticsScreen(),
                                ),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          _systemTile(
                            icon: Icons.widgets_rounded,
                            color: primary,
                            title: l.widgetGuideTitle,
                            subtitle: l.widgetGuideTileSub,
                            trailingIcon: Icons.add_to_home_screen_rounded,
                            onTap: () => showAddHomeWidgetGuideDialog(context),
                          ),
                          const Divider(height: 1),
                          _systemTile(
                            icon: Icons.health_and_safety_rounded,
                            color: accent,
                            title: l.settingsDiagTileTitle,
                            subtitle: l.settingsDiagTileSub,
                            trailingIcon: Icons.chevron_right_rounded,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const NotificationDiagnosticsScreen(),
                                ),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          _systemTile(
                            icon: Icons.data_object_rounded,
                            color: teal,
                            title: l.settingsExportJsonTitle,
                            subtitle: l.settingsExportJsonSub,
                            trailingIcon: Icons.ios_share_rounded,
                            onTap: _exportJson,
                          ),
                          const Divider(height: 1),
                          _systemTile(
                            icon: Icons.table_chart_rounded,
                            color: scheduleColor,
                            title: l.settingsExportCsvTitle,
                            subtitle: l.settingsExportCsvSub,
                            trailingIcon: Icons.ios_share_rounded,
                            onTap: _exportCsv,
                          ),
                          const Divider(height: 1),
                          _systemTile(
                            icon: Icons.delete_sweep_rounded,
                            color: AppColors.danger(context),
                            title: l.scheduleClearAllTitle,
                            subtitle: l.scheduleClearAllSub,
                            trailingIcon: Icons.chevron_right_rounded,
                            onTap: _confirmClearAllCourses,
                          ),
                          const Divider(height: 1),
                          _systemTile(
                            icon: Icons.info_outline_rounded,
                            color: primary,
                            title: l.settingsAboutTileTitle,
                            subtitle: l.settingsAboutTileSub,
                            trailingIcon: Icons.chevron_right_rounded,
                            customLeading: ClipRRect(
                              borderRadius: AppRadius.bMd,
                              child: Image.asset(
                                'assets/icon/dafeiyu_mascot.png',
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                              ),
                            ),
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
