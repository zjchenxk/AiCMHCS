import 'package:server/app_config.dart';
import 'package:server/db/database_gateway.dart';
import 'package:server/db/sqlite_gateway.dart';
import 'package:server/dm/dm_gateway.dart';

/// 按配置打开数据库网关：driver=dm → 达梦（DPI），driver=sqlite →
/// SQLite 数据文件。启动脚本（main.dart）与工具（tool/）统一经此入口，
/// 保证两种发行档（网络版 / 单机版）走同一套初始化逻辑。
Future<DatabaseGateway> openDatabaseGateway(AppConfig config) async {
  switch (config.dbDriver) {
    case 'dm':
      return DmGateway.start(
        host: config.dbHost,
        port: config.dbPort,
        user: config.dbUser,
        password: config.dbPassword,
        dmHome: config.dmHome,
      );
    case 'sqlite':
      return SqliteGateway.start(config.dbFile);
    default:
      throw FormatException(
        '未知的 AICMHCS_DB_DRIVER 取值：${config.dbDriver}（可选 dm / sqlite）',
      );
  }
}
