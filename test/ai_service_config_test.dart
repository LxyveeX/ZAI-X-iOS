import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zai_x/services/ai/ai_service_config.dart';

void main() {
  const sample = <String, dynamic>{
    'baseUrl': 'https://ai.example.com/v1/',
    'apiKey': 'sk-test-0123456789',
    'model': 'demo-model',
  };

  test('encode then decode restores the config', () {
    final encoded = AiServiceConfig.encode(sample, random: Random(7));
    final config = AiServiceConfig.decode(encoded.payload, encoded.mask)!;
    expect(config.baseUrl, 'https://ai.example.com/v1');
    expect(config.apiKey, 'sk-test-0123456789');
    expect(config.model, 'demo-model');
  });

  test('encoded defines do not reveal the key or endpoint', () {
    final encoded = AiServiceConfig.encode(sample, random: Random(7));
    for (final value in [encoded.payload, encoded.mask]) {
      final bytes = String.fromCharCodes(base64.decode(value));
      for (final secret in ['sk-test', 'example.com', 'demo-model']) {
        expect(value.contains(secret), isFalse);
        expect(bytes.contains(secret), isFalse);
      }
    }
  });

  test('every build uses a new mask', () {
    final a = AiServiceConfig.encode(sample, random: Random(1));
    final b = AiServiceConfig.encode(sample, random: Random(2));
    expect(a.payload, isNot(b.payload));
    expect(a.mask, isNot(b.mask));
  });

  test('missing or broken defines disable the feature', () {
    final encoded = AiServiceConfig.encode(sample, random: Random(7));
    expect(AiServiceConfig.decode('', ''), isNull);
    expect(AiServiceConfig.decode(encoded.payload, ''), isNull);
    expect(
      AiServiceConfig.decode(encoded.payload, base64.encode([1, 2, 3])),
      isNull,
    );
    expect(AiServiceConfig.decode('not base64!', encoded.mask), isNull);
    // 测试没有注入 dart-define，AI 功能应该是关闭的
    expect(AiServiceConfig.current, isNull);
  });

  test('only https endpoints with a key and model are accepted', () {
    expect(
      AiServiceConfig.fromJson({...sample, 'baseUrl': 'http://ai.example.com'}),
      isNull,
    );
    expect(AiServiceConfig.fromJson({...sample, 'apiKey': ' '}), isNull);
    expect(AiServiceConfig.fromJson({...sample, 'model': ''}), isNull);
    expect(
      () => AiServiceConfig.encode({'baseUrl': 'https://x.example'}),
      throwsFormatException,
    );
  });
}
