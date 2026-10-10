import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../dm/dm_gateway.dart';
import '../models/user_info.dart';

/// 认证类业务异常：httpStatus / code / message 直接映射到 HTTP 响应。
final class AuthException implements Exception {
  const AuthException(this.httpStatus, this.code, this.message);

  final int httpStatus;
  final int code;
  final String message;

  @override
  String toString() => 'AuthException($httpStatus, $code): $message';
}

/// 登录会话（内存版；重启后失效，生产环境应落库或改用 Redis）。
final class LoginSession {
  LoginSession(this.token, this.user, this.expiresAt);

  final String token;
  final UserInfo user;
  DateTime expiresAt;
}

/// 登录认证服务：口令校验（盐 + SHA-256）、令牌签发与校验、登录审计。
class AuthService {
  AuthService(this._db, {this.sessionTtl = const Duration(hours: 2)});

  final DmGateway _db;
  final Duration sessionTtl;

  final _sessions = <String, LoginSession>{};

  /// 口令散列算法：sha256(salt + password) 的十六进制。
  /// 库中存储格式：`salt:hash`（salt 为 16 字节随机数的十六进制）。
  static String hashPassword(String saltHex, String password) =>
      sha256.convert(utf8.encode('$saltHex$password')).toString();

  static String makeSalt() => _randomHex(16);

  static String makeStoredPassword(String password) {
    final salt = makeSalt();
    return '$salt:${hashPassword(salt, password)}';
  }

  static bool verifyStoredPassword(String stored, String password) {
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    return _fixedTimeEquals(
      utf8.encode(hashPassword(parts[0], password)),
      utf8.encode(parts[1]),
    );
  }

  /// 登录：校验用户名口令、写审计日志、更新最近登录时间、签发令牌。
  Future<LoginSession> login(
    String userCode,
    String password, {
    String? ip,
  }) async {
    final uCode = userCode.trim();
    if (uCode.isEmpty || password.isEmpty) {
      throw const AuthException(400, 40001, '用户名和密码不能为空');
    }

    final result = await _db.query(
      'SELECT ID, USER_CODE, PASSWORD, USER_NAME, ROLE_CODE, PHONE, STATUS, '
      'LAST_LOGIN_AT FROM SYS_USER WHERE USER_CODE = ?',
      [uCode],
    );

    UserInfo? user;
    String stored = '';
    String? status;
    if (result.rows.isNotEmpty) {
      final row = result.rowsAsMaps.first;
      stored = row['PASSWORD'] ?? '';
      status = row['STATUS'];
      if (verifyStoredPassword(stored, password)) {
        user = UserInfo.fromRow(row);
      }
    }

    // 用户不存在与口令错误统一提示，避免账号枚举。
    if (user == null) {
      await _logLogin(null, uCode, ip, 'FAIL', '用户名或密码错误');
      throw const AuthException(401, 40101, '用户名或密码错误');
    }
    if (status != '1') {
      await _logLogin(user.id, uCode, ip, 'FAIL', '账号已停用');
      throw const AuthException(403, 40301, '账号已被停用，请联系管理员');
    }

    await _db.execute(
      'UPDATE SYS_USER SET LAST_LOGIN_AT = CURRENT_TIMESTAMP WHERE ID = ?',
      [user.id.toString()],
    );
    await _logLogin(user.id, uCode, ip, 'SUCCESS', null);

    _pruneExpired();
    final token = _randomHex(32);
    final session = LoginSession(token, user, DateTime.now().add(sessionTtl));
    _sessions[token] = session;
    return session;
  }

  /// 校验令牌并滑动续期。
  Future<UserInfo> verify(String token) async {
    _pruneExpired();
    final session = _sessions[token];
    if (session == null) {
      throw const AuthException(401, 40102, '登录已过期，请重新登录');
    }
    session.expiresAt = DateTime.now().add(sessionTtl);
    return session.user;
  }

  void logout(String token) => _sessions.remove(token);

  /// 写登录审计。中文原因不能走 bind_param（无宽字符版本，按本地码页
  /// 解释会乱码），改为转义后经 W 路径内联执行。
  Future<void> _logLogin(
    int? userId,
    String userCode,
    String? ip,
    String result,
    String? failReason,
  ) async {
    try {
      final uid = userId?.toString() ?? 'NULL';
      await _db.executeDirect(
        'INSERT INTO SYS_LOGIN_LOG '
        '(USER_ID, USER_CODE, LOGIN_IP, LOGIN_RESULT, FAIL_REASON) '
        'VALUES ($uid, ${_lit(userCode)}, ${_lit(ip)}, '
        '${_lit(result)}, ${_lit(failReason)})',
      );
    } catch (_) {
      // 审计写入失败不阻断登录流程。
    }
  }

  /// SQL 字符串字面量（单引号翻倍转义）。
  static String _lit(String? s) =>
      s == null ? 'NULL' : "'${s.replaceAll("'", "''")}'";

  void _pruneExpired() {
    final now = DateTime.now();
    _sessions.removeWhere((_, s) => s.expiresAt.isBefore(now));
  }

  static String _randomHex(int byteCount) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 常量时间字节比较，避免时序侧信道。
  static bool _fixedTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
