import 'dart:convert';

import 'package:client/main.dart';
import 'package:common/utils/security_util.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// 加密 API 客户端：自动携带 token、请求体封入信封、响应解出信封，
/// 并按统一响应格式校验 code/message/data 后返回 data。
/// login 等明文接口不经过本类（仍走 AuthService）。
class BaseService {
  http.Client client = http.Client();
  String apiUrl = '';

  /// 启动时从 assets/config.json 读取后端地址。
  Future<void> loadConfig() async {
    final config = jsonDecode(await rootBundle.loadString('assets/config.json')) as Map<String, dynamic>;
    apiUrl = config['apiUrl'] as String;
  }

  ///param path: 接口路径（如 /api/auth/me）
  ///param queryParameters: URL 查询参数（GET 请求为明文，不进加密信封）
  ///returns: 解密并校验后的 data，失败抛带 message 的异常
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParameters}) {
    return _request('GET', path, null, queryParameters: queryParameters);
  }

  ///param path: 接口路径
  ///param body: 明文请求体（自动加密）
  ///returns: 解密并校验后的 data，失败抛带 message 的异常
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) => _request('POST', path, body);

  ///param path: 接口路径
  ///param body: 明文请求体（自动加密）
  ///returns: 解密并校验后的 data，失败抛带 message 的异常
  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) => _request('PUT', path, body);

  ///param path: 接口路径（无请求体，DELETE 不进加密信封）
  ///returns: 解密并校验后的 data，失败抛带 message 的异常
  Future<Map<String, dynamic>> delete(String path) => _request('DELETE', path, null);

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    Map<String, dynamic>? body, {
    Map<String, String>? queryParameters,
  }) async {
    if (token == null || sessionKey == null) {
      throw Exception('用户未登录或登录已过期，请重新登录！');
    }

    var uri = Uri.parse('$apiUrl$path');
    if (queryParameters != null && queryParameters.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParameters);
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final http.Response response;
    if (body == null) {
      response = method == 'DELETE' ? await client.delete(uri, headers: headers) : await client.get(uri, headers: headers);
    } else {
      final sealed = await SecurePayload.seal(sessionKey!, body);
      final encoded = jsonEncode(sealed);
      response = method == 'PUT' ? await client.put(uri, headers: headers, body: encoded) : await client.post(uri, headers: headers, body: encoded);
    }

    var jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

    // 明文形态（无会话时的 401/500 等框架错误）直接进入统一格式校验。
    if (jsonResponse.containsKey('payload')) {
      if (sessionKey == null) {
        throw Exception('用户未登录或登录已过期，请重新登录！');
      }
      try {
        jsonResponse = await SecurePayload.open(sessionKey!, jsonResponse);
      } on SecurePayloadException {
        throw Exception('响应解密失败！');
      }
    }

    if (!jsonResponse.containsKey('code')) {
      throw Exception('响应中未包含: code');
    }
    if (jsonResponse['code'] != 0) {
      throw Exception(jsonResponse['message'] ?? '未知错误');
    }
    if (!jsonResponse.containsKey('data')) {
      throw Exception('响应中未包含: data');
    }
    return jsonResponse['data'] as Map<String, dynamic>;
  }
}
