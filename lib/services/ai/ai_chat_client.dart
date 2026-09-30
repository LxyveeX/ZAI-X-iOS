import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:zai_x/app/app_error.dart';
import 'package:zai_x/services/ai/ai_service_config.dart';

/// 搜索被取消（换了描述或离开页面）
class AiSearchCancelled implements Exception {
  const AiSearchCancelled();
}

/// 要求 AI 回传一个 JSON 物件的对话（测试与诊断可以换成别的实作）
abstract interface class AiJsonChat {
  Future<Map<String, dynamic>> completeJson({
    required String system,
    required String user,
    String? reasoningEffort,
    CancelToken? cancel,
  });
}

/// OpenAI 相容 /chat/completions 的最小客户端
///
/// 用独立的 Dio，不经过漫画接口的拦截器，登录 token 与请求内容都不会写进日志。
class AiChatClient implements AiJsonChat {
  AiChatClient(this.config, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
            ));

  final AiServiceConfig config;
  final Dio _dio;

  /// 送出一轮对话，要求模型只回一个 JSON 物件
  ///
  /// [reasoningEffort] 是推理模型的思考程度（none / low…），可以明显缩短等待；
  /// 端点不认得这个参数（400）时会自动拿掉再送一次。
  @override
  Future<Map<String, dynamic>> completeJson({
    required String system,
    required String user,
    String? reasoningEffort,
    CancelToken? cancel,
  }) async {
    Future<Response<dynamic>> send(String? effort) => _dio.post(
          '${config.baseUrl}/chat/completions',
          data: {
            'model': config.model,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
            'response_format': {'type': 'json_object'},
            if (effort != null) 'reasoning_effort': effort,
          },
          options: Options(
            headers: {'Authorization': 'Bearer ${config.apiKey}'},
            responseType: ResponseType.json,
          ),
          cancelToken: cancel,
        );

    Response<dynamic> response;
    try {
      try {
        response = await send(reasoningEffort);
      } on DioException catch (e) {
        if (reasoningEffort == null || e.response?.statusCode != 400) rethrow;
        response = await send(null);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) throw const AiSearchCancelled();
      throw AppError(describeError(e));
    }
    final json = decodeJsonObject(contentOf(response.data) ?? '');
    if (json == null) {
      throw AppError('AI 回传的内容无法解读，请再试一次');
    }
    return json;
  }

  /// 取出 choices[0].message.content
  static String? contentOf(dynamic data) {
    var body = data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } catch (_) {
        return null;
      }
    }
    if (body is! Map) return null;
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    final content = message['content'];
    if (content is String) return content;
    // 部分端点把内容拆成多个片段
    if (content is List) {
      return content.whereType<Map>().map((e) => '${e['text'] ?? ''}').join();
    }
    return null;
  }

  /// 从模型回覆取出第一个 JSON 物件（容许 ```json 区块或前后多余文字）
  static Map<String, dynamic>? decodeJsonObject(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    Map<String, dynamic>? tryDecode(String value) {
      try {
        final json = jsonDecode(value);
        return json is Map<String, dynamic> ? json : null;
      } catch (_) {
        return null;
      }
    }

    final direct = tryDecode(trimmed);
    if (direct != null) return direct;
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return tryDecode(trimmed.substring(start, end + 1));
  }

  /// 给使用者看的错误说明（不含网址与 Key）
  static String describeError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'AI 服务回应超时，请稍后再试';
      case DioExceptionType.connectionError:
        return '无法连接 AI 服务，请检查网络';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code == 401 || code == 403) return 'AI 服务认证失败';
        if (code == 429) return 'AI 服务忙碌中，请稍后再试';
        if (code >= 500) return 'AI 服务暂时无法使用（$code）';
        return 'AI 搜索失败（$code）';
      default:
        return 'AI 搜索失败，请稍后再试';
    }
  }
}
