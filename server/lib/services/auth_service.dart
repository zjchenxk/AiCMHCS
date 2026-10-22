import 'dart:convert';
import 'dart:math';

import 'package:common/model.dart';
import 'package:common/utils/security_util.dart';
import 'package:crypto/crypto.dart';

import 'package:server/db/database_gateway.dart';

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
  LoginSession(this.token, this.sessionKey, this.user, this.expiresAt);

  final String token;
  final String sessionKey; //会话加密密钥（base64 的 32 字节随机数，随登录下发，与 token 同生命周期）
  final LoginUser user;
  DateTime expiresAt;
}

/// 从数据库行解析登录用户（DbResult 各列均以字符串返回，数值按需转换）。
LoginUser _loginUserFromRow(Map<String, String?> row) => LoginUser(
  id: int.parse(row['ID'] ?? '0'),
  userCode: row['USER_CODE'] ?? '',
  userName: row['USER_NAME'] ?? '',
  roleCode: row['ROLE_CODE'] ?? '',
  phone: row['PHONE'],
  lastLoginAt: row['LAST_LOGIN_AT'],
);

/// 登录认证服务：口令校验（盐 + SHA-256）、令牌签发与校验、登录审计。
/// 经 DatabaseGateway 访问数据库，达梦与 SQLite 通用（含中文的参数由
/// 达梦网关自动内联，业务层直接写参数化 SQL）。
class AuthService {
  AuthService(this._db, {this.sessionTtl = const Duration(hours: 2)});

  final DatabaseGateway _db;
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

    LoginUser? user;
    var stored = '';
    String? status;
    if (result.rows.isNotEmpty) {
      final row = result.rowsAsMaps.first;
      stored = row['PASSWORD'] ?? '';
      status = row['STATUS'];
      if (verifyStoredPassword(stored, password)) {
        user = _loginUserFromRow(row);
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
      'UPDATE SYS_USER SET LAST_LOGIN_AT = ? WHERE ID = ?',
      [formatTimestamp(DateTime.now()), user.id],
    );
    await _logLogin(user.id, uCode, ip, 'SUCCESS', null);

    _pruneExpired();
    final token = _randomHex(32);
    final session = LoginSession(
      token,
      SecurePayload.generateSessionKey(),
      user,
      DateTime.now().add(sessionTtl),
    );
    _sessions[token] = session;
    return session;
  }

  /// 校验令牌并滑动续期，返回完整会话（含会话加密密钥）。
  Future<LoginSession> verifySession(String token) async {
    _pruneExpired();
    final session = _sessions[token];
    if (session == null) {
      throw const AuthException(401, 40102, '登录已过期，请重新登录');
    }
    session.expiresAt = DateTime.now().add(sessionTtl);
    return session;
  }

  /// 校验令牌并滑动续期。
  Future<LoginUser> verify(String token) async =>
      (await verifySession(token)).user;

  void logout(String token) => _sessions.remove(token);

  /// 写登录审计（含中文的失败原因经参数传入，由达梦网关自动内联；
  /// 登录时间由 Dart 侧生成后绑定，见 formatTimestamp）。
  Future<void> _logLogin(
    int? userId,
    String userCode,
    String? ip,
    String result,
    String? failReason,
  ) async {
    try {
      await _db.execute(
        'INSERT INTO SYS_LOGIN_LOG '
        '(USER_ID, USER_CODE, LOGIN_IP, LOGIN_TIME, LOGIN_RESULT, '
        'FAIL_REASON) VALUES (?, ?, ?, ?, ?, ?)',
        [
          userId,
          userCode,
          ip,
          formatTimestamp(DateTime.now()),
          result,
          failReason,
        ],
      );
    } catch (_) {
      // 审计写入失败不阻断登录流程。
    }
  }

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
