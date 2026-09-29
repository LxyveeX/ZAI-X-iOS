// 把 AI 服务设定（baseUrl / apiKey / model）转成 flutter build 的
// --dart-define-from-file 档。仓库里不存放任何明文，设定来源只有两种：
//
//   本机：dart run tools/ai/make_ai_defines.dart --in <仓库外的设定.json> --out <输出.json>
//   CI：  dart run tools/ai/make_ai_defines.dart --env ZAI_AI_CONFIG --out "$RUNNER_TEMP/ai_defines.json"
//
// 每次执行都换一组随机遮罩；没有设定时输出 {}，App 会隐藏 AI 功能。
// 这个工具不会把设定内容印到终端。
import 'dart:convert';
import 'dart:io';

import 'package:zai_x/services/ai/ai_service_config.dart';

void main(List<String> args) {
  String? option(String name) {
    final index = args.indexOf(name);
    return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
  }

  final out = option('--out');
  final input = option('--in');
  final env = option('--env');
  if (out == null || (input == null && env == null)) {
    stderr.writeln('用法：--in <设定.json> 或 --env <环境变量>，并指定 --out <输出.json>');
    exit(64);
  }

  final raw = input != null
      ? File(input).readAsStringSync()
      : Platform.environment[env] ?? '';
  var defines = <String, String>{};
  if (raw.trim().isNotEmpty) {
    final dynamic json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      stderr.writeln('AI 设定不是有效的 JSON');
      exit(65);
    }
    if (json is! Map<String, dynamic>) {
      stderr.writeln('AI 设定必须是 JSON 物件');
      exit(65);
    }
    try {
      final encoded = AiServiceConfig.encode(json);
      defines = {'ZAI_AI_A': encoded.payload, 'ZAI_AI_B': encoded.mask};
    } on FormatException catch (e) {
      stderr.writeln(e.message);
      exit(65);
    }
  }
  File(out).writeAsStringSync(jsonEncode(defines));
  stdout.writeln(defines.isEmpty ? '没有 AI 设定，这次建置不含 AI 功能' : '已写入混淆后的 AI 设定');
}
