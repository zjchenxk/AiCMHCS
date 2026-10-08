import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// 达梦 DPI（DM Programming Interface）的 Dart FFI 绑定。
///
/// 绑定依据本机 DM8 安装目录中的头文件：
///   C:\dmdbms\drivers\dpi\include\DPI.h / DPItypes.h / DPIucode.h
/// 句柄（dhenv/dhcon/dhstmt）均为 void*；DM8 64 位构建下
/// slength=8 字节有符号整数，ulength=8 字节无符号整数。
///
/// 字符集策略：执行语句、取列名、取数据、错误消息一律使用 W 系列
/// （UTF-16）函数，DPI 自动完成与服务器字符集（GB18030）的双向转码。
final class Dpi {
  Dpi._(this.lib);

  final DynamicLibrary lib;

  static Dpi? _instance;

  /// 常量定义见 DPI.h。
  static const int dsqlSuccess = 0;
  static const int dsqlSuccessWithInfo = 1;
  static const int dsqlNoData = 100;
  static const int dsqlNullData = -1;
  static const int dsqlHandleEnv = 1;
  static const int dsqlHandleDbc = 2;
  static const int dsqlHandleStmt = 3;
  static const int dsqlCChar = 1003; // C 字符串缓冲（长度见指示器）
  static const int dsqlCWChar = 1001; // 宽字符（UTF-16）缓冲，配套 W 系列
  static const int dsqlParamInput = 1;
  static const int dsqlChar = 1;
  static const int dsqlVarchar = 2;

  /// 加载 dmdpi.dll。
  ///
  /// Windows 按绝对路径加载 DLL 时不会在其所在目录解析依赖
  /// （disql.exe 能运行是因为 exe 本身就在 dmdbms\bin），而 dmdpi 的
  /// 依赖链（dmcomm → libcrypto-3-x64 等）分散在驱动目录与其
  /// dependencies 子目录中。这里收集候选 DLL 后做多轮加载直到
  /// 不动点：无外部依赖的先成功，其余随依赖就绪逐层解开。
  static Dpi open({String? dmHome}) {
    if (_instance != null) return _instance!;

    // 1) 若安装程序已把 dmdbms\bin 加入 PATH，直接加载即可。
    try {
      return _instance = Dpi._(DynamicLibrary.open('dmdpi.dll'));
    } catch (_) {
      // 继续尝试已知的安装位置。
    }

    final candidates = <String>[
      if (dmHome != null && dmHome.isNotEmpty) dmHome,
      if (Platform.environment['DM_HOME'] case final home?) home,
      r'C:\dmdbms',
    ];

    for (final home in candidates) {
      final files = <File>[];
      final seen = <String>{};
      for (final dir in [
        Directory('$home\\bin\\dependencies'),
        Directory('$home\\drivers\\dpi\\dependencies'),
        Directory('$home\\drivers\\dpi'),
      ]) {
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last.toLowerCase();
          if (!name.endsWith('.dll') || !seen.add(name)) continue;
          files.add(entity);
        }
      }
      if (files.isEmpty) continue;

      final loaded = <String>{};
      var pending = files;
      while (pending.isNotEmpty) {
        var progress = false;
        final next = <File>[];
        for (final file in pending) {
          final name = file.uri.pathSegments.last.toLowerCase();
          if (loaded.contains(name)) continue;
          try {
            DynamicLibrary.open(file.path);
            loaded.add(name);
            progress = true;
          } catch (_) {
            next.add(file);
          }
        }
        if (!progress) break;
        pending = next;
      }

      for (final dir in [
        Directory('$home\\drivers\\dpi'),
        Directory('$home\\bin'),
      ]) {
        try {
          return _instance = Dpi._(
            DynamicLibrary.open('${dir.path}\\dmdpi.dll'),
          );
        } catch (_) {
          // 换下一个候选目录。
        }
      }
    }

    throw StateError(
      '无法加载达梦 DPI 驱动 dmdpi.dll。请确认本机已安装 DM8，'
      '或通过环境变量 DM_HOME 指向达梦安装目录（例如 C:\\dmdbms）。',
    );
  }

  // ---- 函数绑定（native 签名严格对应 DPI.h 声明）----

  late final int Function(Pointer<Pointer<Void>>) _allocEnv = lib
      .lookupFunction<Int16 Function(Pointer<Pointer<Void>>),
          int Function(Pointer<Pointer<Void>>)>('dpi_alloc_env');

  late final int Function(Pointer<Void>, Pointer<Pointer<Void>>) _allocCon = lib
      .lookupFunction<
          Int16 Function(Pointer<Void>, Pointer<Pointer<Void>>),
          int Function(Pointer<Void>, Pointer<Pointer<Void>>)>('dpi_alloc_con');

  late final int Function(Pointer<Void>, Pointer<Pointer<Void>>) _allocStmt =
      lib
          .lookupFunction<
              Int16 Function(Pointer<Void>, Pointer<Pointer<Void>>),
              int Function(
                Pointer<Void>,
                Pointer<Pointer<Void>>,
              )>('dpi_alloc_stmt');

  late final int Function(Pointer<Void>) _freeEnv = lib.lookupFunction<
      Int16 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('dpi_free_env');

  late final int Function(Pointer<Void>) _freeCon = lib.lookupFunction<
      Int16 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('dpi_free_con');

  late final int Function(Pointer<Void>) _freeStmt = lib.lookupFunction<
      Int16 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('dpi_free_stmt');

  late final int Function(Pointer<Void>) _closeCursor = lib.lookupFunction<
      Int16 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('dpi_close_cursor');

  late final int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
      Pointer<Uint8>) _login = lib.lookupFunction<
      Int16 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Uint8>)>('dpi_login');

  late final int Function(Pointer<Void>) _logout = lib.lookupFunction<
      Int16 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('dpi_logout');

  late final int Function(Pointer<Void>) _commit = lib.lookupFunction<
      Int16 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('dpi_commit');

  late final int Function(Pointer<Void>) _rollback = lib.lookupFunction<
      Int16 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('dpi_rollback');

  late final int Function(Pointer<Void>, Pointer<Uint8>) _execDirect = lib
      .lookupFunction<Int16 Function(Pointer<Void>, Pointer<Uint8>),
          int Function(Pointer<Void>, Pointer<Uint8>)>('dpi_exec_direct');

  late final int Function(Pointer<Void>, Pointer<Uint8>, int) _execDirectW = lib
      .lookupFunction<Int16 Function(Pointer<Void>, Pointer<Uint8>, Int32),
          int Function(Pointer<Void>, Pointer<Uint8>, int)>('dpi_exec_directW');

  late final int Function(Pointer<Void>, Pointer<Uint8>, int) _prepareW = lib
      .lookupFunction<Int16 Function(Pointer<Void>, Pointer<Uint8>, Int32),
          int Function(Pointer<Void>, Pointer<Uint8>, int)>('dpi_prepareW');

  late final int Function(
      Pointer<Void>,
      int,
      int,
      int,
      int,
      int,
      int,
      Pointer<Void>,
      int,
      Pointer<Int64>) _bindParam = lib.lookupFunction<
      Int16 Function(Pointer<Void>, Uint16, Int16, Int16, Int16, Uint64, Int16,
          Pointer<Void>, Int64, Pointer<Int64>),
      int Function(Pointer<Void>, int, int, int, int, int, int, Pointer<Void>,
          int, Pointer<Int64>)>('dpi_bind_param');

  late final int Function(Pointer<Void>) _exec = lib.lookupFunction<
      Int16 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('dpi_exec');

  late final int Function(Pointer<Void>, Pointer<Int16>) _numberColumns = lib
      .lookupFunction<Int16 Function(Pointer<Void>, Pointer<Int16>),
          int Function(Pointer<Void>, Pointer<Int16>)>('dpi_number_columns');

  late final int Function(Pointer<Void>, Pointer<Int64>) _rowCount = lib
      .lookupFunction<Int16 Function(Pointer<Void>, Pointer<Int64>),
          int Function(Pointer<Void>, Pointer<Int64>)>('dpi_row_count');

  late final int Function(
      Pointer<Void>,
      int,
      Pointer<Uint16>,
      int,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Uint64>,
      Pointer<Int16>,
      Pointer<Int16>) _descColumnW = lib.lookupFunction<
      Int16 Function(Pointer<Void>, Int16, Pointer<Uint16>, Int16,
          Pointer<Int16>, Pointer<Int16>, Pointer<Uint64>, Pointer<Int16>,
          Pointer<Int16>),
      int Function(
          Pointer<Void>,
          int,
          Pointer<Uint16>,
          int,
          Pointer<Int16>,
          Pointer<Int16>,
          Pointer<Uint64>,
          Pointer<Int16>,
          Pointer<Int16>)>('dpi_desc_columnW');

  late final int Function(Pointer<Void>, Pointer<Uint64>) _fetch = lib
      .lookupFunction<Int16 Function(Pointer<Void>, Pointer<Uint64>),
          int Function(Pointer<Void>, Pointer<Uint64>)>('dpi_fetch');

  late final int Function(Pointer<Void>, int, int, Pointer<Void>, int,
      Pointer<Int64>) _getDataW = lib.lookupFunction<
      Int16 Function(
          Pointer<Void>, Uint16, Int16, Pointer<Void>, Int64, Pointer<Int64>),
      int Function(
          Pointer<Void>, int, int, Pointer<Void>, int, Pointer<Int64>)>(
    'dpi_get_dataW',
  );

  late final int Function(int, Pointer<Void>, int, Pointer<Int32>,
      Pointer<Uint8>, int, Pointer<Int16>) _getDiagRecW = lib.lookupFunction<
      Int16 Function(Int16, Pointer<Void>, Int16, Pointer<Int32>,
          Pointer<Uint8>, Int16, Pointer<Int16>),
      int Function(int, Pointer<Void>, int, Pointer<Int32>, Pointer<Uint8>, int,
          Pointer<Int16>)>('dpi_get_diag_recW');

  // ---- 便捷封装 ----

  int allocEnv(Pointer<Pointer<Void>> henv) => _allocEnv(henv);
  int allocCon(Pointer<Void> henv, Pointer<Pointer<Void>> hcon) =>
      _allocCon(henv, hcon);
  int allocStmt(Pointer<Void> hcon, Pointer<Pointer<Void>> hstmt) =>
      _allocStmt(hcon, hstmt);
  int freeEnv(Pointer<Void> henv) => _freeEnv(henv);
  int freeCon(Pointer<Void> hcon) => _freeCon(hcon);
  int freeStmt(Pointer<Void> hstmt) => _freeStmt(hstmt);
  int closeCursor(Pointer<Void> hstmt) => _closeCursor(hstmt);

  int login(Pointer<Void> hcon, String server, String user, String password) {
    final svr = server.toNativeUtf8();
    final usr = user.toNativeUtf8();
    final pwd = password.toNativeUtf8();
    final r = _login(hcon, svr.cast(), usr.cast(), pwd.cast());
    calloc.free(svr);
    calloc.free(usr);
    calloc.free(pwd);
    return r;
  }

  int logout(Pointer<Void> hcon) => _logout(hcon);
  int commit(Pointer<Void> hcon) => _commit(hcon);
  int rollback(Pointer<Void> hcon) => _rollback(hcon);

  /// 非 W 路径执行（本地码页，仅用于 ASCII 语句）。
  int execDirect(Pointer<Void> hstmt, String sql) {
    final buf = _native(sql);
    final r = _execDirect(hstmt, buf);
    calloc.free(buf);
    return r;
  }

  /// W 路径执行：SQL 转为 UTF-16，sqllen 为字节数。
  int execDirectW(Pointer<Void> hstmt, String sql) {
    final buf = nativeW(sql);
    try {
      return _execDirectW(hstmt, buf.cast(), sql.length * 2);
    } finally {
      calloc.free(buf);
    }
  }

  /// W 路径预处理：SQL 转为 UTF-16，sqllen 为字节数。
  int prepareW(Pointer<Void> hstmt, String sql) {
    final buf = nativeW(sql);
    try {
      return _prepareW(hstmt, buf.cast(), sql.length * 2);
    } finally {
      calloc.free(buf);
    }
  }

  int bindParam(
    Pointer<Void> hstmt,
    int paramIndex, // 1-based
    int paramType,
    int cType,
    int dType,
    int precision,
    int scale,
    Pointer<Void> buf,
    int bufLen,
    Pointer<Int64> ind,
  ) =>
      _bindParam(hstmt, paramIndex, paramType, cType, dType, precision, scale,
          buf, bufLen, ind);

  int exec(Pointer<Void> hstmt) => _exec(hstmt);
  int numberColumns(Pointer<Void> hstmt, Pointer<Int16> colCount) =>
      _numberColumns(hstmt, colCount);
  int rowCount(Pointer<Void> hstmt, Pointer<Int64> rowCount) =>
      _rowCount(hstmt, rowCount);

  int descColumnW(
    Pointer<Void> hstmt,
    int colIndex, // 1-based
    Pointer<Uint16> name,
    int nameBufBytes,
    Pointer<Int16> nameLen,
    Pointer<Int16> sqlType,
    Pointer<Uint64> colSize,
    Pointer<Int16> decimalDigits,
    Pointer<Int16> nullable,
  ) =>
      _descColumnW(hstmt, colIndex, name, nameBufBytes, nameLen, sqlType,
          colSize, decimalDigits, nullable);

  int fetch(Pointer<Void> hstmt, Pointer<Uint64> rowNum) =>
      _fetch(hstmt, rowNum);

  int getDataW(
    Pointer<Void> hstmt,
    int colIndex,
    int cType,
    Pointer<Void> buf,
    int bufBytes,
    Pointer<Int64> valLen,
  ) =>
      _getDataW(hstmt, colIndex, cType, buf, bufBytes, valLen);

  /// 读取句柄上的诊断记录（UTF-16 错误消息，避免本地码页乱码）。
  String diagW(int handleType, Pointer<Void> handle) {
    final code = calloc<Int32>();
    final msg = calloc<Uint16>(1024);
    final msgLen = calloc<Int16>();
    try {
      final r =
          _getDiagRecW(handleType, handle, 1, code, msg.cast(), 2048, msgLen);
      if (r == dsqlSuccess || r == dsqlSuccessWithInfo) {
        final text = String.fromCharCodes(msg.asTypedList(msgLen.value ~/ 2));
        return '[dm-${code.value}] $text';
      }
      return '[dm-?] 未知错误（诊断码 $r）';
    } finally {
      calloc.free(code);
      calloc.free(msg);
      calloc.free(msgLen);
    }
  }

  static Pointer<Uint8> _native(String s) {
    final units = utf8.encode(s);
    final buf = calloc<Uint8>(units.length + 1);
    buf.asTypedList(units.length).setAll(0, units);
    return buf;
  }

  /// 分配 UTF-16 缓冲（Windows 原生小端字节序，即 codeUnits 的内存布局）。
  static Pointer<Uint16> nativeW(String s) {
    final units = s.codeUnits;
    final buf = calloc<Uint16>(units.length);
    buf.asTypedList(units.length).setAll(0, units);
    return buf;
  }
}
