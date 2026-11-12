import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 口令工具类：登录口令的加盐散列（生成 / 校验，仅服务端持有），
/// 由 AuthService / UserService / 演示数据脚本共用；等保三级复杂度
/// 校验与前端共享，见 common 包的 PasswordPolicy。
final class PasswordHelper {
  PasswordHelper._();

  /// 口令散列算法：sha256(salt + password) 的十六进制。
  /// 库中存储格式：`salt:hash`（salt 为 16 字节随机数的十六进制）。
  static String hashPassword(String saltHex, String password) => sha256.convert(utf8.encode('$saltHex$password')).toString();

  /// 生成随机盐（16 字节的十六进制）。
  static String makeSalt() => _randomHex(16);

  /// 生成存储口令：salt + hash，库中存储格式为 `salt:hash`。
  static String makeStoredPassword(String password) {
    final salt = makeSalt();
    return '$salt:${hashPassword(salt, password)}';
  }

  /// 校验存储口令：salt + hash，库中存储格式为 `salt:hash`。
  static bool verifyStoredPassword(String stored, String password) {
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    return _fixedTimeEquals(
      utf8.encode(hashPassword(parts[0], password)),
      utf8.encode(parts[1]),
    );
  }

  /// 生成 byteCount 字节随机数的十六进制（小写，每字节补齐两位）。
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
