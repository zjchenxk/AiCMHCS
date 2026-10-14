import 'dart:convert';

import 'package:common/utils/security_util.dart';
import 'package:test/test.dart';

void main() {
  group('SecurePayload 信封', () {
    test('加密后可解开还原明文（含中文）', () async {
      final key = SecurePayload.generateSessionKey();
      final plain = {
        'code': 0,
        'message': '登录成功',
        'data': {'id': 1, 'userName': '测试用户'},
      };
      final sealed = await SecurePayload.seal(key, plain);
      expect(sealed.keys, contains('payload'));
      expect(await SecurePayload.open(key, sealed), plain);
    });

    test('同一明文两次加密的密文不同（nonce 随机）', () async {
      final key = SecurePayload.generateSessionKey();
      final s1 = await SecurePayload.seal(key, {'a': 1});
      final s2 = await SecurePayload.seal(key, {'a': 1});
      expect(s1['payload'], isNot(s2['payload']));
    });

    test('密文被篡改时解密失败（GCM 完整性）', () async {
      final key = SecurePayload.generateSessionKey();
      final sealed = await SecurePayload.seal(key, {'a': 1});
      final bytes = base64Decode(sealed['payload'] as String);
      bytes[bytes.length - 1] ^= 0x01;
      sealed['payload'] = base64Encode(bytes);
      await expectLater(
        SecurePayload.open(key, sealed),
        throwsA(isA<SecurePayloadException>()),
      );
    });

    test('密钥不匹配时解密失败', () async {
      final sealed = await SecurePayload.seal(
        SecurePayload.generateSessionKey(),
        {'a': 1},
      );
      await expectLater(
        SecurePayload.open(SecurePayload.generateSessionKey(), sealed),
        throwsA(isA<SecurePayloadException>()),
      );
    });

    test('非信封报文被拒绝', () async {
      final key = SecurePayload.generateSessionKey();
      await expectLater(
        SecurePayload.open(key, {'foo': 'bar'}),
        throwsA(isA<SecurePayloadException>()),
      );
    });

    test('会话密钥随机且长度固定', () {
      final k1 = SecurePayload.generateSessionKey();
      final k2 = SecurePayload.generateSessionKey();
      expect(k1, isNot(k2));
      expect(base64Decode(k1), hasLength(32));
    });
  });
}
