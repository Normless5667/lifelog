import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 跑步语音教练服务（flutter_tts + audio_session 压低音乐音频焦点）：
/// - 初始化前先检查 TTS 引擎可用性；不可用或异常时自动降级静默，绝不崩溃
/// - 说话时通过 AudioSession 申请瞬时压低音乐焦点（ducking），说完后释放还原音乐音量
class RunVoiceCoach {
  final FlutterTts _tts = FlutterTts();
  AudioSession? _session;
  bool _initialized = false;
  bool _available = false;
  bool _muted = false;

  bool get isAvailable => _available;
  bool get isMuted => _muted;

  void setMuted(bool muted) {
    _muted = muted;
    if (muted) {
      stop();
    }
  }

  /// 检查 TTS 可用性并配置语音播报音频焦点（压低音乐而不是停掉音乐）
  Future<bool> init({bool isEnglish = false}) async {
    if (_initialized) return _available;
    _initialized = true;

    try {
      // 1) 配置 audio_session：说话时 duck 音乐，不打断音乐播放
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
    } catch (e) {
      debugPrint('[RunVoiceCoach] AudioSession configure skipped: $e');
    }

    try {
      // 2) 检查 TTS 引擎是否可用
      final langs = await _tts.getLanguages;
      if (langs == null || (langs is List && langs.isEmpty)) {
        _available = false;
        return false;
      }

      final targetLang = isEnglish ? 'en-US' : 'zh-CN';
      final hasTarget = await _tts.isLanguageAvailable(targetLang);
      if (hasTarget == true || hasTarget == 1) {
        await _tts.setLanguage(targetLang);
      } else {
        await _tts.setLanguage(isEnglish ? 'en' : 'zh');
      }

      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(false);

      _tts.setCompletionHandler(() {
        _session?.setActive(false).catchError((_) => false);
      });
      _tts.setCancelHandler(() {
        _session?.setActive(false).catchError((_) => false);
      });
      _tts.setErrorHandler((_) {
        _session?.setActive(false).catchError((_) => false);
      });

      _available = true;
      return true;
    } catch (e) {
      debugPrint('[RunVoiceCoach] TTS unavailable, degrading to haptic + banner: $e');
      _available = false;
      return false;
    }
  }

  /// 安全播报一句提示；若 TTS 不可用或已静音则静默返回
  Future<void> speak(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _muted || !_available) return;
    try {
      await _session?.setActive(true);
      await _tts.stop();
      await _tts.speak(msg);
    } catch (e) {
      debugPrint('[RunVoiceCoach] TTS speak failed, degrading safely: $e');
      _available = false;
      _session?.setActive(false).catchError((_) => false);
    }
  }

  Future<void> stop() async {
    if (!_available) return;
    try {
      await _tts.stop();
      await _session?.setActive(false);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
  }
}
