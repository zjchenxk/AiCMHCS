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
    this.fieldMasterKey,
    this.fieldKeyFile = 'data/aicmhcs.field.key',
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

  /// 字段级存储加密主密钥（base64 的 32 字节随机数，经 HKDF 派生各字段
  /// 子钥）。null 表示未配置、走密钥文件；生产（等保）环境应以环境变量
  /// 注入，实现密钥与数据库分离。
  final String? fieldMasterKey;

  /// 字段加密密钥文件路径（相对服务运行目录）。环境变量未配置且文件
  /// 不存在时首启自动生成——单机版交付没有配置环节，密钥随安装目录落盘。
  final String fieldKeyFile;

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
    fieldMasterKey: Platform.environment['AICMHCS_FIELD_MASTER_KEY'],
    fieldKeyFile:
        Platform.environment['AICMHCS_FIELD_KEY_FILE'] ??
        'data/aicmhcs.field.key',
  );
}
