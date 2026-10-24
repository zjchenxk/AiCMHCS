import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/database/engine/worker_gateway.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

/// SQLite 网关（单机版）。
///
/// 连接放进独立工作隔离区串行执行，语句语义与达梦网关一致
/// （逐条自动提交、execute 返回受影响行数、结果所有列以字符串返回）。
/// 库文件不存在时自动创建（含父目录）；`:memory:` 为进程内临时库，
/// 仅供测试使用。
class SqliteGateway extends WorkerGateway {
  SqliteGateway._(super.worker, super.replies, super.errors);

  /// 按数据文件绝对路径缓存（dart_frog dev 热重载会重新执行 main 入口，
  /// 缓存保证不泄漏出多个工作隔离区）；`:memory:` 每次都要新实例，不缓存。
  static final _cached = <String, SqliteGateway>{};

  /// 打开（或复用）指定路径的 SQLite 网关。
  static Future<SqliteGateway> start(String path) async {
    final cached = _cachedByPath(path);
    if (cached != null) {
      if (_cached[cached] case final gw? when !gw.isClosed) return gw;
      // 文件库：确保父目录存在（单机版数据目录可能在首次运行时才创建）。
      final parent = File(path).parent;
      if (parent.path.isNotEmpty) {
        await parent.create(recursive: true);
      }
    }
    final gateway = await WorkerGateway.spawn(
      entry: _sqliteWorkerMain,
      boot: {'path': path},
      build: SqliteGateway._,
    );
    if (cached != null) _cached[cached] = gateway;
    return gateway;
  }

  /// 返回缓存键；`:memory:` 不缓存返回 null。
  static String? _cachedByPath(String path) =>
      path.toLowerCase() == ':memory:' ? null : File(path).absolute.path;

  @override
  DbDialect get dialect => DbDialect.sqlite;

  @override
  Exception deserializeError(int? code, String message) =>
      DbException(code ?? -1, message);

  @override
  void onClosed() {
    _cached.removeWhere((_, gw) => identical(gw, this));
  }
}

/// 工作区入口：加载原生库、打开连接并进入命令循环。
void _sqliteWorkerMain(Map<Object?, Object?> boot) {
  _overrideSqlite3Loader();
  final commands = ReceivePort();
  final readyPort = boot['readyPort']! as SendPort;
  final Database db;
  try {
    db = sqlite3.open(boot['path']! as String)
    ..select('PRAGMA busy_timeout = 5000')
    ..select('PRAGMA journal_mode = WAL')
    ..select('PRAGMA foreign_keys = ON');
  } catch (e) {
    readyPort.send({'ok': false, 'error': e.toString()});
    commands.close();
    return;
  }
  readyPort.send({'ok': true, 'port': commands.sendPort});

  serveWorkerCommands(
    commands,
    boot,
    codeOf: (e) => e is SqliteException ? e.extendedResultCode : null,
    dispatch: (msg) => _sqliteExecuteOp(db, msg),
  );
}

/// 执行单个命令操作。
Object? _sqliteExecuteOp(Database db, Map<Object?, Object?> msg) {
  final sql = msg['sql'] as String?;
  final params = (msg['params'] as List?)?.cast<Object?>() ?? const [];
  switch (msg['op']! as String) {
    case 'ping':
      db.select('SELECT 1');
      return null;
    case 'query':
      return _toDbResult(db.select(sql!, params));
    case 'execute':
      final stmt = db.prepare(sql!);
      try {
        stmt.execute(params);
        // 工作区串行执行，db.updatedRows 即本条语句的受影响行数。
        return db.updatedRows;
      } finally {
        stmt.dispose();
      }
    case 'executeDirect':
      db.execute(sql!);
      return null;
    case 'close':
      db.dispose();
      return null;
    default:
      throw StateError('未知操作 ${msg['op']}');
  }
}

/// 所有列统一转字符串，与达梦网关的结果契约保持一致。
DbResult _toDbResult(ResultSet rs) => DbResult(
  rs.columnNames,
  rs.rows.map((row) => row.map((v) => v?.toString()).toList()).toList(),
);

/// 解析 sqlite3 原生库位置（仅 Windows 需要干预，其余平台走 sqlite3 包
/// 默认加载逻辑）。优先级：
/// `AICMHCS_SQLITE3_DLL` 环境变量 → 可执行文件同目录 sqlite3.dll
/// → Windows 系统自带 winsqlite3.dll。
///
/// 必须在首次使用 sqlite3 前调用；静态状态不跨隔离区共享，因此在工作区
/// 入口处执行。
void _overrideSqlite3Loader() {
  if (!Platform.isWindows) return;
  open.overrideFor(OperatingSystem.windows, () {
    final configured = Platform.environment['AICMHCS_SQLITE3_DLL'];
    if (configured != null && configured.isNotEmpty) {
      return DynamicLibrary.open(configured);
    }
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final besideExe = '$exeDir${Platform.pathSeparator}sqlite3.dll';
    try {
      return DynamicLibrary.open(besideExe);
    } catch (_) {
      // exe 同目录没有随包分发的 dll 时回退系统库。
    }
    return DynamicLibrary.open('winsqlite3.dll');
  });
}
