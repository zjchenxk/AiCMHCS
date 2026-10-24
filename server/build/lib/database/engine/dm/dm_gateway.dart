import 'dart:isolate';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/database/engine/dm/dm_database.dart';
import 'package:server/database/engine/dm/dm_param_rewrite.dart';
import 'package:server/database/engine/worker_gateway.dart';

/// 达梦数据库网关。
///
/// 查询/探活失败时自动重连并重试一次（DML 不重试，避免重复写入）。
/// 含非 ASCII 的参数在发往工作区前由 [rewrite] 改写为 SQL 字面量内联
/// （DPI 绑定参数仅支持 ASCII），业务代码直接写参数化 SQL 即可。
class DmGateway extends WorkerGateway {
  DmGateway._(super.worker, super.replies, super.errors);

  static DmGateway? _cached;

  /// 启动（或复用）网关。dart_frog dev 热重载会重新执行 main 入口，
  /// 缓存保证不会泄漏出多个工作隔离区。
  static Future<DmGateway> start({
    required String host,
    required int port,
    required String user,
    required String password,
    String? dmHome,
  }) async {
    if (_cached case final cached? when !cached.isClosed) return cached;
    final gateway = await WorkerGateway.spawn(
      entry: _dmWorkerMain,
      boot: {
        'host': host,
        'port': port,
        'user': user,
        'password': password,
        if (dmHome != null) 'dmHome': dmHome,
      },
      build: DmGateway._,
    );
    return _cached = gateway;
  }

  @override
  DbDialect get dialect => DbDialect.dm;

  @override
  (String, List<Object?>) rewrite(String sql, List<Object?> params) => rewriteDmParams(sql, params);

  @override
  Exception deserializeError(int? code, String message) => DmException(code ?? -1, message);

  @override
  void onClosed() {
    if (identical(_cached, this)) _cached = null;
  }
}

final class _ConnRef {
  _ConnRef(this.con);

  DmConnection con;
}

/// 工作区入口：建立连接并进入命令循环。
void _dmWorkerMain(Map<Object?, Object?> boot) {
  final commands = ReceivePort();
  final readyPort = boot['readyPort']! as SendPort;
  final DmConnection connection;
  try {
    connection = _connect(boot);
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
    codeOf: (e) => e is DmException ? e.code : null,
    dispatch: (msg) => _dmExecuteOp(msg, ref, boot),
  );
}

DmConnection _connect(Map<Object?, Object?> boot) => DmConnection.connect(
  host: boot['host']! as String,
  port: boot['port']! as int,
  user: boot['user']! as String,
  password: boot['password']! as String,
  dmHome: boot['dmHome'] as String?,
);

/// 执行单个命令操作；查询/探活失败时重连并重试一次，DML 不重试。
Future<Object?> _dmExecuteOp(
  Map<Object?, Object?> msg,
  _ConnRef ref,
  Map<Object?, Object?> boot,
) async {
  DmConnection reconnect() {
    try {
      ref.con.close();
    } catch (_) {
      // 旧连接可能已断开。
    }
    return ref.con = _connect(boot);
  }

  final sql = msg['sql'] as String?;
  final params = (msg['params'] as List?)?.cast<Object?>() ?? const [];
  switch (msg['op']! as String) {
    case 'ping':
      try {
        ref.con.ping();
        return null;
      } catch (_) {
        reconnect().ping();
        return null;
      }
    case 'query':
      try {
        return ref.con.query(sql!, params);
      } catch (_) {
        return reconnect().query(sql!, params);
      }
    case 'execute':
      return ref.con.execute(sql!, params);
    case 'executeDirect':
      ref.con.executeDirect(sql!);
      return null;
    case 'close':
      ref.con.close();
      return null;
    default:
      throw StateError('未知操作 ${msg['op']}');
  }
}
