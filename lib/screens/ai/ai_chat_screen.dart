import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../db/repo.dart';
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

  const _ParsedAiReply({
    required this.displayText,
    this.plan,
    this.isGeneratingPlan = false,
    this.parseFailed = false,
    this.rawFailedJson,
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
  static final _markerReg = RegExp(r'<<<PLAN_JSON>>>([\s\S]*?)<<<END_PLAN>>>');
  static final _fencedJsonReg = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```');

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
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  TrainingPlan? _tryParsePlanJson(String rawJson) {
    final j = AiService.extractJson(rawJson);
    if (j == null || j['days'] is! List) return null;
    try {
      final plan = TrainingPlan.fromJson(j);
      return plan.days.isEmpty ? null : plan;
    } catch (_) {
      return null;
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
      final plan = _tryParsePlanJson(jsonStr);
      if (plan != null) {
        return _ParsedAiReply(displayText: cleanText, plan: plan);
      } else {
        return _ParsedAiReply(
          displayText: cleanText,
          parseFailed: true,
          rawFailedJson: jsonStr,
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
        final plan = _tryParsePlanJson(candidate);
        if (plan != null) {
          return _ParsedAiReply(displayText: cleanText, plan: plan);
        } else {
          return _ParsedAiReply(
            displayText: cleanText,
            parseFailed: true,
            rawFailedJson: candidate,
          );
        }
      }
    }

    return _ParsedAiReply(displayText: content);
  }

  Future<void> _importPlan(TrainingPlan plan) async {
    await Repo.saveTrainingPlan(plan);
    UsageTelemetryService.instance.trackFeature('ai_plan_import', 'success');
    if (!mounted) return;
    setState(() {
      _importedPlanNames.add(plan.planName);
    });
    toast(context, context.l10n.aiPlanImportedToast(plan.planName));
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFFAB47BC)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      plan.planName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: plan.days.length,
                  itemBuilder: (_, di) {
                    final d = plan.days[di];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2B5B84).withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${d.day} · ${d.focus}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF2B5B84),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  l.aiPlanDayExerciseCount(d.exercises.length),
                                  style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final ex in d.exercises)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    const Icon(Icons.fitness_center_rounded, size: 14, color: Color(0xFFEF5350)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        L10nHelper.exerciseDisplayName(ctx, ex.name),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    Text(
                                      '${ex.sets} × ${ex.reps}${ex.weightHint.isNotEmpty ? ' (${ex.weightHint})' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                                      ),
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
              const SizedBox(height: 10),
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
      if (L10nHelper.isWorkoutPlanRequest(content)) {
        UsageTelemetryService.instance.trackFeature('ai_plan_import', 'tap');
        sys += L10nHelper.planSchemaPromptInstruction;
      }
      final recent = _messages.length > 16 ? _messages.sublist(_messages.length - 16) : _messages;
      final reply = await AiService.chat(systemPrompt: sys, history: recent);
      final aiMsg = ChatMessage(role: 'assistant', content: reply);
      await Repo.addChatMessage(aiMsg);
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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final quickPrompts = <(String, String)>[
      (l.aiQuickGeneratePlan, l.aiPromptGeneratePlan),
      (l.aiQuickTodaySummary, l.aiPromptTodaySummary),
      (l.aiQuickWeekSummary, l.aiPromptWeekSummary),
      (l.aiQuickNextMeal, l.aiPromptNextMeal),
    ];

    final mdStyle = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      code: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      codeblockPadding: const EdgeInsets.all(10),
      codeblockDecoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFAB47BC).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smart_toy_rounded, color: Color(0xFFAB47BC), size: 20),
            ),
            const SizedBox(width: 10),
            Text(l.aiTitle),
          ],
        ),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: l.aiClearChatTooltip,
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: () async {
                if (await confirm(context, l.aiClearChatConfirm)) {
                  await Repo.clearChat();
                  _load();
                }
              },
            ),
          IconButton(
            tooltip: l.aiSettingsTooltip,
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: quickPrompts.map((p) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFFAB47BC)),
                    label: Text(p.$1),
                    onPressed: _sending ? null : () => _send(p.$2),
                  ),
                );
              }).toList(),
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
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                          ),
                        );
                      }
                      final m = _messages[i];
                      final isUser = m.role == 'user';
                      final parsed = isUser ? null : _parseReplyContent(m.content);

                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isUser ? cs.primaryContainer : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: isUser
                              ? SelectableText(m.content)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (parsed!.displayText.isNotEmpty)
                                      MarkdownBody(
                                        data: parsed.displayText,
                                        selectable: true,
                                        styleSheet: mdStyle,
                                        builders: {
                                          'pre': _HorizontalScrollPreBuilder(cs.surface),
                                        },
                                      ),
                                    if (parsed.isGeneratingPlan) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            l.aiPlanGeneratingPlaceholder,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (parsed.plan != null) ...[
                                      if (parsed.displayText.isNotEmpty) const SizedBox(height: 10),
                                      _buildPlanSummaryCard(parsed.plan!),
                                    ],
                                    if (parsed.parseFailed) ...[
                                      const SizedBox(height: 8),
                                      _buildParseFailedCollapse(i, parsed.rawFailedJson ?? m.content),
                                    ],
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: l.aiInputHint,
                        prefixIcon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(_input.text),
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18, color: Color(0xFFFF7A22)),
                const SizedBox(width: 6),
                Text(
                  l.aiPlanCardHeader,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF7A22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              plan.planName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            for (final d in plan.days)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text(
                      d.day,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d.focus,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.aiPlanDayExerciseCount(d.exercises.length),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showPlanDetailsSheet(plan),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: Text(l.aiPlanViewDetailsBtn, style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isImported ? null : () => _importPlan(plan),
                    icon: Icon(
                      isImported ? Icons.check_rounded : Icons.download_done_rounded,
                      size: 16,
                    ),
                    label: Text(
                      isImported ? l.aiPlanImportedDoneBtn : l.aiPlanImportBtn,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 1.3 兜底：JSON 解析失败时默认折叠原文，提供「显示原始回复」按钮
  Widget _buildParseFailedCollapse(int msgIdx, String rawText) {
    final l = context.l10n;
    final expanded = _expandedRawMsgIndices.contains(msgIdx);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 15, color: Colors.orange),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l.aiPlanParseFailedHint,
                style: const TextStyle(fontSize: 12),
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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                rawText,
                style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
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
  _HorizontalScrollPreBuilder(this.bgColor);

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
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          text,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.4),
        ),
      ),
    );
  }
}
