import 'dart:io';

import 'package:aicmhcs_server/app_config.dart';
import 'package:aicmhcs_server/dm/dm_gateway.dart';
import 'package:aicmhcs_server/services/auth_service.dart';
import 'package:dart_frog/dart_frog.dart';

/// dart_frog 自定义入口：先初始化数据库网关与认证服务，
/// 再把它们注入中间件管线。
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) async {
  final config = AppConfig.fromEnv();

  final db = await DmGateway.start(
    host: config.dbHost,
    port: config.dbPort,
    user: config.dbUser,
    password: config.dbPassword,
    dmHome: config.dmHome,
  );

  final auth = AuthService(db);

  final app = handler
      .use(provider<DmGateway>((_) => db))
      .use(provider<AuthService>((_) => auth));

  final server = await serve(app, ip, port);
  print('AiCMHCS 后端已启动: http://${server.address.address}:${server.port}');
  print('数据库: DM8 ${config.dbHost}:${config.dbPort}（用户 ${config.dbUser}）');
  return server;
}
