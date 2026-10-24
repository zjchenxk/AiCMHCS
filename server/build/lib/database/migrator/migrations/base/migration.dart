import 'package:server/database/engine/database_gateway.dart';
import 'package:server/utils/field_cipher.dart';

/// 数据订正回调：迁移语句全部执行成功后、写版本记录前运行。
///
/// 用于语句表达不了的数据订正（如存量明文字段加密——必须在应用侧
/// 持密钥完成），须幂等：中断后重跑对已处理行不再改动。
typedef MigrationDataFix = Future<void> Function(DatabaseGateway db, FieldCipher cipher);

/// 基础数据加载回调：迁移语句（及 dataFix）执行成功后、写版本记录前运行。
///
/// 用于随结构版本走的基础字典数据（如行政区划）——数据本体放资源文件
/// 而非内联进迁移代码，回调负责读取并批量写入。与 [MigrationDataFix] 的
/// 区别：不依赖字段加密密钥。须幂等：建议「先清空再全量导入」，
/// 中断后重跑不会残留半途数据。
typedef MigrationSeed = Future<void> Function(DatabaseGateway db);

/// 单个结构迁移：一个版本号对应一次结构变更。
///
/// 语句按方言分组：[common] 为两库通用语句（如多数 ALTER TABLE ADD
/// COLUMN），[dm] / [sqlite] 为方言专属语句（建表类型、COMMENT ON 等），
/// 执行顺序为 common → 对应方言组。
final class DbMigration {
  /// 构造函数：版本号、描述、语句组、可选数据订正与基础数据加载。
  const DbMigration({required this.version, required this.description, this.common = const [], this.dm = const [], this.sqlite = const [], this.dataFix, this.seed});

  /// 版本号，全库唯一且必须严格递增。
  final int version;

  /// 中文描述（写入 SYS_SCHEMA_VERSION 版本历史）。
  final String description;

  /// 两库通用语句。
  final List<String> common;

  /// 仅达梦执行的语句。
  final List<String> dm;

  /// 仅 SQLite 执行的语句。
  final List<String> sqlite;

  /// 语句执行成功后运行的数据订正（可选）。声明了本回调的迁移，
  /// SchemaMigrator 必须注入 FieldCipher，否则启动即报错。
  final MigrationDataFix? dataFix;

  /// 语句与数据订正之后运行的基础数据加载（可选），不要求密钥。
  final MigrationSeed? seed;

  /// 指定方言应执行的完整语句列表。
  List<String> statementsFor(DbDialect dialect) => [
    ...common,
    ...switch (dialect) {
      DbDialect.dm => dm,
      DbDialect.sqlite => sqlite,
    },
  ];
}
