import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:server/app_config.dart';
import 'package:server/services/initial_screening_service.dart';

/// 初筛 AI 建议服务：按年龄段 + 初筛发现调用 DeepSeek 生成健康宣教与
/// 干预指导（需求：字数控制在 200 字以内）。
///
/// API Key 由服务端配置（`AICMHCS_DEEPSEEK_API_KEY`，未配置时用
/// [AppConfig.deepseekApiKey] 的开发机默认值），**不经浏览器**——客户端
/// 只调本服务端接口，避免密钥泄露与 CORS 问题。基础地址/模型名可经
/// 环境变量指向内网代理或自建网关。
///
/// 连通性：调用前先做一次 TCP 连通性探测（3 秒超时），探测失败或请求
/// 阶段出现网络类异常（连接被拒/域名解析失败/TLS 握手失败等）时统一
/// 提示「无法连接互联网」；生成超时另作超时提示。
class AiGuidanceService {
  /// 构造函数：注入应用配置、可选 HTTP 客户端与连通性探测（测试注入用）。
  AiGuidanceService(this._config, {http.Client? client, Future<void> Function(Uri uri)? connectivityProbe}) : _client = client ?? http.Client(), _probe = connectivityProbe ?? _tcpProbe;

  final AppConfig _config;

  final http.Client _client;

  /// 连通性探测（缺省为 TCP connect；测试可注入固定抛错/成功）。
  final Future<void> Function(Uri uri) _probe;

  /// 探测超时（外网连通时毫秒级返回；不可达时快速失败）。
  static const Duration _probeTimeout = Duration(seconds: 3);

  /// 默认探测：对目标地址做 TCP 连接（https 443 / http 80），能连上即
  /// 视为可访问外网。
  static Future<void> _tcpProbe(Uri uri) async {
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final socket = await Socket.connect(uri.host, port, timeout: _probeTimeout);
    socket.destroy();
  }

  /// 调用超时（DeepSeek 生成 200 字内文本通常数秒，留足余量）。
  static const Duration _timeout = Duration(seconds: 30);

  /// 生成初筛 AI 建议文本。
  ///
  ///param month: 当前初筛年龄段（CHECK_MONTH，如 18）
  ///param sex: 儿童性别码值（1-男，2-女；其余按「儿」措辞）
  ///param warningSignResult: 预警征象筛查结果（未见异常或条目名称顿号连接）
  ///param languageSocialResult: 语言功能和社会交往能力询问结果
  ///returns: AI 生成的指导建议文本（已去除首尾空白）
  Future<String> suggest({
    required int month,
    required String sex,
    required String warningSignResult,
    required String languageSocialResult,
  }) async {
    final apiKey = _config.deepseekApiKey?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw const AsdException(400, 40001, 'DeepSeek API Key 未配置，请经环境变量 AICMHCS_DEEPSEEK_API_KEY 注入');
    }
    final findings = _findingsText(warningSignResult, languageSocialResult);
    final prompt =
        '${_sexLabel(sex)}，$month月龄，今天在基层医疗机构进行孤独症初筛时发现：$findings，'
        '请站在基层医疗机构角度，向儿童家长提供相关健康宣教和干预指导，字数控制在200字以内';

    final uri = Uri.parse('${_config.deepseekBaseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    // 连通性预检：连不上外网直接给明确提示，不进入请求阶段
    try {
      await _probe(uri);
    } catch (_) {
      throw const AsdException(400, 40001, '无法连接互联网');
    }
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
            body: jsonEncode({
              'model': _config.deepseekModel,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
              'temperature': 0.7,
              'max_tokens': 600,
              'stream': false,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      // 连接已建立但生成超时（非断网），单独提示
      throw const AsdException(400, 40001, 'DeepSeek 请求超时，请稍后重试');
    } catch (e) {
      // 网络类异常（连接被拒/解析失败/TLS 握手失败等）统一提示无法连接互联网
      if (e is SocketException || e is HandshakeException || e is HttpException || e is http.ClientException) {
        throw const AsdException(400, 40001, '无法连接互联网');
      }
      throw AsdException(400, 40001, 'DeepSeek 请求失败：$e');
    }
    if (response.statusCode != 200) {
      throw AsdException(400, 40001, 'DeepSeek 返回 HTTP ${response.statusCode}：${_brief(response.body)}');
    }
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const AsdException(400, 40001, 'DeepSeek 响应解析失败');
    }
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw AsdException(400, 40001, 'DeepSeek 未返回内容：${_brief(response.body)}');
    }
    final message = (choices.first as Map<String, dynamic>)['message'];
    final content = message is Map<String, dynamic> ? (message['content'] as String?)?.trim() ?? '' : '';
    if (content.isEmpty) {
      throw const AsdException(400, 40001, 'DeepSeek 返回内容为空');
    }
    return content;
  }

  /// 初筛发现文本：两项均未见异常时为「未见异常」，否则取非「未见异常」
  /// 的项顿号连接。
  String _findingsText(String warningSignResult, String languageSocialResult) {
    final items = <String>[
      if (warningSignResult.trim() != InitialScreeningService.checkResultNormal) warningSignResult.trim(),
      if (languageSocialResult.trim() != InitialScreeningService.checkResultNormal) languageSocialResult.trim(),
    ].where((e) => e.isNotEmpty).toList();
    return items.isEmpty ? InitialScreeningService.checkResultNormal : items.join('、');
  }

  /// 性别措辞（1-男童，2-女童，其余「儿童」）。
  String _sexLabel(String sex) => switch (sex.trim()) {
    '1' => '男童',
    '2' => '女童',
    _ => '儿童',
  };

  /// 响应体截断（错误信息回显用，防超长）。
  String _brief(String body) => body.length <= 200 ? body : '${body.substring(0, 200)}…';
}
