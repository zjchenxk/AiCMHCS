import 'dart:async';
import 'dart:isolate';

import 'dm_database.dart';

/// 数据库访问网关。
///
/// DPI 是同步 FFI 调用，直接在 HTTP 事件循环里执行会阻塞其他请求，
/// 因此网关把连接放进独立工作隔离区，主隔离区通过消息通信访问。
/// 工作区串行处理请求；查询/探活失败时自动重连并重试一次
/// （DML 不重试，避免重复写入）。
class DmGateway {
  DmGateway._(this._worker, this._replies, this._errors);

  final SendPort _worker;
  final ReceivePort _replies;
  final ReceivePort _errors;
  final _pending = <int, Completer<Object?>>{};
  int _seq = 0;
  bool _closed = false;

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
    if (_cached case final cached? when !cached._closed) return cached;

    final ready = ReceivePort();
    final replies = ReceivePort();
    final errors = ReceivePort();
    final boot = _Boot(
      readyPort: ready.sendPort,
      replyPort: replies.sendPort,
      host: host,
      port: port,
      user: user,
      password: password,
      dmHome: dmHome,
    );

    await Isolate.spawn(_workerMain, boot, onError: errors.sendPort);

    final ack = await ready.first as Map<Object?, Object?>;
    ready.close();
    if (ack['ok'] != true) {
      replies.close();
      errors.close();
      throw StateError('初始化达梦数据库连接失败: ${ack['error']}');
    }

    final gateway = DmGateway._(ack['port'] as SendPort, replies, errors);
    errors.listen(gateway._onWorkerError);
    replies.listen(gateway._onMessage);
    return _cached = gateway;
  }

  Future<DmResult> query(String sql, [List<Object?> params = const []]) async =>
      await _call('query', sql: sql, params: params) as DmResult;

  Future<int> execute(String sql, [List<Object?> params = const []]) async =>
      await _call('execute', sql: sql, params: params) as int;

  Future<void> executeDirect(String sql) async => await _call(
        'executeDirect',
        sql: sql,
      );

  Future<void> ping() async => await _call('ping');

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _call('close', timeout: const Duration(seconds: 5));
    } catch (_) {
      // 关闭阶段的错误忽略。
    }
    _replies.close();
    _errors.close();
    final cached = _cached;
    if (cached == this) _cached = null;
  }

  Future<Object?> _call(
    String op, {
    String? sql,
    List<Object?> params = const [],
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_closed) throw StateError('数据库网关已关闭');
    final id = ++_seq;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _worker.send({
      'id': id,
      'op': op,
      'sql': sql,
      'params': params,
      'replyPort': _replies.sendPort,
    });
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      throw TimeoutException('数据库操作超时（$op）', timeout);
    } finally {
      _pending.remove(id);
    }
  }

  void _onWorkerError(Object? msg) {
    for (final c in List.of(_pending.values)) {
      if (!c.isCompleted) {
        c.completeError(StateError('数据库工作区异常: $msg'));
      }
    }
    _pending.clear();
  }

  void _onMessage(Object? message) {
    final msg = message as Map<Object?, Object?>;
    final completer = _pending[msg['id'] as int];
    if (completer == null || completer.isCompleted) return;
    if (msg['ok'] == true) {
      completer.complete(msg['data']);
    } else {
      completer.completeError(
        DmException(
          msg['code'] as int? ?? -1,
          msg['error'] as String? ?? '未知数据库错误',
        ),
      );
    }
  }
}

final class _Boot {
  const _Boot({
    required this.readyPort,
    required this.replyPort,
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    this.dmHome,
  });

  final SendPort readyPort;
  final SendPort replyPort;
  final String host;
  final int port;
  final String user;
  final String password;
  final String? dmHome;
}

final class _ConnRef {
  _ConnRef(this.con);

  DmConnection con;
}

void _workerMain(_Boot boot) {
  final commands = ReceivePort();
  DmConnection connection;
  try {
    connection = DmConnection.connect(
      host: boot.host,
      port: boot.port,
      user: boot.user,
      password: boot.password,
      dmHome: boot.dmHome,
    );
  } catch (e) {
    boot.readyPort.send({'ok': false, 'error': e.toString()});
    commands.close();
    return;
  }
  boot.readyPort.send({'ok': true, 'port': commands.sendPort});

  final ref = _ConnRef(connection);
  var queue = Future<void>.value();
  commands.listen((message) {
    final msg = message as Map<Object?, Object?>;
    queue = queue.then((_) async {
      try {
        final data = await _executeOp(msg, ref, boot);
        boot.replyPort.send({'id': msg['id'], 'ok': true, 'data': data});
      } catch (e) {
        boot.replyPort.send({
          'id': msg['id'],
          'ok': false,
          'error': e.toString(),
          'code': e is DmException ? e.code : null,
        });
      }
      if (msg['op'] == 'close') commands.close();
    });
  });
}

Future<Object?> _executeOp(Map msg, _ConnRef ref, _Boot boot) async {
  DmConnection reconnect() {
    try {
      ref.con.close();
    } catch (_) {
      // 旧连接可能已断开。
    }
    return ref.con = DmConnection.connect(
      host: boot.host,
      port: boot.port,
      user: boot.user,
      password: boot.password,
      dmHome: boot.dmHome,
    );
  }

  switch (msg['op'] as String) {
    case 'ping':
      try {
        ref.con.ping();
        return null;
      } catch (_) {
        reconnect().ping();
        return null;
      }
    case 'query':
      final sql = msg['sql']! as String;
      final params = (msg['params'] as List).cast<Object?>();
      try {
        return ref.con.query(sql, params);
      } catch (_) {
        return reconnect().query(sql, params);
      }
    case 'execute':
      final sql = msg['sql']! as String;
      final params = (msg['params'] as List).cast<Object?>();
      return ref.con.execute(sql, params);
    case 'executeDirect':
      ref.con.executeDirect(msg['sql']! as String);
      return null;
    case 'close':
      ref.con.close();
      return null;
    default:
      throw StateError('未知操作 ${msg['op']}');
  }
}
