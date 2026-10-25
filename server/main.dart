import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/app_config.dart';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/database/engine/db_factory.dart';
import 'package:server/database/migrator/migrations/base/migration.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/services/admin_division_service.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/operation_log_service.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:server/utils/log_helper.dart';

/// dart_frog 自定义入口：按配置打开数据库网关（达梦 / SQLite）、
/// 解析字段加密密钥、对齐结构迁移，再把网关与认证服务注入中间件管线。
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) async {
  final config = AppConfig.fromEnv();

  final db = await openDatabaseGateway(config);
  final cipher = await FieldCipher.fromConfig(config);
  var applied = const <DbMigration>[];
  try {
    applied = await SchemaMigrator(db, fieldCipher: cipher).migrate();
  } catch (_) {
    await db.close();
    rethrow;
  }

  final auth = AuthService(db, cipher);
  final adminDivisions = AdminDivisionService(db);
  final operationLogs = OperationLogService(db);
  // 静态门面：服务层深处、全局中间件等无 RequestContext 的位置经
  // LogHelper 写日志；中间件/路由经下方 provider 取同一实例。
  LogHelper.service = operationLogs;

  final app = handler
      .use(provider<DatabaseGateway>((_) => db))
      .use(provider<FieldCipher>((_) => cipher))
      .use(provider<AuthService>((_) => auth))
      .use(provider<AdminDivisionService>((_) => adminDivisions))
      .use(provider<OperationLogService>((_) => operationLogs));

  final server = await serve(app, ip, port);
  final dbDesc = switch (db.dialect) {
    DbDialect.dm => '达梦 DM8 ${config.dbHost}:${config.dbPort}（用户 ${config.dbUser}）',
    DbDialect.sqlite => 'SQLite（${config.dbFile}）',
  };
  final migrated = applied.isEmpty ? '' : '，已应用结构迁移 ${applied.map((m) => 'v${m.version}').join('、')}';
  final keyWarning = cipher.keyFileWasGenerated
      ? '；警告：字段加密密钥文件为本次自动生成（${config.fieldKeyFile}），'
            '请单独备份，丢失将无法解密存量数据'
      : '';
  print('AiCMHCS 后端已启动: http://${server.address.address}:${server.port}');
  print('数据库: $dbDesc$migrated$keyWarning');
  return server;
}
