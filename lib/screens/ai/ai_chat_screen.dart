import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../db/repo.dart';
import '../../models/models.dart';
import '../../services/ai_service.dart';
import '../../services/context_builder.dart';
import '../../widgets/common.dart';
import '../settings/settings_screen.dart';

/// AI 助手：自动注入用户的身体资料、运动问卷、近7天饮食、近14天训练和本周课表
/// 支持生成结构化 JSON 训练计划并「一键导入到训练模块」
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

  static const _planJsonPrompt = '''
请根据我的个人档案（目标、运动经验、每周可训练天数、单次时长、可用器械、伤病限制）以及本周课表空闲时间，为我定制一份周训练计划。
要求：先用简短文字说明计划思路，然后在回复末尾附上严格的 JSON 代码块（格式如下，不要省略字段）：
```json
{
  "plan_name": "计划名称，例如：推拉腿·三分化增肌计划",
  "days": [
    {
      "day": "周一",
      "focus": "推（胸/肩/三头）",
      "exercises": [
        {"name": "杠铃卧推", "sets": 4, "reps": "8-10", "weight_hint": "60kg"},
        {"name": "哑铃推举", "sets": 3, "reps": "10-12", "weight_hint": "16kg"}
      ]
    }
  ]
}
```''';

  static const _quickPrompts = <(String, String)>[
    ('生成训练计划(可导入)', _planJsonPrompt),
    ('今日总结', '请结合我今天的饮食和训练记录做个简短点评，并告诉我接下来一餐怎么吃最合适。'),
    ('本周总结', '请总结我近7天的热量摄入、营养素比例和训练情况，指出做得好的地方和需要改进的地方。'),
    ('下一餐吃什么', '根据我今天剩余的热量和三大营养素缺口，给我推荐2-3个中国常见、容易买到的餐食方案。'),
  ];

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
    toast(context, '已导入「${plan.planName}」！去「训练」页点击对应分化即可直接按计划开练 💪');
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
      if (content.contains('训练计划') || content.contains('计划')) {
        sys += '\n当用户请求制定训练计划时，请在文字说明后附带格式为 {"plan_name":"...","days":[{"day":"...","focus":"...","exercises":[{"name":"...","sets":4,"reps":"8-10","weight_hint":"..."}]}]} 的 JSON 代码块，方便用户一键导入。';
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
    final cs = Theme.of(context).colorScheme;
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
            const Text('AI 健康助手'),
          ],
        ),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: '清空对话',
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: () async {
                if (await confirm(context, '清空全部聊天记录？')) {
                  await Repo.clearChat();
                  _load();
                }
              },
            ),
          IconButton(
            tooltip: 'AI 设置',
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
              children: _quickPrompts.map((p) {
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
                      text: 'AI 会自动读取你的身体档案、饮食、训练和课表\n点上方「生成训练计划(可导入)」即可定制专属计划并一键放入训练页',
                      actionLabel: '生成我的专属训练计划',
                      onAction: () => _send(_planJsonPrompt),
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
                                        label: Text('导入到训练计划（${parsedPlan.planName}）'),
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
                      decoration: const InputDecoration(
                        hintText: '问问饮食、训练，或说“帮我生成训练计划”…',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded, size: 18),
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
