import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/ai_service.dart';
import '../../services/context_builder.dart';
import '../../widgets/common.dart';
import '../settings/settings_screen.dart';

/// AI 助手：自动注入用户的身体资料、运动问卷、近7天饮食、近14天训练和本周课表
/// 支持生成结构化 JSON 训练计划并一键导入到训练模块
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = [];
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
    if (!mounted) return;
    setState(() => _messages = list);
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

  TrainingPlan? _tryParsePlan(String content) {
    if (!content.contains('"plan_name"') && !content.contains('"days"')) return null;
    final j = AiService.extractJson(content);
    if (j == null || j['days'] is! List) return null;
    try {
      final plan = TrainingPlan.fromJson(j);
      return plan.days.isEmpty ? null : plan;
    } catch (_) {
      return null;
    }
  }

  Future<void> _importPlan(TrainingPlan plan) async {
    await Repo.saveTrainingPlan(plan);
    if (!mounted) return;
    toast(context, context.l10n.aiPlanImportedToast(plan.planName));
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
                      final parsedPlan = isUser ? null : _tryParsePlan(m.content);
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
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
                                    MarkdownBody(data: m.content, selectable: true),
                                    if (parsedPlan != null) ...[
                                      const SizedBox(height: 10),
                                      FilledButton.icon(
                                        onPressed: () => _importPlan(parsedPlan),
                                        icon: const Icon(Icons.download_done_rounded),
                                        label: Text(l.aiImportPlanBtn(parsedPlan.planName)),
                                      ),
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
}
