import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 报文加解密失败异常（信封格式非法或 GCM 认证未通过）。
final class SecurePayloadException implements Exception {
  const SecurePayloadException(this.message);

  final String message;

  @override
  String toString() => 'SecurePayloadException: $message';
}

/// API 报文透明加解密（前后端共享，AES-256-GCM）。
///
/// 信封格式：`{"payload": "<base64(nonce[12] + 密文 + 认证标签[16])>"}`，
/// 解开后是原始 JSON 对象。会话密钥由登录接口随 token 一起下发（base64 的
/// 32 字节随机数），与 token 同生命周期；nonce 每次报文随机生成。
final class SecurePayload {
  SecurePayload._();

  static final _algorithm = AesGcm.with256bits();

  /// AES-GCM 的 nonce 与认证标签长度（字节；GCM 规范固定 12/16，
  /// cryptography 包的 AesGcm 未暴露 macLength，故在此显式声明）。
  static const _nonceLength = 12;
  static const _macLength = 16;

  /// 生成随机会话密钥（base64 的 32 字节，恰好供 AES-256 使用）。
  static String generateSessionKey() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    return base64Encode(bytes);
  }

  /// 加密 JSON 对象为信封。
  ///param keyBase64: base64 会话密钥
  ///param plain: 明文 JSON 对象
  ///returns: 信封对象，jsonEncode 后即可作为 HTTP 报文体
  static Future<Map<String, dynamic>> seal(String keyBase64, Map<String, dynamic> plain) async {
    final secretBox = await _algorithm.encrypt(utf8.encode(jsonEncode(plain)), secretKey: SecretKey(base64Decode(keyBase64)));
    return {'payload': base64Encode(secretBox.concatenation())};
  }

  /// 解开信封还原明文 JSON 对象。
  ///param keyBase64: base64 会话密钥
  ///param envelope: 信封对象（须含 String 型 payload 字段）
  ///returns: 明文 JSON 对象
  ///throws SecurePayloadException: 信封格式非法或解密（GCM 认证）失败
  static Future<Map<String, dynamic>> open(String keyBase64, Map<String, dynamic> envelope) async {
    final payload = envelope['payload'];
    if (payload is! String || payload.isEmpty) {
      throw const SecurePayloadException('报文不是合法的加密信封');
    }
    final Uint8List combined;
    try {
      combined = base64Decode(payload);
    } on FormatException {
      throw const SecurePayloadException('报文密文不是合法的 base64');
    }
    if (combined.length < _nonceLength + _macLength) {
      throw const SecurePayloadException('报文密文长度非法');
    }
    try {
      final secretBox = SecretBox.fromConcatenation(combined, nonceLength: _nonceLength, macLength: _macLength);
      final clear = await _algorithm.decrypt(secretBox, secretKey: SecretKey(base64Decode(keyBase64)));
      final plain = jsonDecode(utf8.decode(clear));
      if (plain is! Map<String, dynamic>) {
        throw const SecurePayloadException('解密后的报文不是 JSON 对象');
      }
      return plain;
    } on SecretBoxAuthenticationError {
      throw const SecurePayloadException('报文完整性校验失败或密钥不匹配');
    } on FormatException {
      throw const SecurePayloadException('解密后的报文不是合法文本');
    }
  }
}
