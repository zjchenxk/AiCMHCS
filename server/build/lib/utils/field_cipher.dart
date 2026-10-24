import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:common/utils/security_util.dart';
import 'package:cryptography/cryptography.dart';

import 'package:server/app_config.dart';

/// 字段加解密失败异常（密文格式非法、GCM 认证未通过或密钥不匹配）。
final class FieldCipherException implements Exception {
  ///中文描述（不含明文数据）。
  const FieldCipherException(this.message);

  /// 失败原因。
  final String message;

  @override
  String toString() => 'FieldCipherException: $message';
}

/// 字段级存储加密与盲索引（等保：敏感个人信息加密存储，密钥仅在应用侧，
/// DBA 与拖库者均无法还原明文）。
///
/// - 密文格式 `v1:<base64(nonce[12] + 密文 + 认证标签[16])>`，AES-256-GCM
///   随机 nonce，同明文每次密文不同（抗频度分析）；`v1` 为密钥版本号，
///   为将来轮换预留；
/// - 盲索引为 HMAC-SHA256 十六进制（64 字符），写入冗余哈希列供等值
///   查询——手机号等取值空间小，裸哈希可被穷举，带密钥 HMAC 才能防
///   离线枚举；
/// - 子密钥由主密钥经 HKDF-SHA256 按用途（purpose）派生：加密与 MAC
///   分钥、每个字段各自独立，新敏感字段接入时选新 purpose 即可；
/// - 明文统一 trim 后处理，加密与盲索引口径一致，保证查询可命中；
/// - 读兼容：不带 `v<N>:` 前缀的存量值视为迁移残留明文，原样返回。
///
/// 传输层信封加密（SecurePayload）与本文密钥各自独立，互不通用。
class FieldCipher {
  ///私有构造：经 [fromMasterKeyBase64] / [fromConfig] 创建。
  FieldCipher._(this._masterKey);

  /// 从 base64 主密钥构造（32 字节随机数的 base64 文本）。
  factory FieldCipher.fromMasterKeyBase64(String keyBase64) {
    final Uint8List bytes;
    try {
      bytes = base64Decode(keyBase64.trim());
    } on FormatException {
      throw const FieldCipherException('字段加密主密钥不是合法的 base64');
    }
    if (bytes.length != _keyLength) {
      throw const FieldCipherException(
        '字段加密主密钥必须为 32 字节随机数的 base64（44 字符）',
      );
    }
    return FieldCipher._(Uint8List.fromList(bytes));
  }

  /// 按配置解析主密钥：环境变量 `AICMHCS_FIELD_MASTER_KEY` → 密钥文件
  /// （不存在且未设环境变量时自动生成）。密钥写入文件失败直接抛错——
  /// 宁可启动失败，也不能带着重启后即失效的临时密钥写入数据。
  static Future<FieldCipher> fromConfig(AppConfig config) {
    final fromEnv = config.fieldMasterKey?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return Future.value(FieldCipher.fromMasterKeyBase64(fromEnv));
    }
    final file = File(config.fieldKeyFile);
    if (file.existsSync()) {
      return Future.value(
        FieldCipher.fromMasterKeyBase64(file.readAsStringSync()),
      );
    }
    final keyBase64 = SecurePayload.generateSessionKey();
    final cipher = FieldCipher.fromMasterKeyBase64(keyBase64);
    return File(config.fieldKeyFile).parent.create(recursive: true).then((_) => file.writeAsString(keyBase64)).then((_) {
      cipher.keyFileWasGenerated = true;
      return cipher;
    });
  }

  /// 字段用途：SYS_USER.PHONE（联系电话）。
  static const phonePurpose = 'phone';

  /// 是否为本次自动生成的密钥文件（调用方据此提示运维单独备份密钥）。
  bool keyFileWasGenerated = false;

  static const _keyLength = 32;
  static const _version = 1;

  /// AES-GCM 的 nonce 与认证标签长度（字节；GCM 规范固定 12/16，
  /// cryptography 包的 AesGcm 未暴露 macLength，故在此显式声明）。
  static const _nonceLength = 12;
  static const _macLength = 16;

  static final _aesGcm = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: _keyLength);
  static final _versionPattern = RegExp(r'^v(\d+):');

  final Uint8List _masterKey;

  final _encKeys = <String, Future<SecretKeyData>>{};
  final _macKeys = <String, Future<SecretKeyData>>{};

  /// 判断值是否已是本工具产出的密文（幂等回填等场景使用）。
  static bool looksEncrypted(String value) => _versionPattern.hasMatch(value);

  /// 加密字段值（null 透传，输出带版本前缀的密文）。
  Future<String?> seal(String purpose, String? plain) async {
    if (plain == null) return null;
    final box = await _aesGcm.encrypt(
      utf8.encode(plain.trim()),
      secretKey: await _encKeyOf(purpose),
    );
    return 'v$_version:${base64Encode(box.concatenation())}';
  }

  /// 解密字段值：`v<N>:` 前缀按版本解密，不带前缀的视为存量明文原样返回。
  ///
  /// 密钥错误或密文被篡改时 GCM 认证失败，抛 [FieldCipherException]。
  Future<String?> open(String purpose, String? stored) async {
    if (stored == null) return null;
    final match = _versionPattern.firstMatch(stored);
    if (match == null) return stored;
    final version = int.parse(match.group(1)!);
    if (version != _version) {
      throw FieldCipherException(
        '不支持的字段密文版本 v$version（当前 v$_version）',
      );
    }
    final Uint8List combined;
    try {
      combined = base64Decode(stored.substring(match.end));
    } on FormatException {
      throw const FieldCipherException('字段密文不是合法的 base64');
    }
    if (combined.length < _nonceLength + _macLength) {
      throw const FieldCipherException('字段密文长度非法');
    }
    try {
      final box = SecretBox.fromConcatenation(
        combined,
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final clear = await _aesGcm.decrypt(
        box,
        secretKey: await _encKeyOf(purpose),
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const FieldCipherException('字段密文完整性校验失败或密钥不匹配');
    } on FormatException {
      throw const FieldCipherException('解密后的字段值不是合法文本');
    }
  }

  /// 计算盲索引（null 透传；与 [seal] 同口径 trim，保证查询两侧一致）。
  Future<String?> mac(String purpose, String? plain) async {
    if (plain == null) return null;
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(plain.trim()),
      secretKey: await _macKeyOf(purpose),
    );
    return mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<SecretKeyData> _encKeyOf(String purpose) => _encKeys.putIfAbsent(
    purpose,
    () => _hkdf.deriveKey(
      secretKey: SecretKey(_masterKey),
      info: utf8.encode('field-enc:$purpose'),
    ),
  );

  Future<SecretKeyData> _macKeyOf(String purpose) => _macKeys.putIfAbsent(
    purpose,
    () => _hkdf.deriveKey(
      secretKey: SecretKey(_masterKey),
      info: utf8.encode('field-mac:$purpose'),
    ),
  );
}
