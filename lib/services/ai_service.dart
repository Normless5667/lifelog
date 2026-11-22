import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../debug/debug_server.dart';
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

/// AR 菜单翻译单条菜品（符合 REQUIREMENTS_v3.3_ar_camera.md JSON 契约）
class MenuDishItem {
  final int id;
  final String vn;
  final String cn;
  final int? vnd;
  final double? rmb;
  final int? kcal;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String light; // 'green' | 'yellow' | 'red'
  final String tip;

  const MenuDishItem({
    required this.id,
    required this.vn,
    required this.cn,
    this.vnd,
    this.rmb,
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.light = 'yellow',
    this.tip = '',
  });

  /// 按当前生效汇率（1 VND -> RMB）实时计算人民币价格；若无越南盾原价则回退 AI 提供的 rmb
  double? effectiveRmb(double? fxRate) {
    if (vnd != null && vnd! > 0 && fxRate != null && fxRate.isFinite && fxRate > 0) {
      return vnd! * fxRate;
    }
    return rmb;
  }
}

/// AR 菜单翻译完整结果（若 AI 返回非合法 JSON，parseFailed=true 并完整保留 rawReply，绝不崩溃）
class MenuTranslationResult {
  final double? fxRate;
  final List<MenuDishItem> items;
  final String rawReply;
  final bool parseFailed;

  const MenuTranslationResult({
    required this.fxRate,
    required this.items,
    required this.rawReply,
    this.parseFailed = false,
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

  static String _summarizeMessagesForDebug(List<Map<String, dynamic>> messages) {
    final buf = StringBuffer();
    for (final m in messages) {
      final role = m['role'] ?? 'unknown';
      final content = m['content'];
      if (content is String) {
        buf.writeln('[$role] $content');
      } else if (content is List) {
        for (final part in content) {
          if (part is Map) {
            if (part['type'] == 'text') {
              buf.writeln('[$role/text] ${part['text']}');
            } else if (part['type'] == 'image_url') {
              final url = (part['image_url'] is Map) ? '${part['image_url']['url']}' : '';
              buf.writeln('[$role/image] <image_url len=${url.length}>');
            }
          }
        }
      }
    }
    return buf.toString().trim();
  }

  static Future<String> _complete(
    AiConfig cfg,
    List<Map<String, dynamic>> messages, {
    double temperature = 0.7,
    int maxTokens = 2000,
    Duration timeout = _timeout,
  }) async {
    if (!cfg.isReady) {
      throw AiException('还没有配置 AI 接口，请先到「设置」里填写 API Key', needsConfig: true);
    }
    final sw = Stopwatch()..start();
    final endpoint = _endpoint(cfg.baseUrl);
    final modelName = cfg.model.trim();
    DebugServer.instance.logAi(
      stage: 'REQ',
      model: modelName,
      detail: 'POST $endpoint (max_tokens=$maxTokens, temp=$temperature)\n'
          '${_summarizeMessagesForDebug(messages)}',
    );
    final http.Response resp;
    try {
      resp = await http
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${cfg.apiKey.trim()}',
            },
            body: jsonEncode({
              'model': modelName,
              'messages': messages,
              'temperature': temperature,
              'max_tokens': maxTokens,
              'stream': false,
            }),
          )
          .timeout(timeout);
    } on SocketException catch (e) {
      DebugServer.instance.logAi(
        stage: 'ERR ${sw.elapsedMilliseconds}ms',
        model: modelName,
        detail: 'SocketException: $e',
        isError: true,
      );
      throw AiException('网络连接失败，请检查网络');
    } on HttpException catch (e) {
      DebugServer.instance.logAi(
        stage: 'ERR ${sw.elapsedMilliseconds}ms',
        model: modelName,
        detail: 'HttpException: ${e.message}',
        isError: true,
      );
      throw AiException('网络错误：${e.message}');
    } on Exception catch (e) {
      DebugServer.instance.logAi(
        stage: 'ERR ${sw.elapsedMilliseconds}ms',
        model: modelName,
        detail: '$e',
        isError: true,
      );
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
      DebugServer.instance.logAi(
        stage: 'HTTP ${resp.statusCode} (${sw.elapsedMilliseconds}ms)',
        model: modelName,
        detail: detail,
        isError: true,
      );
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
      final content = (j['choices'][0]['message']['content'] ?? '').toString().trim();
      DebugServer.instance.logAi(
        stage: 'RES ${sw.elapsedMilliseconds}ms',
        model: modelName,
        detail: content,
      );
      return content;
    } catch (e) {
      DebugServer.instance.logAi(
        stage: 'PARSE_ERR ${sw.elapsedMilliseconds}ms',
        model: modelName,
        detail: 'error=$e\nraw=$body',
        isError: true,
      );
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

  static const _menuTranslationPrompt = '''
你是懂越南语、英语和中国营养学的随身点餐助手。下面是端侧 OCR 从越南/英文餐厅菜单识别出的原始文字（可能存在轻微换行错位或少量字符误差）。
请提取其中的菜品，翻译成地道中文，换算越南盾（VND）到人民币（RMB），并估算每道菜热量与营养红绿灯。
请**只输出一个合法 JSON 对象**，不要输出任何其他解释文字，严格遵循以下格式：

{
  "fx_rate": 0.000285,
  "items": [
    {
      "id": 1,
      "vn": "Phở bò",
      "cn": "牛肉粉",
      "vnd": 120000,
      "rmb": 34.2,
      "kcal": 320,
      "macros": {"p": 38, "c": 2, "f": 17},
      "light": "green",
      "tip": "高蛋白，汤底偏咸"
    }
  ]
}

要求：
1. fx_rate 为 1 越南盾兑换人民币的汇率（参考约 0.000285）。
2. vnd 为整数越南盾（例如菜单写 65k 或 65.000đ 均填 65000；若菜单上没标价则填 null）。
3. light 只能是 "green"（高蛋白/清淡/适合减脂增肌）、"yellow"（普通/适量吃）或 "red"（高油/高糖/油炸/热量炸弹）。
4. 忽略纯店名、电话、Wi-Fi 密码等非菜品文字；尽量还原 OCR 轻微拼错的越南菜名。''';

  /// 将 ML Kit 端侧 OCR 识别出的菜单文本发给 AI 进行翻译、汇率换算与营养红绿灯分析（只发文字，大幅省 Token，默认 15 秒超时）。
  static Future<MenuTranslationResult> translateMenuOcrText(
    String ocrText, {
    double? customFxRate,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final cleaned = ocrText.trim();
    if (cleaned.isEmpty) {
      throw AiException('当前没有识别到菜单文字，请对准菜单后再试');
    }
    var cfg = await SettingsService.visionConfig();
    if (!cfg.isReady) {
      cfg = await SettingsService.chatConfig();
    }
    final fxHint = (customFxRate != null && customFxRate > 0)
        ? '\n用户指定汇率 fx_rate = $customFxRate（请按此汇率计算 rmb）。'
        : '';
    final reply = await _complete(
      cfg,
      [
        {
          'role': 'user',
          'content': '$_menuTranslationPrompt$fxHint\n\n以下是 OCR 识别出的菜单原文：\n$cleaned',
        },
      ],
      temperature: 0.2,
      maxTokens: 2000,
      timeout: timeout,
    );
    return parseMenuTranslationResponse(reply);
  }

  /// 纯解析函数：将 AI 菜单翻译回复解析为 MenuTranslationResult；遇到非合法 JSON 时安全返回 parseFailed=true 并保留 rawReply。
  static MenuTranslationResult parseMenuTranslationResponse(String reply) {
    final j = extractJson(reply);
    if (j == null) {
      return MenuTranslationResult(
        fxRate: null,
        items: const [],
        rawReply: reply.trim(),
        parseFailed: true,
      );
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

    int? parseVnd(Object? v) {
      if (v == null) return null;
      if (v is num) {
        final n = v.round();
        return n > 0 ? n : null;
      }
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s.isEmpty || s == 'null') return null;
        // 处理 65k / 65K
        final kMatch = RegExp(r'^(\d+(?:\.\d+)?)\s*k').firstMatch(s);
        if (kMatch != null) {
          final base = double.tryParse(kMatch.group(1)!);
          if (base != null && base > 0) return (base * 1000).round();
        }
        // 处理 120,000 或 65.000đ（越南盾千位分隔符）
        final digitsOnly = s.replaceAll(RegExp(r'[^0-9]'), '');
        if (digitsOnly.isNotEmpty) {
          final n = int.tryParse(digitsOnly);
          if (n != null && n > 0) return n;
        }
      }
      return null;
    }

    final fxRate = parseOptDouble(j['fx_rate']);
    final rawList = j['items'];
    if (rawList is! List) {
      return MenuTranslationResult(
        fxRate: fxRate,
        items: const [],
        rawReply: reply.trim(),
        parseFailed: true,
      );
    }

    final items = <MenuDishItem>[];
    var seq = 1;
    for (final entry in rawList.whereType<Map>()) {
      final m = Map<String, dynamic>.from(entry);
      final vn = (m['vn'] ?? m['original'] ?? '').toString().trim();
      final cn = (m['cn'] ?? m['zh'] ?? '').toString().trim();
      if (vn.isEmpty && cn.isEmpty) continue;

      final vnd = parseVnd(m['vnd']);
      var rmb = parseOptDouble(m['rmb']);
      if (rmb == null && vnd != null && fxRate != null) {
        rmb = vnd * fxRate;
      }
      final kcalD = parseOptDouble(m['kcal']);
      final kcal = kcalD != null ? kcalD.round() : null;

      double? p;
      double? c;
      double? f;
      final macros = m['macros'];
      if (macros is Map) {
        p = parseOptDouble(macros['p'] ?? macros['protein']);
        c = parseOptDouble(macros['c'] ?? macros['carbs']);
        f = parseOptDouble(macros['f'] ?? macros['fat']);
      }

      final rawLight = (m['light'] ?? 'yellow').toString().trim().toLowerCase();
      final light = switch (rawLight) {
        'green' || '绿' => 'green',
        'red' || '红' => 'red',
        _ => 'yellow',
      };

      final tip = (m['tip'] ?? '').toString().trim();
      final idVal = _asInt(m['id'], seq);
      items.add(MenuDishItem(
        id: idVal,
        vn: vn.isNotEmpty ? vn : cn,
        cn: cn.isNotEmpty ? cn : vn,
        vnd: vnd,
        rmb: rmb,
        kcal: kcal,
        proteinG: p,
        carbsG: c,
        fatG: f,
        light: light,
        tip: tip == 'null' ? '' : tip,
      ));
      seq++;
    }

    if (items.isEmpty) {
      return MenuTranslationResult(
        fxRate: fxRate,
        items: const [],
        rawReply: reply.trim(),
        parseFailed: true,
      );
    }

    return MenuTranslationResult(
      fxRate: fxRate,
      items: items,
      rawReply: reply.trim(),
      parseFailed: false,
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
