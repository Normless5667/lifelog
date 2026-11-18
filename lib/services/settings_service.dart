import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AI 接口配置（OpenAI 兼容）。API Key 存在系统安全存储中。
class AiConfig {
  String baseUrl;
  String apiKey;
  String model;

  AiConfig({required this.baseUrl, required this.apiKey, required this.model});

  bool get isReady => baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty && model.trim().isNotEmpty;
}

class SettingsService {
  SettingsService._();

  static const _storage = FlutterSecureStorage();

  static const defaultBaseUrl = 'https://api.deepseek.com';
  static const defaultChatModel = 'deepseek-chat';

  static Future<String> _read(String k, String def) async => (await _storage.read(key: k)) ?? def;

  /// 对话模型配置
  static Future<AiConfig> chatConfig() async => AiConfig(
        baseUrl: await _read('chat_base_url', defaultBaseUrl),
        apiKey: await _read('chat_api_key', ''),
        model: await _read('chat_model', defaultChatModel),
      );

  static Future<void> saveChatConfig(AiConfig c) async {
    await _storage.write(key: 'chat_base_url', value: c.baseUrl.trim());
    await _storage.write(key: 'chat_api_key', value: c.apiKey.trim());
    await _storage.write(key: 'chat_model', value: c.model.trim());
  }

  /// 识图是否与对话共用配置（默认是）
  static Future<bool> visionSameAsChat() async => (await _read('vision_same', '1')) == '1';

  static Future<void> setVisionSameAsChat(bool v) => _storage.write(key: 'vision_same', value: v ? '1' : '0');

  /// 识图模型配置。共用时返回对话配置。
  static Future<AiConfig> visionConfig({bool raw = false}) async {
    if (!raw && await visionSameAsChat()) return chatConfig();
    final chat = await chatConfig();
    return AiConfig(
      baseUrl: await _read('vision_base_url', chat.baseUrl),
      apiKey: await _read('vision_api_key', ''),
      model: await _read('vision_model', ''),
    );
  }

  static Future<void> saveVisionConfig(AiConfig c) async {
    await _storage.write(key: 'vision_base_url', value: c.baseUrl.trim());
    await _storage.write(key: 'vision_api_key', value: c.apiKey.trim());
    await _storage.write(key: 'vision_model', value: c.model.trim());
  }
}
