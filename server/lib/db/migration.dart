import 'package:server/db/database_gateway.dart';

/// 单个结构迁移：一个版本号对应一次结构变更。
///
/// 语句按方言分组：[common] 为两库通用语句（如多数 ALTER TABLE ADD
/// COLUMN），[dm] / [sqlite] 为方言专属语句（建表类型、COMMENT ON 等），
/// 执行顺序为 common → 对应方言组。
final class DbMigration {
  const DbMigration({
    required this.version,
    required this.description,
    this.common = const [],
    this.dm = const [],
    this.sqlite = const [],
  });

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

  /// 指定方言应执行的完整语句列表。
  List<String> statementsFor(DbDialect dialect) => [
    ...common,
    ...switch (dialect) {
      DbDialect.dm => dm,
      DbDialect.sqlite => sqlite,
    },
  ];
}
