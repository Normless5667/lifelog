import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'settings_service.dart';

class AiException implements Exception {
  final String message;
  final bool needsConfig;
  AiException(this.message, {this.needsConfig = false});
  @override
  String toString() => message;
}

/// OpenAI 兼容 Chat Completions 客户端（DeepSeek / 通义千问 / Kimi 等均可）。
class AiService {
  AiService._();

  static const _timeout = Duration(seconds: 120);

  static String normalizeBaseUrl(String raw) {
    var b = raw.trim();
    if (b.isEmpty) return 'https://api.deepseek.com';
    final lower = b.toLowerCase();
    if (lower == 'deepseek') return 'https://api.deepseek.com';
    if (lower == 'openai') return 'https://api.openai.com/v1';
    if (lower == 'qwen' || lower == 'dashscope' || lower == '通义' || lower == '通义千问') {
      return 'https://dashscope.aliyuncs.com/compatible-mode/v1';
    }
    if (!b.startsWith('http://') && !b.startsWith('https://')) {
      b = 'https://$b';
    }
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  static Uri _endpoint(String baseUrl) {
    var b = normalizeBaseUrl(baseUrl);
    if (b.endsWith('/chat/completions')) return Uri.parse(b);
    return Uri.parse('$b/chat/completions');
  }

  static Future<String> _complete(AiConfig cfg, List<Map<String, dynamic>> messages,
      {double temperature = 0.7, int maxTokens = 2000}) async {
    if (!cfg.isReady) {
      throw AiException('还没有配置 AI 接口，请先到「设置」里填写 API Key', needsConfig: true);
    }
    final http.Response resp;
    try {
      resp = await http
          .post(
            _endpoint(cfg.baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${cfg.apiKey.trim()}',
            },
            body: jsonEncode({
              'model': cfg.model.trim(),
              'messages': messages,
              'temperature': temperature,
              'max_tokens': maxTokens,
              'stream': false,
            }),
          )
          .timeout(_timeout);
    } on SocketException {
      throw AiException('网络连接失败，请检查网络');
    } on HttpException catch (e) {
      throw AiException('网络错误：${e.message}');
    } on Exception catch (e) {
      if (e.toString().contains('TimeoutException')) throw AiException('请求超时，请稍后再试');
      throw AiException('请求失败：$e');
    }

    final body = utf8.decode(resp.bodyBytes);
    if (resp.statusCode != 200) {
      String detail = body;
      try {
        final j = jsonDecode(body);
        detail = (j['error']?['message'] ?? body).toString();
      } catch (_) {}
      if (detail.length > 300) detail = '${detail.substring(0, 300)}…';
      switch (resp.statusCode) {
        case 401:
          throw AiException('API Key 无效（401），请到设置里检查', needsConfig: true);
        case 402:
          throw AiException('账户余额不足（402），请充值');
        case 429:
          throw AiException('请求太频繁或额度用完（429），请稍后再试');
        default:
          throw AiException('AI 接口错误（${resp.statusCode}）：$detail');
      }
    }
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final content = j['choices'][0]['message']['content'];
      return (content ?? '').toString().trim();
    } catch (_) {
      throw AiException('无法解析 AI 返回内容');
    }
  }

  /// 普通对话。[history] 为 user/assistant 交替的消息。
  static Future<String> chat({
    required String systemPrompt,
    required List<ChatMessage> history,
  }) async {
    final cfg = await SettingsService.chatConfig();
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ...history.map((m) => {'role': m.role, 'content': m.content}),
    ];
    return _complete(cfg, messages);
  }

  /// 测试连接，返回模型回复
  static Future<String> testConfig(AiConfig cfg) =>
      _complete(cfg, [
        {'role': 'user', 'content': '你好，请只回复“连接成功”四个字。'}
      ], maxTokens: 20, temperature: 0);

  static const _foodJsonSpec = '''
请只输出一个 JSON 对象，不要输出任何其他文字，格式如下：
{"foods":[{"name":"食物名称","amount":"估计份量，如 1碗约300g","calories":数字(千卡),"protein":数字(克),"carbs":数字(克),"fat":数字(克)}],"note":"一句话说明或建议"}
要求：按中国常见做法和份量估算；有多种食物时分别列出；数字只写数值不带单位。''';

  /// 拍照识别食物热量。[imageFile] 应已压缩（image_picker 限制尺寸）。
  static Future<({List<FoodEstimate> foods, String note})> analyzeFoodImage(File imageFile,
      {String? hint}) async {
    final cfg = await SettingsService.visionConfig();
    final bytes = await imageFile.readAsBytes();
    final b64 = base64Encode(bytes);
    final text = '你是专业营养师。请识别这张照片里的食物，估算每种食物的份量和营养成分。'
        '${hint != null && hint.trim().isNotEmpty ? '\n用户补充说明：$hint' : ''}\n$_foodJsonSpec';
    final reply = await _complete(cfg, [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': text},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$b64'}
          },
        ],
      }
    ], temperature: 0.2);
    return _parseFoods(reply);
  }

  /// 文字描述估算热量（使用对话模型）
  static Future<({List<FoodEstimate> foods, String note})> estimateFoodText(String description) async {
    final cfg = await SettingsService.chatConfig();
    final reply = await _complete(cfg, [
      {'role': 'system', 'content': '你是专业营养师，擅长估算中国常见食物的热量与营养成分。'},
      {'role': 'user', 'content': '我吃了：$description\n$_foodJsonSpec'},
    ], temperature: 0.2);
    return _parseFoods(reply);
  }

  static ({List<FoodEstimate> foods, String note}) _parseFoods(String reply) {
    final j = extractJson(reply);
    if (j == null) throw AiException('AI 返回格式不正确，请重试。\n原始回复：$reply');
    final list = (j['foods'] as List?) ?? const [];
    final foods = list
        .whereType<Map>()
        .map((e) => FoodEstimate.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (foods.isEmpty) throw AiException('没有识别到食物，请换个角度重拍或用文字描述');
    return (foods: foods, note: (j['note'] ?? '').toString());
  }

  static const _scheduleJsonSpec = '''
请只输出一个 JSON 对象，不要输出任何其他文字，格式如下：
{"courses":[{"name":"课程名","teacher":"老师姓名(没有则空字符串)","location":"教室(没有则空字符串)","weekday":1到7的整数(1=周一,7=周日),"start_section":开始节次整数(从1开始),"end_section":结束节次整数,"start_week":起始周整数(默认1),"end_week":结束周整数(默认16),"week_type":0或1或2(0=每周,1=单周,2=双周)}]}
要求：如果同一门课在一周有多次或不同周段，拆成多条记录；weekday 必须是 1~7，start_section <= end_section。''';

  /// 拍课表截图导入（使用识图模型）
  static Future<List<Course>> parseScheduleImage(File imageFile, {String? hint}) async {
    final cfg = await SettingsService.visionConfig();
    final bytes = await imageFile.readAsBytes();
    final b64 = base64Encode(bytes);
    final text = '请识别这张课程表截图中的所有课程信息。'
        '${hint != null && hint.trim().isNotEmpty ? '\n补充说明：$hint' : ''}\n$_scheduleJsonSpec';
    final reply = await _complete(cfg, [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': text},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$b64'}
          },
        ],
      }
    ], temperature: 0.1, maxTokens: 3500);
    return _parseCourses(reply);
  }

  /// 粘贴教务文字或 JSON 导入课表（使用对话模型）
  static Future<List<Course>> parseScheduleText(String rawText) async {
    final cfg = await SettingsService.chatConfig();
    final reply = await _complete(cfg, [
      {'role': 'system', 'content': '你是教务课表解析助手，擅长从杂乱文本、表格或 JSON 中提取结构化课程表。'},
      {'role': 'user', 'content': '请从以下内容中提取所有课程：\n$rawText\n$_scheduleJsonSpec'},
    ], temperature: 0.1, maxTokens: 3500);
    return _parseCourses(reply);
  }

  static const _coursePalette = <int>[
    0xFF26A69A, 0xFF42A5F5, 0xFFAB47BC, 0xFFEF5350, 0xFFFFA726,
    0xFF66BB6A, 0xFF5C6BC0, 0xFFEC407A, 0xFF8D6E63, 0xFF29B6F6,
  ];

  static int _asInt(Object? v, int def) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? def;
    return def;
  }

  static List<Course> _parseCourses(String reply) {
    final j = extractJson(reply);
    if (j == null) throw AiException('AI 返回格式不正确，请重试。\n原始回复：$reply');
    final list = (j['courses'] as List?) ?? const [];
    final out = <Course>[];
    final colorByName = <String, int>{};
    for (final item in list.whereType<Map>()) {
      final m = Map<String, dynamic>.from(item);
      final name = (m['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final color = colorByName.putIfAbsent(
        name,
        () => _coursePalette[colorByName.length % _coursePalette.length],
      );
      final wd = _asInt(m['weekday'], 1).clamp(1, 7);
      final s = _asInt(m['start_section'], 1).clamp(1, 16);
      final e = _asInt(m['end_section'], s).clamp(s, 16);
      final sw = _asInt(m['start_week'], 1).clamp(1, 30);
      final ew = _asInt(m['end_week'], 16).clamp(sw, 30);
      final wt = _asInt(m['week_type'], 0).clamp(0, 2);
      out.add(Course(
        name: name,
        teacher: (m['teacher'] ?? '').toString().trim(),
        location: (m['location'] ?? '').toString().trim(),
        weekday: wd,
        startSection: s,
        endSection: e,
        startWeek: sw,
        endWeek: ew,
        weekType: wt,
        color: color,
      ));
    }
    if (out.isEmpty) throw AiException('没有识别出任何课程，请确认截图清晰或文本包含课程信息');
    return out;
  }

  /// 从 AI 回复中容错地提取 JSON 对象
  static Map<String, dynamic>? extractJson(String s) {
    var t = s.trim();
    t = t.replaceAll(RegExp(r'```(json)?', caseSensitive: false), '');
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final v = jsonDecode(t.substring(start, end + 1));
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
