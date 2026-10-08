import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'dpi.dart';

/// 达梦数据库异常，code 为达梦错误码，message 为服务器诊断消息。
final class DmException implements Exception {
  DmException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'DmException $code: $message';
}

/// 查询结果。所有列均以字符串形式取回，数值/时间由调用方按需转换；
/// NULL 用 null 表示。
final class DmResult {
  DmResult(this.columns, this.rows);

  final List<String> columns;
  final List<List<String?>> rows;

  /// 按列名取行的便捷视图。
  List<Map<String, String?>> get rowsAsMaps => rows
      .map((row) => {
            for (var i = 0; i < columns.length && i < row.length; i++)
              columns[i]: row[i],
          })
      .toList(growable: false);
}

/// 单个 DM8 连接。
///
/// 字符集约定：全程使用 DPI 的 W 系列（UTF-16）接口执行语句、读取
/// 列名与数据，DPI 自动完成与服务器字符集（本机为 GB18030）的双向
/// 转码，Dart 侧因此可以始终按 Unicode 处理字符串。
/// 绑定参数（dpi_bind_param 无 W 版本）按本地码页编码，仅支持
/// ASCII 参数值；中文参数需改用 SQL 字面量经 W 路径传入。
///
/// FFI 调用是同步阻塞的，因此本类不直接暴露给请求处理代码，
/// 由 [DmGateway] 放在独立工作隔离区中串行调用。
final class DmConnection {
  DmConnection._(this._dpi, this._henv, this._hcon);

  /// 单列取数缓冲（字节，UTF-16）。
  static const int _colBufBytes = 16 * 1024;

  final Dpi _dpi;
  final Pointer<Void> _henv;
  final Pointer<Void> _hcon;
  bool _closed = false;

  /// 建立 DPI 连接。
  static DmConnection connect({
    required String host,
    required int port,
    required String user,
    required String password,
    String? dmHome,
  }) {
    final dpi = Dpi.open(dmHome: dmHome);

    final henv = calloc<Pointer<Void>>();
    final hcon = calloc<Pointer<Void>>();
    var envAllocated = false;
    var conAllocated = false;
    try {
      final rcEnv = dpi.allocEnv(henv);
      if (rcEnv != Dpi.dsqlSuccess && rcEnv != Dpi.dsqlSuccessWithInfo) {
        throw DmException(rcEnv, '分配 DPI 环境句柄失败（返回码 $rcEnv）');
      }
      envAllocated = true;
      final rcCon = dpi.allocCon(henv.value, hcon);
      if (rcCon != Dpi.dsqlSuccess && rcCon != Dpi.dsqlSuccessWithInfo) {
        throw DmException(rcCon, '分配 DPI 连接句柄失败（返回码 $rcCon）');
      }
      conAllocated = true;

      final rc = dpi.login(hcon.value, '$host:$port', user, password);
      if (rc != Dpi.dsqlSuccess && rc != Dpi.dsqlSuccessWithInfo) {
        final diag = dpi.diagW(Dpi.dsqlHandleDbc, hcon.value);
        throw DmException(rc, '连接达梦数据库失败（$host:$port）: $diag');
      }
      return DmConnection._(dpi, henv.value, hcon.value);
    } catch (_) {
      if (conAllocated) dpi.freeCon(hcon.value);
      if (envAllocated) dpi.freeEnv(henv.value);
      rethrow;
    } finally {
      calloc.free(henv);
      calloc.free(hcon);
    }
  }

  bool get isClosed => _closed;

  void close() {
    if (_closed) return;
    _closed = true;
    _dpi.logout(_hcon);
    _dpi.freeCon(_hcon);
    _dpi.freeEnv(_henv);
  }

  /// 执行 SELECT（? 占位符，参数为字符串或 null），取回全部行。
  DmResult query(String sql, [List<Object?> params = const []]) {
    final stmt = _newStatement();
    try {
      _prepareAndExecute(stmt, sql, params);
      return _fetchAll(stmt);
    } finally {
      _dpi.freeStmt(stmt);
    }
  }

  /// 执行 DML（INSERT/UPDATE/DELETE），返回受影响行数并提交事务。
  int execute(String sql, [List<Object?> params = const []]) {
    final stmt = _newStatement();
    try {
      _prepareAndExecute(stmt, sql, params);
      final affected = calloc<Int64>();
      int count;
      try {
        _check(
          _dpi.rowCount(stmt, affected),
          stmt,
          '获取受影响行数失败',
        );
        count = affected.value;
      } finally {
        calloc.free(affected);
      }
      _check(_dpi.commit(_hcon), null, '提交事务失败');
      return count;
    } catch (_) {
      _dpi.rollback(_hcon);
      rethrow;
    } finally {
      _dpi.freeStmt(stmt);
    }
  }

  /// 执行 DDL / 无占位符语句并提交事务。
  void executeDirect(String sql) {
    final stmt = _newStatement();
    try {
      _execDirectW(stmt, sql);
      _check(_dpi.commit(_hcon), null, '提交事务失败');
    } catch (_) {
      _dpi.rollback(_hcon);
      rethrow;
    } finally {
      _dpi.freeStmt(stmt);
    }
  }

  /// 连接探活。
  void ping() {
    final stmt = _newStatement();
    try {
      _execDirectW(stmt, 'SELECT 1');
      _dpi.closeCursor(stmt);
    } finally {
      _dpi.freeStmt(stmt);
    }
  }

  Pointer<Void> _newStatement() {
    final hstmt = calloc<Pointer<Void>>();
    try {
      _check(
        _dpi.allocStmt(_hcon, hstmt),
        _hcon,
        '分配语句句柄失败',
      );
      return hstmt.value;
    } finally {
      calloc.free(hstmt);
    }
  }

  void _execDirectW(Pointer<Void> stmt, String sql) {
    _check(
      _dpi.execDirectW(stmt, sql),
      stmt,
      '执行语句失败',
    );
  }

  void _prepareAndExecute(
      Pointer<Void> stmt, String sql, List<Object?> params) {
    if (params.isEmpty) {
      _execDirectW(stmt, sql);
      return;
    }

    // 参数缓冲区与指示器必须存活到 exec 返回之后，统一在 finally 释放。
    final buffers = <Pointer<Uint8>>[];
    final indicators = <Pointer<Int64>>[];
    try {
      _check(_dpi.prepareW(stmt, sql), stmt, '预处理语句失败');
      for (var i = 0; i < params.length; i++) {
        final ind = calloc<Int64>();
        indicators.add(ind);
        final value = params[i];
        if (value == null) {
          ind.value = Dpi.dsqlNullData;
          _check(
            _dpi.bindParam(
              stmt,
              i + 1,
              Dpi.dsqlParamInput,
              Dpi.dsqlCChar,
              Dpi.dsqlVarchar,
              0,
              0,
              nullptr.cast(),
              0,
              ind,
            ),
            stmt,
            '绑定参数 ${i + 1} 失败',
          );
          continue;
        }
        final text = value is String ? value : value.toString();
        final bytes = utf8.encode(text);
        final buf = calloc<Uint8>(bytes.length);
        buffers.add(buf);
        buf.asTypedList(bytes.length).setAll(0, bytes);
        ind.value = bytes.length;
        _check(
          _dpi.bindParam(
            stmt,
            i + 1,
            Dpi.dsqlParamInput,
            Dpi.dsqlCChar,
            Dpi.dsqlVarchar,
            bytes.length,
            0,
            buf.cast(),
            bytes.length,
            ind,
          ),
          stmt,
          '绑定参数 ${i + 1} 失败',
        );
      }
      _check(_dpi.exec(stmt), stmt, '执行语句失败');
    } finally {
      for (final b in buffers) {
        calloc.free(b);
      }
      for (final i in indicators) {
        calloc.free(i);
      }
    }
  }

  DmResult _fetchAll(Pointer<Void> stmt) {
    int nCols;
    final colCount = calloc<Int16>();
    try {
      _check(
        _dpi.numberColumns(stmt, colCount),
        stmt,
        '获取列数失败',
      );
      nCols = colCount.value;
    } finally {
      calloc.free(colCount);
    }
    if (nCols <= 0) {
      return DmResult(const [], const []);
    }

    // 列名（UTF-16）。
    final columns = <String>[];
    final nameBuf = calloc<Uint16>(256);
    final nameLen = calloc<Int16>();
    final sqlType = calloc<Int16>();
    final colSize = calloc<Uint64>();
    final decDigits = calloc<Int16>();
    final nullable = calloc<Int16>();
    try {
      for (var i = 1; i <= nCols; i++) {
        _check(
          _dpi.descColumnW(stmt, i, nameBuf, 512, nameLen, sqlType, colSize,
              decDigits, nullable),
          stmt,
          '读取第 $i 列元数据失败',
        );
        final units = nameLen.value ~/ 2;
        columns.add(String.fromCharCodes(
          nameBuf.asTypedList(units < 0 ? 0 : units),
        ));
      }
    } finally {
      calloc.free(nameBuf);
      calloc.free(nameLen);
      calloc.free(sqlType);
      calloc.free(colSize);
      calloc.free(decDigits);
      calloc.free(nullable);
    }

    // 逐行取数：W 路径没有 bind_col 的宽字符版本，用 getDataW 逐列读取。
    final rows = <List<String?>>[];
    final wbuf = calloc<Uint16>(_colBufBytes ~/ 2);
    final ind = calloc<Int64>();
    final rowNum = calloc<Uint64>();
    try {
      while (true) {
        final rc = _dpi.fetch(stmt, rowNum);
        if (rc == Dpi.dsqlNoData) break;
        _check(rc, stmt, '读取数据行失败');
        final row = List<String?>.filled(nCols, null, growable: false);
        for (var i = 1; i <= nCols; i++) {
          final grc = _dpi.getDataW(
            stmt,
            i,
            Dpi.dsqlCWChar,
            wbuf.cast(),
            _colBufBytes,
            ind,
          );
          _check(grc, stmt, '读取第 $i 列数据失败');
          if (ind.value == Dpi.dsqlNullData) {
            row[i - 1] = null;
          } else {
            var units = ind.value ~/ 2;
            if (units < 0) units = 0;
            if (units > _colBufBytes ~/ 2) units = _colBufBytes ~/ 2;
            row[i - 1] = String.fromCharCodes(wbuf.asTypedList(units));
          }
        }
        rows.add(row);
      }
    } finally {
      calloc.free(wbuf);
      calloc.free(ind);
      calloc.free(rowNum);
    }
    return DmResult(columns, rows);
  }

  void _check(int rc, Pointer<Void>? stmt, String what) {
    if (rc == Dpi.dsqlSuccess || rc == Dpi.dsqlSuccessWithInfo) return;
    // 优先语句级诊断；stmt 为空表示连接级操作（提交/回滚）。
    final diag = stmt != null
        ? _dpi.diagW(Dpi.dsqlHandleStmt, stmt)
        : _dpi.diagW(Dpi.dsqlHandleDbc, _hcon);
    throw DmException(rc, '$what: $diag');
  }
}
