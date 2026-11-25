import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:server/app_config.dart';
import 'package:server/services/ai_guidance_service.dart';
import 'package:server/services/initial_screening_service.dart';
import 'package:test/test.dart';

/// 固定返回预设响应的伪 HTTP 客户端。
class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => handler(request);
}

/// 构造配置（仅 AI 相关字段有意义）。
AppConfig buildConfig({String? apiKey = 'sk-test'}) => AppConfig(
  dbDriver: 'sqlite',
  dbHost: 'LOCALHOST',
  dbPort: 5236,
  dbUser: 'u',
  dbPassword: 'p',
  dbFile: 'data/x.db',
  dbName: 'aicmhcs',
  deepseekApiKey: apiKey,
  deepseekBaseUrl: 'https://api.deepseek.com',
  deepseekModel: 'deepseek-chat',
);

http.StreamedResponse jsonResponse(Map<String, dynamic> body, {int status = 200}) {
  return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status);
}

/// 初筛 AI 建议服务单元测试：外网连通性判断、网络异常归类、正常与异常响应。
void main() {
  test('连通性探测失败 → 无法连接互联网', () async {
    final service = AiGuidanceService(
      buildConfig(),
      connectivityProbe: (_) async => throw const SocketException('offline'),
      client: _FakeClient((_) async => jsonResponse(const {})),
    );
    await expectLater(
      service.suggest(month: 18, sex: '1', warningSignResult: '与人无目光交流', languageSocialResult: '社会交往能力障碍或倒退'),
      throwsA(predicate((e) => e is AsdException && e.message == '无法连接互联网')),
    );
  });

  test('探测通过但请求阶段网络异常 → 无法连接互联网', () async {
    for (final error in <Object>[
      const SocketException('connection refused'),
      http.ClientException('connection closed before full header was received'),
      const HandshakeException('handshake failed'),
    ]) {
      final service = AiGuidanceService(
        buildConfig(),
        connectivityProbe: (_) async {},
        client: _FakeClient((_) async => throw error),
      );
      await expectLater(
        service.suggest(month: 8, sex: '2', warningSignResult: '未见异常', languageSocialResult: '未见异常'),
        throwsA(predicate((e) => e is AsdException && e.message == '无法连接互联网')),
        reason: '错误 $error 应归类为无法连接互联网',
      );
    }
  });

  test('生成超时 → 单独的超时提示（不误报断网）', () async {
    final service = AiGuidanceService(
      buildConfig(),
      connectivityProbe: (_) async {},
      client: _FakeClient((_) async => throw TimeoutException('timeout')),
    );
    await expectLater(
      service.suggest(month: 8, sex: '1', warningSignResult: '未见异常', languageSocialResult: '未见异常'),
      throwsA(predicate((e) => e is AsdException && e.message == 'DeepSeek 请求超时，请稍后重试')),
    );
  });

  test('正常返回内容；提示词含性别/月龄/初筛发现；API Key 走请求头', () async {
    late http.BaseRequest captured;
    final service = AiGuidanceService(
      buildConfig(),
      connectivityProbe: (_) async {},
      client: _FakeClient((request) async {
        captured = request;
        return jsonResponse({
          'choices': [
            {
              'message': {'content': '  建议尽快复筛并加强亲子互动训练。  '},
            },
          ],
        });
      }),
    );
    final text = await service.suggest(
      month: 18,
      sex: '1',
      warningSignResult: '与人无目光交流',
      languageSocialResult: '社会交往能力障碍或倒退',
    );
    expect(text, '建议尽快复筛并加强亲子互动训练。');
    expect(captured.url.toString(), 'https://api.deepseek.com/chat/completions');
    expect(captured.headers['Authorization'], 'Bearer sk-test');
    final body = jsonDecode((captured as http.Request).body) as Map<String, dynamic>;
    final prompt = ((body['messages'] as List).first as Map<String, dynamic>)['content'] as String;
    expect(prompt, contains('男童'));
    expect(prompt, contains('18月龄'));
    expect(prompt, contains('与人无目光交流'));
    expect(prompt, contains('社会交往能力障碍或倒退'));
    expect(prompt, contains('字数控制在200字以内'));
  });

  test('两项均未见异常时提示词按「未见异常」表述', () async {
    late http.BaseRequest captured;
    final service = AiGuidanceService(
      buildConfig(),
      connectivityProbe: (_) async {},
      client: _FakeClient((request) async {
        captured = request;
        return jsonResponse({
          'choices': [
            {
              'message': {'content': '继续定期随访'},
            },
          ],
        });
      }),
    );
    await service.suggest(month: 3, sex: '2', warningSignResult: '未见异常', languageSocialResult: '未见异常');
    final prompt = (((jsonDecode((captured as http.Request).body) as Map<String, dynamic>)['messages'] as List<dynamic>).first as Map<String, dynamic>)['content'] as String;
    expect(prompt, contains('女童，3月龄'));
    expect(prompt, contains('发现：未见异常，'));
  });

  test('未配置 Key / HTTP 非 200 / 空内容 均给出明确错误', () async {
    final noKey = AiGuidanceService(
      buildConfig(apiKey: null),
      connectivityProbe: (_) async {},
      client: _FakeClient((_) async => jsonResponse(const {})),
    );
    await expectLater(
      noKey.suggest(month: 3, sex: '1', warningSignResult: '未见异常', languageSocialResult: '未见异常'),
      throwsA(predicate((e) => e is AsdException && e.message.contains('AICMHCS_DEEPSEEK_API_KEY'))),
    );

    final http401 = AiGuidanceService(
      buildConfig(),
      connectivityProbe: (_) async {},
      client: _FakeClient((_) async => jsonResponse(const {'error': 'unauthorized'}, status: 401)),
    );
    await expectLater(
      http401.suggest(month: 3, sex: '1', warningSignResult: '未见异常', languageSocialResult: '未见异常'),
      throwsA(predicate((e) => e is AsdException && e.message.contains('HTTP 401'))),
    );

    final empty = AiGuidanceService(
      buildConfig(),
      connectivityProbe: (_) async {},
      client: _FakeClient((_) async => jsonResponse(const {'choices': <Object>[]})),
    );
    await expectLater(
      empty.suggest(month: 3, sex: '1', warningSignResult: '未见异常', languageSocialResult: '未见异常'),
      throwsA(predicate((e) => e is AsdException && e.message.contains('未返回内容'))),
    );
  });
}
