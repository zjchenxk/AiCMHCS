import 'dart:async';
import 'dart:isolate';

import 'package:server/db/database_gateway.dart';

/// 基于「独立工作隔离区 + 消息通信」的网关基类。
///
/// 原生数据库调用（FFI）是同步阻塞的，直接在 HTTP 事件循环里执行会卡住
/// 其他请求，因此网关把连接放进独立隔离区串行执行，主隔离区通过消息
/// 通信访问。子类提供工作区入口函数、异常还原方式与参数改写钩子。
abstract class WorkerGateway implements DatabaseGateway {
  WorkerGateway(SendPort worker, ReceivePort replies, ReceivePort errors)
    : _worker = worker,
      _replies = replies,
      _errors = errors {
    _errors.listen(_onWorkerError);
    _replies.listen(_onMessage);
  }

  final SendPort _worker;
  final ReceivePort _replies;
  final ReceivePort _errors;
  final _pending = <int, Completer<Object?>>{};
  int _seq = 0;
  bool _closed = false;

  /// 网关是否已关闭。
  bool get isClosed => _closed;

  /// 把工作区回报的错误还原为具体的数据库异常。
  Exception deserializeError(int? code, String message);

  /// 语句与参数在发往工作区前的改写钩子，默认原样返回。
  ///
  /// 达梦实现用它把含非 ASCII 的参数内联为 SQL 字面量（DPI 绑定参数
  /// 仅支持 ASCII），其余实现无需覆盖。
  (String, List<Object?>) rewrite(String sql, List<Object?> params) =>
      (sql, params);

  /// 网关完全关闭后的回调（子类用于清理静态缓存）。
  void onClosed() {}

  @override
  Future<DbResult> query(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final (rewritten, bound) = rewrite(sql, params);
    return (await invoke('query', sql: rewritten, params: bound))! as DbResult;
  }

  @override
  Future<int> execute(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final (rewritten, bound) = rewrite(sql, params);
    return (await invoke('execute', sql: rewritten, params: bound))! as int;
  }

  @override
  Future<void> executeDirect(String sql) async =>
      invoke('executeDirect', sql: sql);

  @override
  Future<void> ping() async => invoke('ping');

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await invoke('close', timeout: const Duration(seconds: 5));
    } catch (_) {
      // 关闭阶段的错误忽略。
    }
    _replies.close();
    _errors.close();
    onClosed();
  }

  /// 调用工作区操作并等待结果，默认 30 秒超时。
  Future<Object?> invoke(
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
    final msg = message! as Map<Object?, Object?>;
    final completer = _pending[msg['id']! as int];
    if (completer == null || completer.isCompleted) return;
    if (msg['ok'] == true) {
      completer.complete(msg['data']);
    } else {
      completer.completeError(
        deserializeError(
          msg['code'] as int?,
          msg['error'] as String? ?? '未知数据库错误',
        ),
      );
    }
  }

  /// 启动工作隔离区并完成握手，返回由 [build] 构造的网关实例。
  ///
  /// 握手约定：[entry] 完成初始化后向 boot 中的 `readyPort` 发送
  /// `{'ok': true, 'port': 命令端口}`，失败发送 `{'ok': false, 'error': ...}`。
  /// 基类会向 [boot] 追加 `readyPort` / `replyPort` 后传入工作区。
  static Future<W> spawn<W extends WorkerGateway>({
    required void Function(Map<Object?, Object?> boot) entry,
    required Map<Object?, Object?> boot,
    required W Function(
      SendPort worker,
      ReceivePort replies,
      ReceivePort errors,
    )
    build,
  }) async {
    final ready = ReceivePort();
    final replies = ReceivePort();
    final errors = ReceivePort();
    final fullBoot = {
      ...boot,
      'readyPort': ready.sendPort,
      'replyPort': replies.sendPort,
    };
    try {
      await Isolate.spawn(entry, fullBoot, onError: errors.sendPort);
      final ack = await ready.first as Map<Object?, Object?>;
      ready.close();
      if (ack['ok'] != true) {
        throw StateError('数据库工作区初始化失败: ${ack['error']}');
      }
      return build(ack['port']! as SendPort, replies, errors);
    } catch (_) {
      ready.close();
      replies.close();
      errors.close();
      rethrow;
    }
  }
}

/// 工作区命令循环：串行执行 [dispatch]，把结果回传给主隔离区；
/// 收到 close 操作后停止监听、隔离区自然退出。
///
/// 各网关的工作区入口在握手完成后调用本函数即可获得统一的命令处理。
void serveWorkerCommands(
  ReceivePort commands,
  Map<Object?, Object?> boot, {
  required FutureOr<Object?> Function(Map<Object?, Object?> msg) dispatch,
  int? Function(Object error)? codeOf,
}) {
  final replyPort = boot['replyPort']! as SendPort;
  var queue = Future<void>.value();
  commands.listen((message) {
    final msg = message as Map<Object?, Object?>;
    queue = queue.then((_) async {
      try {
        final data = await dispatch(msg);
        replyPort.send({'id': msg['id'], 'ok': true, 'data': data});
      } catch (e) {
        replyPort.send({
          'id': msg['id'],
          'ok': false,
          'error': e.toString(),
          'code': codeOf?.call(e),
        });
      }
      if (msg['op'] == 'close') commands.close();
    });
  });
}
