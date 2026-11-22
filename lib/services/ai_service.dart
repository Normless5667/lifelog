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

/// 跑步机 / 椭圆机 / 动感单车屏幕拍照识别结果（读不出的字段严格保留 null，绝不瞎猜）
class TreadmillScanResult {
  final double? distanceKm;
  final int? durationSecs;
  final double? calories;
  final String? paceNote;
  final String machineType; // treadmill / treadmill_fast / elliptical / bike / unknown
  final String? unitNote;
  final String raw;

  const TreadmillScanResult({
    this.distanceKm,
    this.durationSecs,
    this.calories,
    this.paceNote,
    this.machineType = 'unknown',
    this.unitNote,
    this.raw = '',
  });
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
    int maxTokens = 2000,
  }) async {
    final cfg = await SettingsService.chatConfig();
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ...history.map((m) => {'role': m.role, 'content': m.content}),
    ];
    return _complete(cfg, messages, maxTokens: maxTokens);
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

  static const _treadmillPrompt = '''
这是健身房跑步机/椭圆机/动感单车屏幕的照片。请读出屏幕上的运动数据，只返回一个 JSON 对象，不要输出任何其他文字或解释：

{
  "distance_km": 数字或null,
  "duration_secs": 整数或null,
  "calories": 数字或null,
  "pace": "例如 6'30\"/km 或 null",
  "machine_type": "treadmill/elliptical/bike/unknown",
  "unit_note": "如果屏幕原始距离是 mile/英里 请写明原值与换算说明，否则 null"
}

严格要求：
- 距离单位可能是 km 也可能是 mile（mi）：如果是 mile，请按 1 mile = 1.60934 km 换算成 distance_km，并在 unit_note 里注明（例如 "屏幕显示 3.10 mi，已换算为 4.99 km"）
- 时长可能是 MM:SS 也可能是 HH:MM:SS，请统一换算为总秒数 duration_secs（整数）
- 反光、模糊、被遮挡或看不清的字段必须返回 null，绝对不要瞎猜''';

  /// 拍照读取健身房跑步机 / 椭圆机 / 动感单车屏幕数据（复用 SettingsService.visionConfig() 视觉通道）。
  static Future<TreadmillScanResult> analyzeTreadmillImage(
    File imageFile, {
    String? hint,
  }) async {
    final cfg = await SettingsService.visionConfig();
    final bytes = await imageFile.readAsBytes();
    final b64 = base64Encode(bytes);
    final text = hint != null && hint.trim().isNotEmpty
        ? '$_treadmillPrompt\n用户补充说明：${hint.trim()}'
        : _treadmillPrompt;
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
    ], temperature: 0.1, maxTokens: 600);
    return parseTreadmillResponse(reply);
  }

  /// 纯解析函数：将视觉模型返回的 JSON 解析为结构化器械读数（保留 null，绝不瞎猜；支持 mile 换算与 MM:SS / HH:MM:SS 容错）。
  static TreadmillScanResult parseTreadmillResponse(String reply) {
    final j = extractJson(reply);
    if (j == null) {
      throw AiException('无法解析屏幕数据，请换个角度避开反光重拍或手动填写。\n原始回复：$reply');
    }

    double? parseOptDouble(Object? v) {
      if (v == null) return null;
      if (v is num) {
        final d = v.toDouble();
        return d.isFinite && d > 0 ? d : null;
      }
      if (v is String) {
        final s = v.trim();
        if (s.isEmpty || s.toLowerCase() == 'null') return null;
        final m = RegExp(r'\d+(\.\d+)?').firstMatch(s);
        if (m == null) return null;
        final d = double.tryParse(m.group(0)!);
        return (d != null && d.isFinite && d > 0) ? d : null;
      }
      return null;
    }

    int? parseDurationSecs(Object? v) {
      if (v == null) return null;
      if (v is num) {
        final s = v.round();
        return (s > 0 && s <= 86400) ? s : null;
      }
      if (v is String) {
        final s = v.trim();
        if (s.isEmpty || s.toLowerCase() == 'null') return null;
        // 支持 HH:MM:SS 或 MM:SS
        final parts = s.split(':');
        if (parts.length == 2 || parts.length == 3) {
          final nums = parts.map((p) => int.tryParse(p.trim())).toList();
          if (nums.every((n) => n != null && n >= 0)) {
            final total = parts.length == 3
                ? nums[0]! * 3600 + nums[1]! * 60 + nums[2]!
                : nums[0]! * 60 + nums[1]!;
            return (total > 0 && total <= 86400) ? total : null;
          }
        }
        final m = RegExp(r'\d+').firstMatch(s);
        if (m != null) {
          final n = int.tryParse(m.group(0)!);
          return (n != null && n > 0 && n <= 86400) ? n : null;
        }
      }
      return null;
    }

    var distanceKm = parseOptDouble(j['distance_km']);
    var rawNote = reply.trim();
    final unitNote = (j['unit_note'] ?? '').toString().trim();
    // 兜底：若模型返回了 distance_mile 或在 distance_km 字符串里带了 mi/mile
    final distStr = (j['distance_km'] ?? '').toString().toLowerCase();
    final explicitMile = parseOptDouble(j['distance_mile'] ?? j['distance_miles']);
    if (distanceKm == null && explicitMile != null) {
      distanceKm = double.parse((explicitMile * 1.60934).toStringAsFixed(2));
      rawNote = 'Mile converted: $explicitMile mi -> $distanceKm km\n$rawNote';
    } else if (distanceKm != null &&
        (distStr.contains('mi') || distStr.contains('英里'))) {
      final orig = distanceKm;
      distanceKm = double.parse((orig * 1.60934).toStringAsFixed(2));
      rawNote = 'Mile converted: $orig mi -> $distanceKm km\n$rawNote';
    }
    if (distanceKm != null && distanceKm > 200) {
      distanceKm = null;
    }

    final durationSecs = parseDurationSecs(j['duration_secs'] ?? j['duration']);
    var calories = parseOptDouble(j['calories']);
    if (calories != null && calories > 10000) {
      calories = null;
    }

    final paceRaw = j['pace'];
    String? paceNote;
    if (paceRaw != null) {
      final p = paceRaw.toString().trim();
      if (p.isNotEmpty && p.toLowerCase() != 'null') {
        paceNote = p;
      }
    }

    final rawMachine = (j['machine_type'] ?? 'unknown').toString().trim().toLowerCase();
    final machineType = switch (rawMachine) {
      'treadmill' || '跑步机' => CardioType.treadmill,
      'treadmill_fast' => CardioType.treadmillFast,
      'elliptical' || '椭圆机' => CardioType.elliptical,
      'bike' || 'cycling' || 'spin' || '动感单车' => CardioType.bike,
      _ => 'unknown',
    };

    if (unitNote.isNotEmpty && unitNote.toLowerCase() != 'null') {
      rawNote = '$unitNote\n$rawNote';
    }

    return TreadmillScanResult(
      distanceKm: distanceKm,
      durationSecs: durationSecs,
      calories: calories,
      paceNote: paceNote,
      machineType: machineType,
      unitNote: (unitNote.isNotEmpty && unitNote.toLowerCase() != 'null') ? unitNote : null,
      raw: rawNote,
    );
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

  /// 从 AI 回复中容错地提取 JSON 对象（自动修复尾逗号等常见大模型输出瑕疵）
  static Map<String, dynamic>? extractJson(String s) {
    var t = s.trim();
    t = t.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '');
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final candidate = t.substring(start, end + 1);
    try {
      final v = jsonDecode(candidate);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      try {
        final repaired = candidate
            .replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m.group(1)!)
            .replaceAll('“', '"')
            .replaceAll('”', '"');
        final v = jsonDecode(repaired);
        return v is Map<String, dynamic> ? v : null;
      } catch (_) {
        return null;
      }
    }
  }
}
