import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// 认证服务：登录并返回 {token, user}（user 为后端 UserInfo 的 JSON）
class AuthService {
  http.Client client = http.Client();
  String apiUrl = '';

  /// 启动时从 assets/config.json 读取后端地址。
  Future<void> loadConfig() async {
    final config = jsonDecode(await rootBundle.loadString('assets/config.json')) as Map<String, dynamic>;
    apiUrl = config['apiUrl'] as String;
  }

  ///param userCode: 用户名
  ///param password: 明文口令
  ///returns: 登录结果 Map（token / expiresIn / user），失败抛带 message 的异常
  Future<Map<String, dynamic>> login(String userCode, String password) async {
    final response = await client.post(
      Uri.parse('$apiUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'usercode': userCode, 'password': password}),
    );

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
    if (!jsonResponse.containsKey('code')) {
      throw Exception('登录失败！响应中未包含: code');
    }
    if (jsonResponse['code'] != 0) {
      throw Exception('登录失败！${jsonResponse['message'] ?? '未知错误'}');
    }
    if (!jsonResponse.containsKey('data')) {
      throw Exception('登录失败！响应中未包含: data');
    }
    return jsonResponse['data'] as Map<String, dynamic>;
  }
}
