// 字段加密与盲索引单元测试：加解密往返、随机 nonce、HMAC 确定性与
// 口径一致、密钥/用途隔离、存量明文兼容、版本前缀与主密钥合法性校验、
// 密钥文件解析（环境变量优先 → 读文件 → 自动生成）。
import 'dart:convert';
import 'dart:io';

import 'package:server/app_config.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:test/test.dart';

const phone = '13800000001';

/// 32 字节测试主密钥原文（base64 由测试内即时编码）。
const rawKey = '0123456789abcdef0123456789abcdef';

FieldCipher cipherOf(String raw) => FieldCipher.fromMasterKeyBase64(base64Encode(utf8.encode(raw)));

void main() {
  final cipher = cipherOf('0123456789abcdef0123456789abcdef');

  group('加解密往返', () {
    test('seal 后可 open 还原（明文两侧空格被 trim）', () async {
      final sealed = await cipher.seal(FieldCipher.phonePurpose, '  $phone  ');
      expect(sealed, startsWith('v1:'));
      expect(await cipher.open(FieldCipher.phonePurpose, sealed), phone);
    });

    test('null 透传：seal / open / mac 均返回 null', () async {
      expect(await cipher.seal(FieldCipher.phonePurpose, null), isNull);
      expect(await cipher.open(FieldCipher.phonePurpose, null), isNull);
      expect(await cipher.mac(FieldCipher.phonePurpose, null), isNull);
    });

    test('随机 nonce：同明文两次密文不同，但均可还原', () async {
      final a = await cipher.seal(FieldCipher.phonePurpose, phone);
      final b = await cipher.seal(FieldCipher.phonePurpose, phone);
      expect(a, isNot(b));
      expect(await cipher.open(FieldCipher.phonePurpose, a), phone);
      expect(await cipher.open(FieldCipher.phonePurpose, b), phone);
    });

    test('不带版本前缀的存量明文原样返回', () async {
      expect(
        await cipher.open(FieldCipher.phonePurpose, phone),
        phone,
      );
      expect(FieldCipher.looksEncrypted(phone), isFalse);
      expect(
        FieldCipher.looksEncrypted(
          (await cipher.seal(FieldCipher.phonePurpose, phone))!,
        ),
        isTrue,
      );
    });

    test('密文被篡改时 GCM 认证失败', () async {
      final sealed = await cipher.seal(FieldCipher.phonePurpose, phone);
      final bytes = base64Decode(sealed!.substring(3)).toList();
      bytes[bytes.length - 1] ^= 0x01;
      final tampered = 'v1:${base64Encode(bytes)}';
      await expectLater(
        cipher.open(FieldCipher.phonePurpose, tampered),
        throwsA(isA<FieldCipherException>()),
      );
    });

    test('不支持的密文版本（v2:）抛错', () async {
      await expectLater(
        cipher.open(FieldCipher.phonePurpose, 'v2:AAAA'),
        throwsA(
          isA<FieldCipherException>().having(
            (e) => e.message,
            'message',
            contains('v2'),
          ),
        ),
      );
    });
  });

  group('密钥与用途隔离', () {
    test('主密钥错误时解密失败', () async {
      final sealed = await cipher.seal(FieldCipher.phonePurpose, phone);
      final other = cipherOf('fedcba9876543210fedcba9876543210');
      await expectLater(
        other.open(FieldCipher.phonePurpose, sealed),
        throwsA(isA<FieldCipherException>()),
      );
    });

    test('purpose 不同则子密钥不同，跨用途解不开', () async {
      final sealed = await cipher.seal(FieldCipher.phonePurpose, phone);
      await expectLater(
        cipher.open('email', sealed),
        throwsA(isA<FieldCipherException>()),
      );
    });
  });

  group('盲索引', () {
    test('HMAC 确定性、输出 64 位十六进制', () async {
      final a = await cipher.mac(FieldCipher.phonePurpose, phone);
      final b = await cipher.mac(FieldCipher.phonePurpose, phone);
      expect(a, b);
      expect(a, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(a!), isTrue);
    });

    test('与 seal 同口径 trim，空格不影响命中', () async {
      expect(
        await cipher.mac(FieldCipher.phonePurpose, '  $phone  '),
        await cipher.mac(FieldCipher.phonePurpose, phone),
      );
    });

    test('不同主密钥的盲索引不同', () async {
      final other = cipherOf('fedcba9876543210fedcba9876543210');
      expect(
        await cipher.mac(FieldCipher.phonePurpose, phone),
        isNot(await other.mac(FieldCipher.phonePurpose, phone)),
      );
    });
  });

  group('主密钥解析', () {
    test('非法 base64 或长度不符直接抛错', () {
      expect(
        () => FieldCipher.fromMasterKeyBase64('不是base64!!'),
        throwsA(isA<FieldCipherException>()),
      );
      expect(
        () => FieldCipher.fromMasterKeyBase64(base64Encode([1, 2, 3])),
        throwsA(isA<FieldCipherException>()),
      );
    });

    test('fromConfig：环境变量优先于密钥文件', () async {
      final dir = await Directory.systemTemp.createTemp('aicmhcs_field');
      addTearDown(() => dir.delete(recursive: true));
      final keyFile = '${dir.path}${Platform.pathSeparator}field.key';
      await File(keyFile).writeAsString(
        base64Encode(utf8.encode('filefilefilefilefilefilefilefile')),
      );
      final config = AppConfig(
        dbDriver: 'sqlite',
        dbHost: '',
        dbPort: 0,
        dbUser: '',
        dbPassword: '',
        dbFile: '',
        fieldMasterKey: base64Encode(utf8.encode(rawKey)),
        fieldKeyFile: keyFile,
      );
      final cipher = await FieldCipher.fromConfig(config);
      expect(cipher.keyFileWasGenerated, isFalse);
      // 与环境变量密钥同源：能解开其密文。
      final sealed = await FieldCipher.fromMasterKeyBase64(
        config.fieldMasterKey!,
      ).seal(FieldCipher.phonePurpose, phone);
      expect(await cipher.open(FieldCipher.phonePurpose, sealed), phone);
    });

    test('fromConfig：无环境变量时读密钥文件', () async {
      final dir = await Directory.systemTemp.createTemp('aicmhcs_field');
      addTearDown(() => dir.delete(recursive: true));
      final keyFile = '${dir.path}${Platform.pathSeparator}field.key';
      await File(keyFile).writeAsString(
        base64Encode(utf8.encode('filefilefilefilefilefilefilefile')),
      );
      final config = AppConfig(
        dbDriver: 'sqlite',
        dbHost: '',
        dbPort: 0,
        dbUser: '',
        dbPassword: '',
        dbFile: '',
        fieldKeyFile: keyFile,
      );
      final cipher = await FieldCipher.fromConfig(config);
      expect(cipher.keyFileWasGenerated, isFalse);
      final sealed = await cipher.seal(FieldCipher.phonePurpose, phone);
      expect(
        await FieldCipher.fromMasterKeyBase64(
          await File(keyFile).readAsString(),
        ).open(FieldCipher.phonePurpose, sealed),
        phone,
      );
    });

    test('fromConfig：均未配置时自动生成密钥文件（含子目录）', () async {
      final dir = await Directory.systemTemp.createTemp('aicmhcs_field');
      addTearDown(() => dir.delete(recursive: true));
      final keyFile = '${dir.path}${Platform.pathSeparator}sub${Platform.pathSeparator}field.key';
      final config = AppConfig(
        dbDriver: 'sqlite',
        dbHost: '',
        dbPort: 0,
        dbUser: '',
        dbPassword: '',
        dbFile: '',
        fieldKeyFile: keyFile,
      );
      final cipher = await FieldCipher.fromConfig(config);
      expect(cipher.keyFileWasGenerated, isTrue);
      final written = await File(keyFile).readAsString();
      // 写入文件的密钥与实例一致：往返可用，重启后数据仍可解。
      final reloaded = FieldCipher.fromMasterKeyBase64(written);
      final sealed = await cipher.seal(FieldCipher.phonePurpose, phone);
      expect(await reloaded.open(FieldCipher.phonePurpose, sealed), phone);
      // 再次 fromConfig 走读文件分支，不再标记为自动生成。
      expect(
        (await FieldCipher.fromConfig(config)).keyFileWasGenerated,
        isFalse,
      );
    });
  });
}
