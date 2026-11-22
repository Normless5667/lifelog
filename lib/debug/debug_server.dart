import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/usage_telemetry_service.dart';
import 'debug_console_html.dart';

/// 内存态调试配置单例：电脑调试台下发 `update_config` 后即时生效，无需重启 App。
class DebugRuntimeConfig extends ChangeNotifier {
  double _fxRate = 0.000285;
  double _threshold = 0.6;
  bool _fxRateOverridden = false;

  double get fxRate => _fxRate;
  double get threshold => _threshold;
  bool get fxRateOverridden => _fxRateOverridden;

  /// 更新可调参数，返回是否发生有效变更
  bool update({double? fxRate, double? threshold}) {
    var changed = false;
    if (fxRate != null && fxRate.isFinite && fxRate > 0) {
      _fxRate = fxRate;
      _fxRateOverridden = true;
      changed = true;
    }
    if (threshold != null && threshold.isFinite && threshold >= 0 && threshold <= 1) {
      _threshold = threshold;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
    return changed;
  }
}

/// 单条推送给电脑调试台的日志记录
class DebugLogEntry {
  final String ts;
  final String level; // 'info' | 'warn' | 'error'
  final String tag;
  final String message;
  final String? stack;

  const DebugLogEntry({
    required this.ts,
    required this.level,
    required this.tag,
    required this.message,
    this.stack,
  });

  Map<String, dynamic> toJson() => {
        'type': 'log',
        'ts': ts,
        'level': level,
        'tag': tag,
        'message': message,
        if (stack != null && stack!.isNotEmpty) 'stack': stack,
      };
}

/// v3.4.0 手机端 Wi-Fi 电脑调试后端（纯 dart:io HttpServer + WebSocket，零第三方依赖）：
/// - 默认关闭，仅用户在设置中手动开启并确认风险提示后启动
/// - 每次开启使用 Random.secure() 生成新随机 token，无有效 token 的所有请求一律 403
/// - 开启期间 2 小时无任何客户端连接自动关闭；App 退出（detached）时自动关闭
/// - 上行：全局 debugPrint / 异常堆栈 / OCR 完整异常 / 页面切换 / 功能埋点 / AI 请求与原文
/// - 下行：接收 `{"cmd":"update_config","fx_rate":...,"threshold":...}` 即时更新内存配置
class DebugServer extends ChangeNotifier with WidgetsBindingObserver {
  DebugServer._();

  @visibleForTesting
  DebugServer.forTest();

  static final DebugServer instance = DebugServer._();

  static const int defaultPort = 8080;
  static const Duration defaultIdleTimeout = Duration(hours: 2);
  static const int _maxHistory = 500;

  final DebugRuntimeConfig config = DebugRuntimeConfig();
  final List<DebugLogEntry> _history = [];
  final Set<WebSocket> _clients = {};

  HttpServer? _server;
  Timer? _idleTimer;
  Duration _idleTimeout = defaultIdleTimeout;
  String? _token;
  String _ipAddress = '127.0.0.1';
  int _port = defaultPort;
  DateTime? _idleShutdownAt;

  bool _hooksInstalled = false;
  bool _inLogHook = false;
  bool _observerAttached = false;

  bool get isRunning => _server != null;
  String? get token => _token;
  String get ipAddress => _ipAddress;
  int get port => _port;
  int get clientCount => _clients.length;
  DateTime? get idleShutdownAt => _idleShutdownAt;
  List<DebugLogEntry> get history => List.unmodifiable(_history);

  /// 完整带 token 访问地址，例如 `http://192.168.1.23:8080/?token=a8f3c9...`
  String? get connectUrl {
    if (!isRunning || _token == null) return null;
    return 'http://$_ipAddress:$_port/?token=$_token';
  }

  /// 在 main() 中尽早挂载全局日志与异常捕获（不会启动 HTTP 服务，服务严格保持默认关闭）
  void installGlobalLogHooks() {
    if (_hooksInstalled) return;
    _hooksInstalled = true;

    final prevDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      prevDebugPrint(message, wrapWidth: wrapWidth);
      if (_inLogHook || message == null || message.isEmpty) return;
      _inLogHook = true;
      try {
        final inferred = _inferTagAndLevel(message);
        log(message, level: inferred.level, tag: inferred.tag);
      } finally {
        _inLogHook = false;
      }
    };

    final prevFlutterError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      log(
        details.exceptionAsString(),
        level: 'error',
        tag: 'FlutterError',
        stack: details.stack?.toString(),
      );
      if (prevFlutterError != null) {
        prevFlutterError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final prevPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      logError('PlatformError', error, stack);
      if (prevPlatformError != null) {
        return prevPlatformError(error, stack);
      }
      return false;
    };

    _attachLifecycleObserver();
  }

  void _attachLifecycleObserver() {
    if (_observerAttached) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 安全底线：App 退出时自动关闭调试服务，不残留在后台
    if (state == AppLifecycleState.detached && isRunning) {
      stop(reason: 'app_detached');
    }
  }

  /// 启动 HTTP + WebSocket 调试服务（每次启动重新生成随机 token）
  Future<void> start({
    int port = defaultPort,
    Duration idleTimeout = defaultIdleTimeout,
  }) async {
    if (_server != null) return;
    _attachLifecycleObserver();
    _idleTimeout = idleTimeout;
    _token = _generateRandomToken();

    HttpServer? bound;
    if (port == 0) {
      bound = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    } else {
      Object? lastErr;
      for (var p = port; p <= port + 5; p++) {
        try {
          bound = await HttpServer.bind(InternetAddress.anyIPv4, p);
          break;
        } on SocketException catch (e) {
          lastErr = e;
        }
      }
      if (bound == null) {
        _token = null;
        throw lastErr ?? StateError('Unable to bind debug HTTP port');
      }
    }

    _server = bound;
    _port = bound.port;
    _ipAddress = await detectLocalIpv4();

    bound.listen(
      _handleRequest,
      onError: (Object e, StackTrace st) {
        logError('DebugServer', e, st, 'HttpServer stream error');
      },
      cancelOnError: false,
    );

    _armIdleTimer();
    log(
      'Debug server started on $_ipAddress:$_port (auto-stop after ${_idleTimeout.inMinutes}m idle)',
      tag: 'DebugServer',
    );
    notifyListeners();
  }

  /// 立即关闭调试服务并断开所有客户端
  Future<void> stop({String reason = 'manual'}) async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _idleShutdownAt = null;

    final srv = _server;
    _server = null;
    _token = null;

    final openClients = List<WebSocket>.from(_clients);
    _clients.clear();
    for (final ws in openClients) {
      try {
        await ws.close(WebSocketStatus.goingAway, 'Debug server stopped');
      } catch (_) {}
    }

    if (srv != null) {
      try {
        await srv.close(force: true);
      } catch (_) {}
      log('Debug server stopped (reason=$reason)', tag: 'DebugServer');
    }
    notifyListeners();
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    if (!isRunning || _clients.isNotEmpty) {
      _idleShutdownAt = null;
      return;
    }
    _idleShutdownAt = DateTime.now().add(_idleTimeout);
    _idleTimer = Timer(_idleTimeout, () {
      if (isRunning && _clients.isEmpty) {
        stop(reason: 'idle_timeout');
      }
    });
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final provided = req.uri.queryParameters['token'] ??
        req.headers.value('x-debug-token') ??
        '';
    final expected = _token;
    if (expected == null || !_constantTimeEquals(provided, expected)) {
      req.response
        ..statusCode = HttpStatus.forbidden
        ..headers.contentType = ContentType.text
        ..write('403 Forbidden: missing or invalid debug token')
        ..close();
      return;
    }

    final path = req.uri.path;
    if (path == '/' && req.method == 'GET') {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..headers.set('Cache-Control', 'no-store')
        ..write(kDebugConsoleHtml)
        ..close();
      return;
    }

    if (path == '/ws') {
      try {
        final ws = await WebSocketTransformer.upgrade(req);
        _attachClient(ws);
      } catch (e, st) {
        logError('DebugServer', e, st, 'WebSocket upgrade failed');
      }
      return;
    }

    req.response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.text
      ..write('404 Not Found')
      ..close();
  }

  void _attachClient(WebSocket ws) {
    _clients.add(ws);
    _idleTimer?.cancel();
    _idleTimer = null;
    _idleShutdownAt = null;
    notifyListeners();

    // 首次握手立即同步配置、设备信息与历史日志缓冲
    _sendToClient(ws, {
      'type': 'hello',
      'version': UsageTelemetryService.appVersion,
      'ip': _ipAddress,
      'port': _port,
      'fx_rate': config.fxRate,
      'threshold': config.threshold,
      'clients': _clients.length,
      'history': _history.map((e) => e.toJson()).toList(),
    });

    log('Browser console connected (clients=${_clients.length})', tag: 'DebugServer');

    ws.listen(
      (dynamic data) => _handleClientMessage(ws, data),
      onDone: () => _detachClient(ws),
      onError: (_) => _detachClient(ws),
      cancelOnError: true,
    );
  }

  void _detachClient(WebSocket ws) {
    final removed = _clients.remove(ws);
    if (!removed) return;
    if (_clients.isEmpty && isRunning) {
      _armIdleTimer();
    }
    notifyListeners();
  }

  void _handleClientMessage(WebSocket ws, dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (_) {
      return;
    }

    final cmd = msg['cmd']?.toString();
    switch (cmd) {
      case 'update_config':
        final fxRaw = msg['fx_rate'];
        final thRaw = msg['threshold'] ?? msg['confidence_threshold'];
        final fx = fxRaw is num ? fxRaw.toDouble() : double.tryParse('$fxRaw');
        final th = thRaw is num ? thRaw.toDouble() : double.tryParse('$thRaw');
        final updated = config.update(fxRate: fx, threshold: th);
        if (updated) {
          log(
            'Remote config applied: fx_rate=${config.fxRate}, threshold=${config.threshold}',
            tag: 'Config',
          );
          _broadcast({
            'type': 'config',
            'fx_rate': config.fxRate,
            'threshold': config.threshold,
          });
        }
        break;
      case 'clear_logs':
        _history.clear();
        _broadcast({'type': 'cleared'});
        break;
      case 'ping':
        _sendToClient(ws, {'type': 'pong', 'ts': _formatNow()});
        break;
    }
  }

  /// 写入日志缓冲并实时广播给所有已连接的电脑调试台
  void log(
    String message, {
    String level = 'info',
    String tag = 'App',
    String? stack,
  }) {
    final entry = DebugLogEntry(
      ts: _formatNow(),
      level: level,
      tag: tag,
      message: message,
      stack: stack,
    );
    _history.add(entry);
    if (_history.length > _maxHistory) {
      _history.removeRange(0, _history.length - _maxHistory);
    }
    if (_clients.isNotEmpty) {
      _broadcast(entry.toJson());
    }
  }

  /// 专门格式化异常（特别展开 PlatformException 的 code / message / details / 原生 stacktrace）
  void logError(
    String tag,
    Object error, [
    StackTrace? stackTrace,
    String? context,
  ]) {
    final buf = StringBuffer();
    if (context != null && context.isNotEmpty) {
      buf.writeln(context);
    }
    if (error is PlatformException) {
      buf.writeln('PlatformException:');
      buf.writeln('  code: ${error.code}');
      buf.writeln('  message: ${error.message}');
      buf.writeln('  details: ${error.details}');
      if (error.stacktrace != null && error.stacktrace!.isNotEmpty) {
        buf.writeln('  nativeStacktrace:\n${error.stacktrace}');
      }
    } else {
      buf.write('${error.runtimeType}: $error');
    }
    log(
      buf.toString().trim(),
      level: 'error',
      tag: tag,
      stack: stackTrace?.toString(),
    );
  }

  /// 记录页面切换
  void logPage(String pageName, {String source = 'tab'}) {
    log('enter page="$pageName" (source=$source)', tag: 'Page');
  }

  /// 记录功能调用与结果
  void logFeature(
    String feature,
    String action, {
    int? durationMs,
    String? errorMsg,
  }) {
    final durPart = durationMs != null ? ' ${durationMs}ms' : '';
    final errPart = (errorMsg != null && errorMsg.isNotEmpty) ? ' error="$errorMsg"' : '';
    log(
      'feature="$feature" action=$action$durPart$errPart',
      level: action == 'fail' ? 'error' : 'info',
      tag: 'Feature',
    );
  }

  /// 记录 AI 请求 prompt 与回复原文（绝不记录 API Key）
  void logAi({
    required String stage,
    required String model,
    required String detail,
    bool isError = false,
  }) {
    final truncated =
        detail.length > 4000 ? '${detail.substring(0, 4000)}\n...[truncated ${detail.length} chars]' : detail;
    log(
      '[$stage] model=$model\n$truncated',
      level: isError ? 'error' : 'info',
      tag: 'AI',
    );
  }

  void _sendToClient(WebSocket ws, Map<String, dynamic> payload) {
    try {
      if (ws.readyState == WebSocket.open) {
        ws.add(jsonEncode(payload));
      }
    } catch (_) {}
  }

  void _broadcast(Map<String, dynamic> payload) {
    if (_clients.isEmpty) return;
    final encoded = jsonEncode(payload);
    final dead = <WebSocket>[];
    for (final ws in _clients) {
      try {
        if (ws.readyState == WebSocket.open) {
          ws.add(encoded);
        } else {
          dead.add(ws);
        }
      } catch (_) {
        dead.add(ws);
      }
    }
    for (final ws in dead) {
      _detachClient(ws);
    }
  }

  static String _generateRandomToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(12, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length || a.isEmpty) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static ({String tag, String level}) _inferTagAndLevel(String msg) {
    final lower = msg.toLowerCase();
    var tag = 'App';
    final bracket = RegExp(r'^\[([A-Za-z0-9_.\- ]{2,24})\]').firstMatch(msg.trimLeft());
    if (bracket != null) {
      tag = bracket.group(1)!.trim();
    } else if (lower.contains('ocr') || lower.contains('mlkit') || lower.contains('inputimage')) {
      tag = 'OCR';
    }
    final isErr = lower.contains('error') ||
        lower.contains('exception') ||
        lower.contains('failed');
    return (tag: tag, level: isErr ? 'error' : 'info');
  }

  static String _formatNow() {
    final d = DateTime.now();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    final s = d.second.toString().padLeft(2, '0');
    final ms = d.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// 查找本机局域网 Wi-Fi IPv4（优先 wlan/en 私有网段，避免返回蜂窝或回环地址）
  static Future<String> detectLocalIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      String? fallbackPrivate;
      String? fallbackAny;
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isWifiLike = name.startsWith('wlan') ||
            name.startsWith('en') ||
            name.contains('wi-fi') ||
            name.contains('wifi');
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (_isPrivateIpv4(ip)) {
            if (isWifiLike) return ip;
            fallbackPrivate ??= ip;
          } else {
            fallbackAny ??= ip;
          }
        }
      }
      return fallbackPrivate ?? fallbackAny ?? '127.0.0.1';
    } catch (_) {
      return '127.0.0.1';
    }
  }

  static bool _isPrivateIpv4(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]) ?? -1;
        return second >= 16 && second <= 31;
      }
    }
    return false;
  }
}
