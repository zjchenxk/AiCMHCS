import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/app_config.dart';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/database/engine/db_factory.dart';
import 'package:server/database/migrator/migration.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/utils/field_cipher.dart';

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

  final app = handler
      .use(provider<DatabaseGateway>((_) => db))
      .use(provider<FieldCipher>((_) => cipher))
      .use(provider<AuthService>((_) => auth));

  final server = await serve(app, ip, port);
  final dbDesc = switch (db.dialect) {
    DbDialect.dm =>
      '达梦 DM8 ${config.dbHost}:${config.dbPort}（用户 ${config.dbUser}）',
    DbDialect.sqlite => 'SQLite（${config.dbFile}）',
  };
  final migrated = applied.isEmpty
      ? ''
      : '，已应用结构迁移 ${applied.map((m) => 'v${m.version}').join('、')}';
  final keyWarning = cipher.keyFileWasGenerated
      ? '；警告：字段加密密钥文件为本次自动生成（${config.fieldKeyFile}），'
            '请单独备份，丢失将无法解密存量数据'
      : '';
  print('AiCMHCS 后端已启动: http://${server.address.address}:${server.port}');
  print('数据库: $dbDesc$migrated$keyWarning');
  return server;
}
