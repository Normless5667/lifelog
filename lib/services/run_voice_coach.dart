import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 跑步语音教练服务（flutter_tts + audio_session 压低音乐音频焦点）：
/// - 完整分步诊断日志（step1~step5），绝不静默吞错
/// - 初始化失败不锁死，允许后续随时重试（例如用户去系统安装语音包后返回）
/// - 已移除有兼容性问题的 awaitSpeakCompletion(false)
/// - 支持多句顺序播报 speakSequence（等待前句播完 + 固定间隔，防止 TTS 连说吞字）
/// - 说话时通过 AudioSession 申请 gainTransientMayDuck 压低音乐而不打断音乐
class RunVoiceCoach {
  final FlutterTts _tts;
  final Future<bool> Function({required bool isEnglish})? _customInitForTest;
  final Future<void> Function(String text)? _customSpeakForTest;

  AudioSession? _session;
  bool _available = false;
  bool _muted = false;
  bool _lastIsEnglish = false;
  String? _lastFailureReason;
  Completer<void>? _utteranceCompleter;
  int _sequenceGen = 0;

  RunVoiceCoach({
    FlutterTts? tts,
    Future<bool> Function({required bool isEnglish})? customInitForTest,
    Future<void> Function(String text)? customSpeakForTest,
  })  : _tts = tts ?? FlutterTts(),
        _customInitForTest = customInitForTest,
        _customSpeakForTest = customSpeakForTest;

  bool get isAvailable => _available;
  bool get isMuted => _muted;
  String? get lastFailureReason => _lastFailureReason;

  void setMuted(bool muted) {
    _muted = muted;
    if (muted) {
      stop();
    }
  }

  /// 检查 TTS 可用性并配置语音播报音频焦点（压低音乐而不是停掉音乐）。
  /// 失败后不锁死，下次调用 init() 仍会重试。
  Future<bool> init({bool isEnglish = false}) async {
    _lastIsEnglish = isEnglish;
    if (_available) return true;

    if (_customInitForTest != null) {
      try {
        final ok = await _customInitForTest(isEnglish: isEnglish);
        _available = ok;
        _lastFailureReason = ok ? null : 'test_init_failed';
        return ok;
      } catch (e, st) {
        debugPrint('[VoiceCoach] customInitForTest failed: $e\n$st');
        _available = false;
        _lastFailureReason = e.toString();
        return false;
      }
    }

    _lastFailureReason = null;

    // Step 1: 配置 AudioSession（独立捕获，非致命）
    try {
      debugPrint('[VoiceCoach] step1: AudioSession configure...');
      _session = await AudioSession.instance;
      await _session!.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers |
              AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.voicePrompt,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.assistanceNavigationGuidance,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      debugPrint('[VoiceCoach] step1: AudioSession OK');
    } catch (e, st) {
      debugPrint('[VoiceCoach] step1: AudioSession skipped (non-fatal): $e\n$st');
    }

    try {
      // Step 2: 枚举引擎与语言（部分国产机 getLanguages 会抛异常，独立捕获绝不误杀）
      List<String> availableLangs = const [];
      try {
        debugPrint('[VoiceCoach] step2: getEngines / getLanguages...');
        if (defaultTargetPlatform == TargetPlatform.android) {
          final engines = await _tts.getEngines;
          debugPrint('[VoiceCoach] engines = $engines');
        }
        final langs = await _tts.getLanguages;
        debugPrint('[VoiceCoach] languages = $langs');
        if (langs is List) {
          availableLangs = langs.map((e) => e.toString()).toList();
        }
      } catch (e, st) {
        debugPrint('[VoiceCoach] step2: getLanguages threw (continuing): $e\n$st');
      }

      // Step 3: 逐个尝试目标语言（中文优先 zh-CN / zh_CN / zh-Hans / zh）
      final prefix = isEnglish ? 'en' : 'zh';
      final candidates = <String>[
        if (isEnglish) ...['en-US', 'en_US', 'en-GB', 'en'] else ...['zh-CN', 'zh_CN', 'zh-Hans', 'zh'],
        for (final loc in availableLangs)
          if (loc.toLowerCase().startsWith(prefix)) loc,
      ];
      final tried = <String>{};
      String? chosenLang;

      for (final cand in candidates) {
        if (!tried.add(cand)) continue;
        try {
          debugPrint('[VoiceCoach] step3: isLanguageAvailable($cand)...');
          final availRes = await _tts.isLanguageAvailable(cand);
          debugPrint('[VoiceCoach] isLanguageAvailable($cand) = $availRes');
          final langAvailable = availRes == true || availRes == 1;
          if (!langAvailable) continue;

          debugPrint('[VoiceCoach] step4: setLanguage($cand)...');
          final setRes = await _tts.setLanguage(cand);
          debugPrint('[VoiceCoach] setLanguage($cand) = $setRes');
          if (setRes == null || setRes == 1 || setRes == true) {
            chosenLang = cand;
            break;
          }
        } catch (e, st) {
          debugPrint('[VoiceCoach] candidate $cand failed: $e\n$st');
        }
      }

      // 若 isLanguageAvailable 在部分机型返回值异常，再直接尝试 setLanguage 一次作为兜底
      if (chosenLang == null) {
        final fallbackCand = isEnglish ? 'en-US' : 'zh-CN';
        try {
          debugPrint('[VoiceCoach] step4 fallback: direct setLanguage($fallbackCand)...');
          final setRes = await _tts.setLanguage(fallbackCand);
          debugPrint('[VoiceCoach] direct setLanguage($fallbackCand) = $setRes');
          if (setRes == 1 || setRes == true) {
            chosenLang = fallbackCand;
          }
        } catch (e, st) {
          debugPrint('[VoiceCoach] fallback setLanguage threw: $e\n$st');
        }
      }

      if (chosenLang == null) {
        _available = false;
        _lastFailureReason = 'missing_language($prefix), langs=$availableLangs';
        debugPrint('[VoiceCoach] INIT FAILED: $_lastFailureReason');
        return false;
      }

      // Step 5: 配置语速、音量、音调（已去掉容易卡死的 awaitSpeakCompletion(false)）
      debugPrint('[VoiceCoach] step5: speech params (lang=$chosenLang)...');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      _tts.setCompletionHandler(() {
        debugPrint('[VoiceCoach] utterance completed');
        _completeCurrentUtterance();
        _session?.setActive(false).catchError((_) => false);
      });
      _tts.setCancelHandler(() {
        debugPrint('[VoiceCoach] utterance cancelled');
        _completeCurrentUtterance();
        _session?.setActive(false).catchError((_) => false);
      });
      _tts.setErrorHandler((msg) {
        debugPrint('[VoiceCoach] tts error callback: $msg');
        _completeCurrentUtterance();
        _session?.setActive(false).catchError((_) => false);
      });

      _available = true;
      _lastFailureReason = null;
      debugPrint('[VoiceCoach] INIT OK (lang=$chosenLang)');
      return true;
    } catch (e, st) {
      debugPrint('[VoiceCoach] INIT FAILED with exception: $e\n$st');
      _available = false;
      _lastFailureReason = e.toString();
      return false;
    }
  }

  void _completeCurrentUtterance() {
    final c = _utteranceCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _utteranceCompleter = null;
  }

  /// 立即播报一句提示（会打断正在进行的序列，确保最新切段语音优先）。
  Future<void> speak(String text) async {
    _sequenceGen++;
    await _speakSingle(text, waitForCompletion: false);
  }

  /// 顺序播报多句提示：等待前一句播完后再停顿 [gap]（默认 800ms），避免 TTS 连说吞字。
  Future<void> speakSequence(
    List<String> lines, {
    Duration gap = const Duration(milliseconds: 800),
  }) async {
    final nonEmpty = [
      for (final s in lines)
        if (s.trim().isNotEmpty) s.trim(),
    ];
    if (nonEmpty.isEmpty || _muted) return;
    final gen = ++_sequenceGen;

    for (var i = 0; i < nonEmpty.length; i++) {
      if (_muted || gen != _sequenceGen) return;
      final isLast = i == nonEmpty.length - 1;
      await _speakSingle(nonEmpty[i], waitForCompletion: !isLast);
      if (!isLast && !_muted && gen == _sequenceGen && gap > Duration.zero) {
        await Future.delayed(gap);
      }
    }
  }

  Future<void> _speakSingle(String text, {required bool waitForCompletion}) async {
    final msg = text.trim();
    if (msg.isEmpty || _muted) return;

    if (!_available) {
      debugPrint('[VoiceCoach] speak skipped (unavailable: $_lastFailureReason) -> "$msg"');
      return;
    }

    if (_customSpeakForTest != null) {
      await _customSpeakForTest(msg);
      return;
    }

    try {
      debugPrint('[VoiceCoach] speak: "$msg"');
      await _session?.setActive(true);
      _completeCurrentUtterance();
      await _tts.stop();

      Completer<void>? completer;
      if (waitForCompletion) {
        completer = Completer<void>();
        _utteranceCompleter = completer;
      }

      final res = await _tts.speak(msg);
      debugPrint('[VoiceCoach] _tts.speak result = $res');

      if (waitForCompletion && completer != null) {
        // 根据字数估算最大超时，防止某些 ROM 不触发 completionHandler 导致卡死
        final estMs = (msg.length * 260).clamp(1500, 9000);
        await completer.future.timeout(
          Duration(milliseconds: estMs),
          onTimeout: () {
            debugPrint('[VoiceCoach] utterance completion timed out after ${estMs}ms');
            _completeCurrentUtterance();
          },
        );
      }
    } catch (e, st) {
      debugPrint('[VoiceCoach] speak threw: $e\n$st');
      _completeCurrentUtterance();
      _session?.setActive(false).catchError((_) => false);
    }
  }

  /// 供外部显式重新检测（例如用户从系统文字转语音设置返回后点击重试）
  Future<bool> retryInit({bool? isEnglish}) async {
    _available = false;
    return init(isEnglish: isEnglish ?? _lastIsEnglish);
  }

  Future<void> stop() async {
    _sequenceGen++;
    _completeCurrentUtterance();
    if (!_available) return;
    if (_customSpeakForTest != null) return;
    try {
      await _tts.stop();
      await _session?.setActive(false);
    } catch (e) {
      debugPrint('[VoiceCoach] stop threw: $e');
    }
  }

  Future<void> dispose() async {
    await stop();
  }
}
