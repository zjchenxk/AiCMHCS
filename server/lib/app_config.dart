import 'dart:io';

/// 应用配置。全部支持环境变量覆盖，默认值对准本机开发环境。
final class AppConfig {
  const AppConfig({
    required this.dbDriver,
    required this.dbHost,
    required this.dbPort,
    required this.dbUser,
    required this.dbPassword,
    required this.dbFile,
    this.dmHome,
  });

  /// 数据库驱动：`dm`（达梦，网络版默认）/ `sqlite`（单机版）。
  final String dbDriver;

  final String dbHost;
  final int dbPort;
  final String dbUser;
  final String dbPassword;

  /// SQLite 数据文件路径（仅 dbDriver=sqlite 时使用，相对服务运行目录）。
  final String dbFile;

  /// 达梦安装目录（用于定位 dmdpi.dll 及其依赖），空表示交给加载器推断。
  final String? dmHome;

  static AppConfig fromEnv() => AppConfig(
    dbDriver: Platform.environment['AICMHCS_DB_DRIVER'] ?? 'dm',
    dbHost: Platform.environment['AICMHCS_DB_HOST'] ?? 'LOCALHOST',
    dbPort:
        int.tryParse(
          Platform.environment['AICMHCS_DB_PORT'] ?? '',
        ) ??
        5236,
    // 应用使用专属账号（由 database/01_init_schema.sql 创建），
    // 不直接使用 SYSDBA，符合最小权限原则。
    dbUser: Platform.environment['AICMHCS_DB_USER'] ?? 'AICMHCS',
    dbPassword: Platform.environment['AICMHCS_DB_PASSWORD'] ?? 'Aicmhcs@2026',
    dbFile: Platform.environment['AICMHCS_DB_FILE'] ?? 'data/aicmhcs.db',
    dmHome: Platform.environment['DM_HOME'],
  );
}
