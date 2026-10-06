import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

class SecurityUtil {
  static final String secretKey = 'a8F3kL2mQ9zX7vB1';
  static final String secretIV = 'T6pR4sW8yU1eZ0nC';

  static final _algorithm = AesCbc.with128bits(
    macAlgorithm: MacAlgorithm.empty,
  );

  ///AES加密
  ///param data 明文
  ///return 密文(base64)
  static Future<String> encryptAES(String data) async {
    final secretKeyBytes = utf8.encode(secretKey);
    final ivBytes = utf8.encode(secretIV);
    final dataBytes = utf8.encode(data);

    final secretBox = await _algorithm.encrypt(
      dataBytes,
      secretKey: SecretKey(secretKeyBytes),
      nonce: ivBytes,
    );

    // 合并 nonce 和 ciphertext (IV + encrypted data)
    final combined = Uint8List(ivBytes.length + secretBox.cipherText.length)
      ..setAll(0, ivBytes)
      ..setAll(ivBytes.length, secretBox.cipherText);

    return base64.encode(combined);
  }

  ///AES解密
  ///param data 密文(base64)
  ///return 明文
  static Future<String> decryptAES(String data) async {
    final secretKeyBytes = utf8.encode(secretKey);
    final ivBytes = utf8.encode(secretIV);

    final combined = base64.decode(data);

    // 提取 IV 和密文
    final cipherText = combined.sublist(ivBytes.length);

    final decrypted = await _algorithm.decrypt(
      SecretBox(cipherText, nonce: ivBytes, mac: Mac.empty),
      secretKey: SecretKey(secretKeyBytes),
    );

    return utf8.decode(decrypted);
  }

  ///生成MD5签名
  ///param data 明文
  ///return MD5签名
  static String generateMD5(String data) {
    return md5.convert(utf8.encode(data)).toString();
  }
}
