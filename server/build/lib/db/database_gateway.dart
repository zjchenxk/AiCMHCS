/// 数据库方言。
enum DbDialect {
  /// 达梦 DM8（DPI 原生接口，网络版）。
  dm,

  /// SQLite（单机版内嵌数据库）。
  sqlite,
}

/// 格式化为两库通用的时间戳文本（`YYYY-MM-DD HH:MM:SS`，本地时间）。
///
/// 时间列的值统一由写入方在 Dart 侧生成并作为参数绑定，不使用 SQL 端
/// 时间函数：达梦绑定字符串可隐式写入 TIMESTAMP(0)，而 SQLite 各发行
/// 构建对 `'localtime'` 修饰符支持不一（Windows 系统 winsqlite3.dll
/// 直接返回 NULL），其 CURRENT_TIMESTAMP 又是 UTC。
String formatTimestamp(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-'
      '${two(time.day)} ${two(time.hour)}:${two(time.minute)}:'
      '${two(time.second)}';
}

/// 数据库操作异常（code 为达梦 / SQLite 扩展错误码）。
final class DbException implements Exception {
  DbException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'DbException $code: $message';
}

/// 查询结果。所有列均以字符串形式取回，数值/时间由调用方按需转换；
/// NULL 用 null 表示（达梦与 SQLite 网关遵循同一契约）。
final class DbResult {
  DbResult(this.columns, this.rows);

  final List<String> columns;
  final List<List<String?>> rows;

  /// 按列名取行的便捷视图。
  List<Map<String, String?>> get rowsAsMaps => rows
      .map(
        (row) => {
          for (var i = 0; i < columns.length && i < row.length; i++)
            columns[i]: row[i],
        },
      )
      .toList(growable: false);
}

/// 数据库网关抽象。业务服务统一依赖本接口，不感知底层是达梦还是
/// SQLite；实现见 [DmGateway]（server/lib/dm/dm_gateway.dart）与
/// SqliteGateway（server/lib/db/sqlite_gateway.dart）。
abstract class DatabaseGateway {
  /// 网关使用的数据库方言。
  DbDialect get dialect;

  /// 执行 SELECT（? 占位符），取回全部行。
  Future<DbResult> query(String sql, [List<Object?> params = const []]);

  /// 执行 DML（INSERT/UPDATE/DELETE），返回受影响行数。
  Future<int> execute(String sql, [List<Object?> params = const []]);

  /// 执行 DDL / 无占位符语句。
  Future<void> executeDirect(String sql);

  /// 连接探活。
  Future<void> ping();

  /// 关闭网关与底层连接。
  Future<void> close();
}
