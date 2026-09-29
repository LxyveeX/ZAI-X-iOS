import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// AI 服务的连线设定（端点、Key、模型）
///
/// 仓库里不存放明文：建置时由 tools/ai/make_ai_defines.dart 用随机遮罩混淆，
/// 再以 --dart-define 注入 ZAI_AI_A（混淆后的内容）与 ZAI_AI_B（遮罩）。
/// 没有注入时 [current] 为 null，App 会隐藏 AI 功能。
///
/// 混淆只能避免设定出现在仓库与一般的字串搜寻里；安装包仍可能被反编译还原，
/// 用量上限请在 AI 服务端设定。
class AiServiceConfig {
  const AiServiceConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  /// OpenAI 相容端点，不含结尾斜线，例如 https://example.com/v1
  final String baseUrl;
  final String apiKey;
  final String model;

  static const String _payload = String.fromEnvironment('ZAI_AI_A');
  static const String _mask = String.fromEnvironment('ZAI_AI_B');

  /// 这个建置内建的设定；没有就是 null
  static final AiServiceConfig? current = decode(_payload, _mask);

  /// 读取明文设定（建置工具与测试使用），格式不对就回 null
  static AiServiceConfig? fromJson(Map<String, dynamic> json) {
    final baseUrl = '${json['baseUrl'] ?? ''}'
        .trim()
        .replaceFirst(RegExp(r'/+$'), '');
    final apiKey = '${json['apiKey'] ?? ''}'.trim();
    final model = '${json['model'] ?? ''}'.trim();
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    if (apiKey.isEmpty || model.isEmpty) return null;
    return AiServiceConfig(baseUrl: baseUrl, apiKey: apiKey, model: model);
  }

  /// 把设定混淆成 dart-define 用的两段 base64
  static ({String payload, String mask}) encode(
    Map<String, dynamic> json, {
    Random? random,
  }) {
    final config = fromJson(json);
    if (config == null) {
      throw const FormatException(
          'AI 设定需要 https 的 baseUrl，以及 apiKey 与 model');
    }
    final plain = utf8.encode(jsonEncode({
      'u': config.baseUrl,
      'k': config.apiKey,
      'm': config.model,
    }));
    final rng = random ?? Random.secure();
    final mask = Uint8List(plain.length);
    final data = Uint8List(plain.length);
    for (var i = 0; i < plain.length; i++) {
      mask[i] = rng.nextInt(256);
      data[i] = plain[i] ^ mask[i];
    }
    return (payload: base64.encode(data), mask: base64.encode(mask));
  }

  /// 还原 [encode] 的结果；任何格式问题都回 null
  static AiServiceConfig? decode(String payload, String mask) {
    if (payload.isEmpty || mask.isEmpty) return null;
    try {
      final data = base64.decode(payload);
      final key = base64.decode(mask);
      if (data.isEmpty || data.length != key.length) return null;
      final plain = Uint8List(data.length);
      for (var i = 0; i < data.length; i++) {
        plain[i] = data[i] ^ key[i];
      }
      final json = jsonDecode(utf8.decode(plain));
      if (json is! Map) return null;
      return fromJson({
        'baseUrl': json['u'],
        'apiKey': json['k'],
        'model': json['m'],
      });
    } catch (_) {
      return null;
    }
  }
}
