// 操作日志链路冒烟脚本：验证「请求留痕 + 客户端上报 + /api/logs 防放大」
// 三个环节，走真实 HTTP + 信封加密，最后直查数据库断言落库结果。
//
// 用法（后端启动后，在 server/ 目录执行；数据库驱动环境变量须与后端一致）：
//   dart run tool/operation_log_smoke.dart                          # 达梦
//   AICMHCS_DB_DRIVER=sqlite dart run tool/operation_log_smoke.dart # 单机版
// 可用 SMOKE_BASE_URL 覆盖后端地址（默认 http://localhost:8080）。
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:common/utils/security_util.dart';
import 'package:http/http.dart' as http;

import 'package:server/app_config.dart';
import 'package:server/database/engine/db_factory.dart';

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty ? args.first : Platform.environment['SMOKE_BASE_URL'] ?? 'http://localhost:8080';
  final client = http.Client();

  // 1. 明文登录拿 token + sessionKey
  final loginResp = await client.post(
    Uri.parse('$base/api/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'usercode': 'admin', 'password': 'Admin@123'}),
  );
  final loginJson = jsonDecode(loginResp.body) as Map<String, dynamic>;
  if (loginJson['code'] != 0) {
    throw StateError('登录失败: ${loginJson['message']}');
  }
  final token = (loginJson['data'] as Map<String, dynamic>)['token'] as String;
  final sessionKey = (loginJson['data'] as Map<String, dynamic>)['sessionKey'] as String;
  print('1. 登录成功 token=${token.substring(0, 8)}...');

  Future<Map<String, dynamic>> sealed(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$base$path');
    final http.Response resp;
    if (body == null) {
      final req = http.Request(method, uri)
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });
      resp = await http.Response.fromStream(await client.send(req));
    } else {
      final req = http.Request(method, uri)
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        })
        ..body = jsonEncode(await SecurePayload.seal(sessionKey, body));
      resp = await http.Response.fromStream(await client.send(req));
    }
    var json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json.containsKey('payload')) {
      json = await SecurePayload.open(sessionKey, json);
    }
    print('   $method $path -> HTTP ${resp.statusCode} code=${json['code']} message=${json['message']}');
    if (json['code'] != 0) {
      throw StateError('接口失败: ${json['message']}');
    }
    return (json['data'] as Map<String, dynamic>?) ?? const {};
  }

  // 2. 业务请求（GET 无查询参数 + GET 带查询参数）：应各留痕一条「信息」
  await sealed('GET', '/api/admin-divisions');
  await sealed('GET', '/api/admin-divisions?parentCode=110000');

  // 3. 客户端通道上报一条「错误」日志（POST /api/logs 本身不应留痕请求日志）
  await sealed('POST', '/api/logs', {
    'logType': '错误',
    'logName': 'client:Smoke.test',
    'logContent': '模拟异常：操作日志冒烟测试\n#0      Smoke.test (smoke.dart:1:1)',
  });

  // 等待后台 fire-and-forget 的请求留痕落库（网关 isolate 异步写）
  await Future<void>.delayed(const Duration(milliseconds: 800));
  client.close();

  // 4. 直查数据库断言（驱动环境变量须与被测后端一致）
  final db = await openDatabaseGateway(AppConfig.fromEnv());
  try {
    final adminId = (await db.query(
      "SELECT ID FROM SYS_USER WHERE USER_CODE = 'admin'",
    )).rows.first.first;
    final rows = (await db.query(
      'SELECT USER_ID, LOG_TYPE, LOG_NAME, LOG_CONTENT, LOG_TIME '
      'FROM SYS_OPERATION_LOG ORDER BY ID DESC LIMIT 10',
    )).rowsAsMaps.reversed;
    print('4. 最近 ${rows.length} 条操作日志：');
    for (final row in rows) {
      final content = row['LOG_CONTENT'];
      final brief = content == null ? '-' : (content.length > 40 ? '${content.substring(0, 40)}...' : content).replaceAll('\n', r'\n');
      print('   [${row['LOG_TYPE']}] ${row['LOG_NAME']} user=${row['USER_ID'] ?? '-'} @${row['LOG_TIME']} 内容: $brief');
    }

    final requestLogHit = rows.any(
      (row) => row['LOG_NAME'] == '/api/admin-divisions' && row['LOG_TYPE'] == '信息' && row['USER_ID'] == adminId,
    );
    final queryLogged = rows.any(
      (row) => row['LOG_NAME'] == '/api/admin-divisions' && row['LOG_CONTENT'] == 'parentCode=110000',
    );
    final uploadHit = rows.any(
      (row) => row['LOG_NAME'] == 'client:Smoke.test' && row['LOG_TYPE'] == '错误' && row['USER_ID'] == adminId,
    );
    final noAmplify = !rows.any((row) => row['LOG_NAME'] == '/api/logs');

    print('5. 断言：请求留痕=$requestLogHit 查询串留痕=$queryLogged 客户端上报=$uploadHit 日志接口防放大=$noAmplify');
    if (!requestLogHit || !queryLogged || !uploadHit || !noAmplify) {
      throw StateError('操作日志链路断言失败');
    }
    print('操作日志链路全部正常');
  } finally {
    await db.close();
  }
}
