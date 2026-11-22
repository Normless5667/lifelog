import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../db/repo.dart';
import '../../debug/debug_server.dart';
import '../../models/models.dart';
import '../../services/ai_service.dart';
import '../../services/context_builder.dart';
import '../../services/usage_telemetry_service.dart';
import '../../widgets/common.dart';
import '../settings/settings_screen.dart';

/// 解析 AI 回复中的训练计划标记与展示正文
class _ParsedAiReply {
  final String displayText;
  final TrainingPlan? plan;
  final bool isGeneratingPlan;
  final bool parseFailed;
  final String? rawFailedJson;
  final String? parseError;

  const _ParsedAiReply({
    required this.displayText,
    this.plan,
    this.isGeneratingPlan = false,
    this.parseFailed = false,
    this.rawFailedJson,
    this.parseError,
  });
}

/// AI 助手（v1.7 P0）：
/// - 自动注入用户的身体资料、运动问卷、近7天饮食、近14天训练和本周课表
/// - 使用 <<<PLAN_JSON>>>...<<<END_PLAN>>> 标记（并兼容历史 ```json 代码块）剥离原始 JSON，
///   在聊天气泡内渲染「已生成训练计划」卡片（支持「查看详情」底部弹窗与「导入到训练 / 已导入 ✓」状态切换）
/// - JSON 解析失败时自动折叠原文并提供「显示原始回复」按钮；未收到 <<<END_PLAN>>> 前显示「正在生成计划…」占位
/// - 所有代码块均包一层横向 SingleChildScrollView + 12号字体，杜绝横向撑破屏幕
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  static final _markerReg = RegExp(
    r'<<<\s*PLAN_JSON\s*>>>([\s\S]*?)<<<\s*END_PLAN\s*>>>',
    caseSensitive: false,
  );
  static final _fencedJsonReg = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```', caseSensitive: false);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = [];
  final Set<String> _importedPlanNames = {};
  final Set<int> _expandedRawMsgIndices = {};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await Repo.getChatMessages();
    final activePlan = await Repo.getTrainingPlan();
    if (!mounted) return;
    setState(() {
      _messages = list;
      if (activePlan != null) {
        _importedPlanNames.add(activePlan.planName);
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final maxExtent = _scroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(maxExtent);
      } else {
        _scroll.animateTo(
          maxExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  ({TrainingPlan? plan, String? error}) _tryParsePlanJson(String rawJson) {
    final j = AiService.extractJson(rawJson);
    if (j == null) {
      return (plan: null, error: 'extractJson_returned_null(len=${rawJson.length})');
    }
    if (j['days'] is! List) {
      return (plan: null, error: 'missing_or_invalid_days_field');
    }
    try {
      final plan = TrainingPlan.fromJson(j);
      if (plan.days.isEmpty) {
        return (plan: null, error: 'parsed_plan_days_empty');
      }
      return (plan: plan, error: null);
    } catch (e) {
      return (plan: null, error: 'TrainingPlan.fromJson: $e');
    }
  }

  /// 从 AI 回复中提取并剥离 JSON 计划部分，保证原始 JSON 不直接铺在聊天气泡里
  _ParsedAiReply _parseReplyContent(String content) {
    // 1. 优先匹配 <<<PLAN_JSON>>>...<<<END_PLAN>>>
    final markerMatch = _markerReg.firstMatch(content);
    if (markerMatch != null) {
      final jsonStr = (markerMatch.group(1) ?? '').trim();
      var cleanText = content.replaceAll(markerMatch.group(0)!, '').trim();
      // 清理可能包裹在标记外层的空代码块符号
      cleanText = cleanText.replaceAll(RegExp(r'```(?:json)?\s*```'), '').trim();
      final res = _tryParsePlanJson(jsonStr);
      if (res.plan != null) {
        return _ParsedAiReply(displayText: cleanText, plan: res.plan);
      } else {
        return _ParsedAiReply(
          displayText: cleanText,
          parseFailed: true,
          rawFailedJson: jsonStr,
          parseError: res.error,
        );
      }
    }

    // 2. 流式输出中：已收到 <<<PLAN_JSON>>> 但尚未收到 <<<END_PLAN>>>
    final startIdx = content.indexOf('<<<PLAN_JSON>>>');
    if (startIdx >= 0) {
      final cleanText = content.substring(0, startIdx).trim();
      return _ParsedAiReply(
        displayText: cleanText,
        isGeneratingPlan: true,
      );
    }

    // 3. 兼容历史对话中的 ```json { "plan_name": ..., "days": [...] } ``` 代码块
    for (final m in _fencedJsonReg.allMatches(content)) {
      final candidate = m.group(1) ?? '';
      if (candidate.contains('"plan_name"') || candidate.contains('"days"')) {
        final cleanText = content.replaceAll(m.group(0)!, '').trim();
        final res = _tryParsePlanJson(candidate);
        if (res.plan != null) {
          return _ParsedAiReply(displayText: cleanText, plan: res.plan);
        } else {
          return _ParsedAiReply(
            displayText: cleanText,
            parseFailed: true,
            rawFailedJson: candidate,
            parseError: res.error,
          );
        }
      }
    }

    // 4. 兜底兼容：AI 未加标记与代码块但直接输出了含 plan_name 与 days 的 JSON 对象
    if (content.contains('"plan_name"') && content.contains('"days"')) {
      final startBrace = content.indexOf('{');
      final endBrace = content.lastIndexOf('}');
      if (startBrace >= 0 && endBrace > startBrace) {
        final jsonCandidate = content.substring(startBrace, endBrace + 1);
        final res = _tryParsePlanJson(jsonCandidate);
        if (res.plan != null) {
          final cleanText = (content.substring(0, startBrace) + content.substring(endBrace + 1)).trim();
          return _ParsedAiReply(displayText: cleanText, plan: res.plan);
        } else {
          return _ParsedAiReply(
            displayText: content,
            parseFailed: true,
            rawFailedJson: jsonCandidate,
            parseError: res.error,
          );
        }
      }
    }

    return _ParsedAiReply(displayText: content);
  }

  Future<void> _importPlan(TrainingPlan plan) async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    UsageTelemetryService.instance.trackFeature('ai_plan_import', 'tap');
    if (plan.planName.trim().isEmpty || plan.days.isEmpty) {
      final dur = DateTime.now().millisecondsSinceEpoch - t0;
      const err = 'invalid_plan_empty_name_or_days';
      UsageTelemetryService.instance.trackFeature(
        'ai_plan_import',
        'fail',
        durationMs: dur,
        stage: 'parse',
        errorMsg: err,
      );
      if (mounted) {
        showAiError(context, AiException(context.l10n.aiPlanParseFailedHint));
      }
      return;
    }
    try {
      await Repo.saveTrainingPlan(plan);
      final dur = DateTime.now().millisecondsSinceEpoch - t0;
      UsageTelemetryService.instance.trackFeature('ai_plan_import', 'success', durationMs: dur);
      if (!mounted) return;
      setState(() {
        _importedPlanNames.add(plan.planName);
      });
      toast(context, context.l10n.aiPlanImportedToast(plan.planName));
    } catch (e, st) {
      final dur = DateTime.now().millisecondsSinceEpoch - t0;
      UsageTelemetryService.instance.trackFeature(
        'ai_plan_import',
        'fail',
        durationMs: dur,
        stage: 'save',
        errorMsg: '$e',
      );
      DebugServer.instance.logError('AiPlan', e, st, 'saveTrainingPlan failed');
      if (!mounted) return;
      showAiError(context, e);
    }
  }

  void _showPlanDetailsSheet(TrainingPlan plan) {
    final l = context.l10n;
    final isImported = _importedPlanNames.contains(plan.planName);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        minChildSize: 0.45,
        builder: (ctx, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.softBg(ctx, AppColors.moduleAi(ctx)),
                      borderRadius: AppRadius.bMd,
                    ),
                    child: Icon(Icons.auto_awesome_rounded, color: AppColors.moduleAi(ctx), size: 18),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      plan.planName,
                      style: AppTypography.sectionTitle(ctx),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: plan.days.length,
                  itemBuilder: (_, di) {
                    final d = plan.days[di];
                    final primary = AppColors.primary(ctx);
                    final workoutColor = AppColors.moduleWorkout(ctx);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.softBg(ctx, primary),
                                      borderRadius: AppRadius.bXs,
                                    ),
                                    child: Text(
                                      '${d.day} · ${d.focus}',
                                      style: AppTypography.badge(ctx, color: primary).copyWith(fontSize: 12.5),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  l.aiPlanDayExerciseCount(d.exercises.length),
                                  style: AppTypography.caption(ctx),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            for (final ex in d.exercises)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(color: workoutColor, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        L10nHelper.exerciseDisplayName(ctx, ex.name),
                                        style: AppTypography.subtitle(ctx).copyWith(fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      '${ex.sets} × ${ex.reps}${ex.weightHint.isNotEmpty ? ' (${ex.weightHint})' : ''}',
                                      style: AppTypography.badge(ctx),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: isImported
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _importPlan(plan);
                      },
                icon: Icon(isImported ? Icons.check_rounded : Icons.download_done_rounded),
                label: Text(isImported ? l.aiPlanImportedDoneBtn : l.aiPlanImportBtn),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send(String text) async {
    final content = text.trim();
    if (content.isEmpty || _sending) return;
    _input.clear();

    final userMsg = ChatMessage(role: 'user', content: content);
    await Repo.addChatMessage(userMsg);
    setState(() {
      _messages.add(userMsg);
      _sending = true;
    });
    _scrollToBottom();

    try {
      var sys = await ContextBuilder.buildSystemPrompt();
      final isPlanReq = L10nHelper.isWorkoutPlanRequest(content);
      if (isPlanReq) {
        sys += L10nHelper.planSchemaPromptInstruction;
      }
      final recent = _messages.length > 16 ? _messages.sublist(_messages.length - 16) : _messages;
      final reply = await AiService.chat(
        systemPrompt: sys,
        history: recent,
        maxTokens: isPlanReq ? 3500 : 2000,
      );
      final aiMsg = ChatMessage(role: 'assistant', content: reply);
      await Repo.addChatMessage(aiMsg);
      // 及时捕捉训练计划 JSON 解析失败阶段（stage=parse），避免静默失败漏报
      final parsedPlanReply = _parseReplyContent(reply);
      if (parsedPlanReply.parseFailed ||
          (isPlanReq && parsedPlanReply.plan == null && !parsedPlanReply.isGeneratingPlan)) {
        final reason = parsedPlanReply.parseError ??
            (isPlanReq ? 'plan_json_missing_or_truncated' : 'plan_parse_failed');
        UsageTelemetryService.instance.trackFeature(
          'ai_plan_import',
          'fail',
          stage: 'parse',
          errorMsg: reason,
        );
      }
      if (!mounted) return;
      setState(() {
        _messages.add(aiMsg);
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showAiError(
        context,
        e,
        onOpenSettings: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
      );
    }
  }

  Widget _appBarActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surfaceSubtle(context),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.all(AppSpacing.sm),
        ),
        icon: Icon(icon, size: 19, color: AppColors.textPrimary(context)),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final aiColor = AppColors.moduleAi(context);
    final primary = AppColors.primary(context);
    final surfaceSubtle = AppColors.surfaceSubtle(context);
    final borderColor = AppColors.border(context);

    final quickPrompts = <(String, String)>[
      (l.aiQuickGeneratePlan, l.aiPromptGeneratePlan),
      (l.aiQuickTodaySummary, l.aiPromptTodaySummary),
      (l.aiQuickWeekSummary, l.aiPromptWeekSummary),
      (l.aiQuickNextMeal, l.aiPromptNextMeal),
    ];

    final mdStyle = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: AppTypography.body(context, color: AppColors.textPrimary(context)),
      strong: AppTypography.body(context, color: AppColors.textPrimary(context))
          .copyWith(fontWeight: FontWeight.w700),
      h1: AppTypography.pageTitle(context),
      h2: AppTypography.sectionTitle(context),
      h3: AppTypography.cardTitle(context),
      listBullet: AppTypography.body(context, color: aiColor).copyWith(fontWeight: FontWeight.w700),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.softBg(context, primary, lightAlpha: 0.08, darkAlpha: 0.14),
        borderRadius: AppRadius.bSm,
        border: Border(left: BorderSide(color: primary, width: 3)),
      ),
      code: TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        color: AppColors.textPrimary(context),
        backgroundColor: surfaceSubtle,
      ),
      codeblockPadding: const EdgeInsets.all(AppSpacing.md),
      codeblockDecoration: BoxDecoration(
        color: surfaceSubtle,
        borderRadius: AppRadius.bSm,
        border: Border.all(color: borderColor),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.softBg(context, aiColor, lightAlpha: 0.12, darkAlpha: 0.20),
                borderRadius: AppRadius.bSm,
                border: Border.all(color: AppColors.softBorder(context, aiColor)),
              ),
              child: Icon(Icons.smart_toy_rounded, color: aiColor, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                l.aiTitle,
                style: AppTypography.pageTitle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_messages.isNotEmpty)
            _appBarActionButton(
              tooltip: l.aiClearChatTooltip,
              icon: Icons.delete_sweep_rounded,
              onPressed: () async {
                if (await confirm(context, l.aiClearChatConfirm)) {
                  await Repo.clearChat();
                  _load();
                }
              },
            ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: _appBarActionButton(
              tooltip: l.aiSettingsTooltip,
              icon: Icons.settings_rounded,
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 快捷指令横条
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs + 2,
              ),
              itemCount: quickPrompts.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (_, idx) {
                final p = quickPrompts[idx];
                return ActionChip(
                  avatar: Icon(Icons.auto_awesome_rounded, size: 15, color: aiColor),
                  label: Text(
                    p.$1,
                    style: AppTypography.badge(context, color: AppColors.textPrimary(context))
                        .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: AppColors.surface(context),
                  side: BorderSide(color: AppColors.softBorder(context, aiColor)),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.bPill),
                  onPressed: _sending ? null : () => _send(p.$2),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: EmptyHint(
                      icon: Icons.smart_toy_rounded,
                      text: l.aiEmptyHint,
                      actionLabel: l.aiEmptyActionBtn,
                      onAction: () => _send(l.aiPromptGeneratePlan),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface(context),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(AppRadius.lg),
                                topRight: const Radius.circular(AppRadius.lg),
                                bottomRight: const Radius.circular(AppRadius.lg),
                                bottomLeft: const Radius.circular(AppRadius.xs),
                              ),
                              border: Border.all(color: borderColor),
                              boxShadow: AppShadows.subtle(context),
                            ),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: aiColor,
                              ),
                            ),
                          ),
                        );
                      }
                      final m = _messages[i];
                      final isUser = m.role == 'user';
                      final parsed = isUser ? null : _parseReplyContent(m.content);
                      final isMidnight = AppColors.isMidnight(context);
                      final bubbleR = isMidnight ? 24.0 : AppRadius.lg;
                      final tailR = isMidnight ? 8.0 : AppRadius.xs;

                      final bubbleRadius = BorderRadius.only(
                        topLeft: Radius.circular(bubbleR),
                        topRight: Radius.circular(bubbleR),
                        bottomLeft: Radius.circular(isUser ? bubbleR : tailR),
                        bottomRight: Radius.circular(isUser ? tailR : bubbleR),
                      );

                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
                          margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md + 2,
                            vertical: AppSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            color: isMidnight
                                ? (isUser
                                    ? AppColors.surfaceSubtle(context)
                                    : AppColors.surface(context).withValues(alpha: 0.88))
                                : (isUser
                                    ? AppColors.softBg(context, primary, lightAlpha: 0.11, darkAlpha: 0.22)
                                    : AppColors.surface(context)),
                            borderRadius: bubbleRadius,
                            border: isMidnight
                                ? null
                                : Border.all(
                                    color: isUser
                                        ? AppColors.softBorder(context, primary, lightAlpha: 0.24, darkAlpha: 0.34)
                                        : borderColor.withValues(alpha: AppColors.isDark(context) ? 0.8 : 0.9),
                                  ),
                            boxShadow: isMidnight ? const [] : AppShadows.subtle(context),
                          ),
                          child: isUser
                              ? SelectableText(
                                  m.content,
                                  style: AppTypography.body(
                                    context,
                                    color: AppColors.textPrimary(context),
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (parsed!.displayText.isNotEmpty)
                                      MarkdownBody(
                                        data: parsed.displayText,
                                        selectable: true,
                                        styleSheet: mdStyle,
                                        builders: {
                                          'pre': _HorizontalScrollPreBuilder(surfaceSubtle, borderColor),
                                        },
                                      ),
                                    if (parsed.isGeneratingPlan) ...[
                                      const SizedBox(height: AppSpacing.sm),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.md,
                                          vertical: AppSpacing.sm,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.softBg(context, aiColor),
                                          borderRadius: AppRadius.bMd,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: aiColor,
                                              ),
                                            ),
                                            const SizedBox(width: AppSpacing.sm),
                                            Flexible(
                                              child: Text(
                                                l.aiPlanGeneratingPlaceholder,
                                                style: AppTypography.badge(context, color: aiColor),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (parsed.plan != null) ...[
                                      if (parsed.displayText.isNotEmpty)
                                        const SizedBox(height: AppSpacing.md),
                                      _buildPlanSummaryCard(parsed.plan!),
                                    ],
                                    if (parsed.parseFailed) ...[
                                      const SizedBox(height: AppSpacing.sm),
                                      _buildParseFailedCollapse(
                                        i,
                                        parsed.rawFailedJson ?? m.content,
                                        parseError: parsed.parseError,
                                      ),
                                    ],
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.isMidnight(context)
                  ? Colors.transparent
                  : AppColors.surface(context),
              border: AppColors.isMidnight(context)
                  ? null
                  : Border(top: BorderSide(color: borderColor)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm + 2,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        style: AppTypography.body(context, color: AppColors.textPrimary(context)),
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        decoration: InputDecoration(
                          hintText: l.aiInputHint,
                          filled: true,
                          fillColor: AppColors.surfaceSubtle(context),
                          prefixIcon: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: AppColors.textTertiary(context),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: AppColors.isMidnight(context)
                                ? BorderRadius.circular(28)
                                : AppRadius.bLg,
                            borderSide: AppColors.isMidnight(context)
                                ? BorderSide.none
                                : BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: AppColors.isMidnight(context)
                                ? BorderRadius.circular(28)
                                : AppRadius.bLg,
                            borderSide: AppColors.isMidnight(context)
                                ? BorderSide.none
                                : BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: AppColors.isMidnight(context)
                                ? BorderRadius.circular(28)
                                : AppRadius.bLg,
                            borderSide: BorderSide(color: aiColor, width: 1.6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.filled(
                      onPressed: _sending ? null : () => _send(_input.text),
                      style: IconButton.styleFrom(
                        backgroundColor: aiColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(44, 44),
                        shape: AppColors.isMidnight(context)
                            ? const CircleBorder()
                            : RoundedRectangleBorder(borderRadius: AppRadius.bMd),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 1.2 「已生成训练计划」结构化卡片（替代原始 JSON 铺屏）
  Widget _buildPlanSummaryCard(TrainingPlan plan) {
    final l = context.l10n;
    final isImported = _importedPlanNames.contains(plan.planName);
    final accent = AppColors.accent(context);
    final primary = AppColors.primary(context);
    final success = AppColors.success(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle(context),
        borderRadius: AppRadius.bLg,
        border: Border.all(color: AppColors.softBorder(context, accent)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.softBg(context, accent, lightAlpha: 0.14, darkAlpha: 0.22),
                  borderRadius: AppRadius.bPill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 13, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      l.aiPlanCardHeader,
                      style: AppTypography.badge(context, color: accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            plan.planName,
            style: AppTypography.cardTitle(context),
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          for (final d in plan.days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.softBg(context, primary),
                      borderRadius: AppRadius.bXs,
                    ),
                    child: Text(
                      d.day,
                      style: AppTypography.badge(context, color: primary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      d.focus,
                      style: AppTypography.subtitle(context).copyWith(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    l.aiPlanDayExerciseCount(d.exercises.length),
                    style: AppTypography.caption(context),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showPlanDetailsSheet(plan),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surface(context),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 15),
                  label: Text(
                    l.aiPlanViewDetailsBtn,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: isImported ? null : () => _importPlan(plan),
                  style: FilledButton.styleFrom(
                    backgroundColor: isImported ? AppColors.softBg(context, success) : primary,
                    foregroundColor: isImported ? success : Colors.white,
                    disabledBackgroundColor: AppColors.softBg(context, success),
                    disabledForegroundColor: success,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.bMd),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
                  ),
                  icon: Icon(
                    isImported ? Icons.check_rounded : Icons.download_done_rounded,
                    size: 15,
                  ),
                  label: Text(
                    isImported ? l.aiPlanImportedDoneBtn : l.aiPlanImportBtn,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 1.3 兜底：JSON 解析失败时默认折叠原文，提供「显示原始回复」按钮并展示失败原因
  Widget _buildParseFailedCollapse(
    int msgIdx,
    String rawText, {
    String? parseError,
  }) {
    final l = context.l10n;
    final expanded = _expandedRawMsgIndices.contains(msgIdx);
    final warning = AppColors.warning(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 15, color: warning),
            const SizedBox(width: AppSpacing.xs + 2),
            Expanded(
              child: Text(
                parseError != null && parseError.isNotEmpty
                    ? '${l.aiPlanParseFailedHint} ($parseError)'
                    : l.aiPlanParseFailedHint,
                style: AppTypography.bodySecondary(context),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  if (expanded) {
                    _expandedRawMsgIndices.remove(msgIdx);
                  } else {
                    _expandedRawMsgIndices.add(msgIdx);
                  }
                });
              },
              child: Text(
                expanded ? l.aiPlanHideRawReplyBtn : l.aiPlanShowRawReplyBtn,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        if (expanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle(context),
              borderRadius: AppRadius.bSm,
              border: Border.all(color: AppColors.border(context)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                rawText,
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 1.4 自定义 Markdown 代码块渲染器：用横向 SingleChildScrollView 包裹，防止任何长代码撑破屏幕
class _HorizontalScrollPreBuilder extends MarkdownElementBuilder {
  final Color bgColor;
  final Color borderColor;
  _HorizontalScrollPreBuilder(this.bgColor, this.borderColor);

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent.trimRight();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppRadius.bSm,
        border: Border.all(color: borderColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          text,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            height: 1.45,
            color: AppColors.textPrimary(context),
          ),
        ),
      ),
    );
  }
}
