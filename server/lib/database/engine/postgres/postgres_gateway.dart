import 'dart:async';
import 'dart:isolate';

import 'package:postgres/postgres.dart';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/database/engine/worker_gateway.dart';

/// PostgreSQL 网关（非信创医院可选发行档，`postgres` 包纯 Dart 驱动）。
///
/// 与达梦 / SQLite 网关共用同一套「独立工作隔离区 + 串行执行」架构
/// （[WorkerGateway]）：连接在独立隔离区内串行执行语句，主隔离区经消息
/// 通信访问，30 秒超时语义一致。语句语义与达梦网关对齐：逐条自动提交、
/// execute 返回受影响行数、结果所有列以字符串返回。
///
/// 方言适配（业务层无感知）：
/// - 占位符：业务 SQL 统一写 `?`，经 [rewrite] 在发送前改写为 PostgreSQL
///   原生位置参数 `$1..$n`（字符串字面量内的 `?` 不改写）；参数以列表
///   绑定、unspecified OID 下发，由服务端按目标列隐式转换（文本入整型/
///   日期列等，与达梦 / SQLite 行为一致）；
/// - 标识符大小写：PostgreSQL 将未加引号的标识符折叠为小写，结果列名
///   统一转大写返回，与两库网关的列名契约一致；
/// - 时间列：DATE 列格式化为 `YYYY-MM-DD`、TIMESTAMP 列格式化为
///   `YYYY-MM-DD HH:MM:SS`（本地时间），与达梦 DPI 的字符串口径一致；
/// - 重连：查询 / 探活失败自动重连并重试一次，execute / executeDirect
///   不重试（防重复写入），同达梦网关。
class PostgresGateway extends WorkerGateway {
  PostgresGateway._(super.worker, super.replies, super.errors);

  static PostgresGateway? _cached;

  /// 启动（或复用）网关。dart_frog dev 热重载会重新执行 main 入口，
  /// 缓存保证不会泄漏出多个工作隔离区。
  ///
  /// ssl 为 true 时库连接要求 TLS（SslMode.require）；默认 false——
  /// 信创内网直连场景库侧通常不提供 SSL，且业务报文已有信封加密承担
  /// 通信保密性（配置见 AppConfig.dbSsl / 环境变量 AICMHCS_DB_SSL）。
  static Future<PostgresGateway> start({
    required String host,
    required int port,
    required String database,
    required String user,
    required String password,
    bool ssl = false,
  }) async {
    if (_cached case final cached? when !cached.isClosed) return cached;
    final gateway = await WorkerGateway.spawn(
      entry: _postgresWorkerMain,
      boot: {'host': host, 'port': port, 'database': database, 'user': user, 'password': password, 'ssl': ssl},
      build: PostgresGateway._,
    );
    return _cached = gateway;
  }

  @override
  DbDialect get dialect => DbDialect.postgres;

  @override
  (String, List<Object?>) rewrite(String sql, List<Object?> params) => rewritePgPlaceholders(sql, params);

  @override
  Exception deserializeError(int? code, String message) => DbException(code ?? -1, message);

  @override
  void onClosed() {
    if (identical(_cached, this)) _cached = null;
  }
}

/// 把业务 SQL 的 `?` 占位符改写为 PostgreSQL 位置参数 `$1..$n`。
///
/// 逐字符扫描，字符串字面量（单引号串，'' 转义）内的 `?` 保持原样；
/// 语句与注释内不存在其他需要回避的 `?` 场景（业务 SQL 不用 E'' 转义
/// 串与 dollar-quoted 字符串）。
(String, List<Object?>) rewritePgPlaceholders(String sql, List<Object?> params) {
  const quote = "'";
  if (!sql.contains('?') || params.isEmpty) {
    return (sql, params);
  }
  final sb = StringBuffer();
  var inString = false;
  var index = 0;
  for (var i = 0; i < sql.length; i++) {
    final ch = sql[i];
    if (inString) {
      sb.write(ch);
      if (ch == quote) {
        if (i + 1 < sql.length && sql[i + 1] == quote) {
          sb.write(quote);
          i++;
        } else {
          inString = false;
        }
      }
      continue;
    }
    if (ch == quote) {
      inString = true;
      sb.write(ch);
      continue;
    }
    if (ch == '?') {
      index++;
      sb.write('\$$index');
      continue;
    }
    sb.write(ch);
  }
  return (sb.toString(), params);
}

/// 工作区入口：建立连接并进入命令循环。
Future<void> _postgresWorkerMain(Map<Object?, Object?> boot) async {
  final commands = ReceivePort();
  final readyPort = boot['readyPort']! as SendPort;
  Connection connection;
  try {
    connection = await _connect(boot);
  } catch (e) {
    readyPort.send({'ok': false, 'error': e.toString()});
    commands.close();
    return;
  }
  readyPort.send({'ok': true, 'port': commands.sendPort});

  final ref = _ConnRef(connection);
  serveWorkerCommands(
    commands,
    boot,
    codeOf: (e) => e is ServerException ? int.tryParse(e.code ?? '') : null,
    dispatch: (msg) => _postgresExecuteOp(msg, ref, boot),
  );
}

Future<Connection> _connect(Map<Object?, Object?> boot) => Connection.open(
  Endpoint(
    host: boot['host']! as String,
    port: boot['port']! as int,
    database: boot['database']! as String,
    username: boot['user']! as String,
    password: boot['password']! as String,
  ),
  // 与网关层的 30 秒操作超时（WorkerGateway.invoke）对齐，避免底层
  // 查询久挂占住串行工作区。SSL 默认关闭（信创内网直连场景库侧通常
  // 不提供 SSL，业务报文已有信封加密），可经 boot['ssl'] 打开。
  settings: ConnectionSettings(
    connectTimeout: const Duration(seconds: 10),
    queryTimeout: const Duration(seconds: 30),
    sslMode: boot['ssl'] == true ? SslMode.require : SslMode.disable,
  ),
);

class _ConnRef {
  _ConnRef(this.con);

  Connection con;
}

/// 执行单个命令操作；查询 / 探活失败重连并重试一次，DML 不重试。
Future<Object?> _postgresExecuteOp(Map<Object?, Object?> msg, _ConnRef ref, Map<Object?, Object?> boot) async {
  Future<Connection> reconnect() async {
    try {
      await ref.con.close();
    } catch (_) {
      // 旧连接可能已断开。
    }
    return ref.con = await _connect(boot);
  }

  final sql = msg['sql'] as String?;
  final params = (msg['params'] as List?)?.cast<Object?>() ?? const [];
  switch (msg['op']! as String) {
    case 'ping':
      try {
        await ref.con.execute('SELECT 1');
        return null;
      } catch (_) {
        await (await reconnect()).execute('SELECT 1');
        return null;
      }
    case 'query':
      try {
        return _toDbResult(await ref.con.execute(sql!, parameters: params));
      } catch (_) {
        return _toDbResult(await (await reconnect()).execute(sql!, parameters: params));
      }
    case 'execute':
      final result = await ref.con.execute(sql!, parameters: params, ignoreRows: true);
      return result.affectedRows;
    case 'executeDirect':
      await ref.con.execute(sql!);
      return null;
    case 'close':
      await ref.con.close();
      return null;
    default:
      throw StateError('未知操作 ${msg['op']}');
  }
}

/// 列类型 OID：date / timestamp（without time zone）/ timestamptz。
const _dateOid = 1082;
const _timestampOid = 1114;
const _timestamptzOid = 1184;

/// 所有列统一转字符串，与达梦 / SQLite 网关的结果契约保持一致。
///
/// 时间列按 OID 定格式：DATE → `YYYY-MM-DD`、TIMESTAMP →
/// `YYYY-MM-DD HH:MM:SS`（timestamptz 先转本地时区）；其余类型取
/// `toString()`（int/numeric/bool 等）。列名统一转大写（PostgreSQL
/// 将未加引号标识符折叠为小写，业务代码按大写列名取值）。
DbResult _toDbResult(Result result) {
  final columns = [for (final col in result.schema.columns) (col.columnName ?? '').toUpperCase()];
  final rows = <List<String?>>[
    for (final row in result)
      [
        for (var i = 0; i < row.length; i++) _cellToString(row[i], _typeOidOf(result, i)),
      ],
  ];
  return DbResult(columns, rows);
}

/// 取第 [index] 列的类型 OID（schema 缺列时为 null，按通用值处理）。
int? _typeOidOf(Result result, int index) => index < result.schema.columns.length ? result.schema.columns[index].typeOid : null;

String? _cellToString(Object? value, int? typeOid) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    final t = typeOid == _timestamptzOid ? value.toLocal() : value;
    return switch (typeOid) {
      _dateOid => _formatDate(t),
      _timestampOid || _timestamptzOid => '${_formatDate(t)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}',
      _ => t.toString(),
    };
  }
  return value.toString();
}

String _formatDate(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

String _two(int n) => n.toString().padLeft(2, '0');
