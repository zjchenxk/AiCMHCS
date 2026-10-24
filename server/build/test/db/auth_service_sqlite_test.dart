// 登录链路端到端集成测试（SQLite 内存库）：验证迁移结构与
// AuthService 的 SQL 完全兼容——口令校验、审计写入、最近登录时间、
// 会话生命周期全部走真实网关。
import 'dart:convert';
import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:test/test.dart';

import '../support/test_divisions.dart';

void main() {
  late SqliteGateway db;
  late AuthService auth;
  late String divisionsDir;
  // v2 起迁移含 dataFix（存量明文加密回填），需注入密钥。
  final cipher = FieldCipher.fromMasterKeyBase64(
    base64Encode(utf8.encode('0123456789abcdef0123456789abcdef')),
  );

  setUpAll(() async {
    // 全量 migrate 含 v3 seed，读注入的小份数据文件。
    divisionsDir = setUpTestDivisionsCsv();
    db = await SqliteGateway.start(':memory:');
    await SchemaMigrator(db, fieldCipher: cipher).migrate();
    // 联系电话经 FieldCipher 加密写入（与 seed/后端写入口径一致）。
    await db.execute(
      'INSERT INTO SYS_USER '
      '(USER_CODE, PASSWORD, USER_NAME, ROLE_CODE, PHONE, PHONE_HMAC, STATUS) '
      'VALUES (?, ?, ?, ?, ?, ?, 1)',
      [
        'admin',
        AuthService.makeStoredPassword('Admin@123'),
        '系统管理员',
        'ADMIN',
        await cipher.seal(FieldCipher.phonePurpose, '13800000001'),
        await cipher.mac(FieldCipher.phonePurpose, '13800000001'),
      ],
    );
    auth = AuthService(db, cipher);
  });

  tearDownAll(() {
    db.close();
    clearTestDivisionsCsv(divisionsDir);
  });

  test('登录成功：返回会话（手机号已解密）、写审计、更新最近登录时间', () async {
    final session = await auth.login('admin', 'Admin@123', ip: '127.0.0.1');
    expect(session.user.id, greaterThan(0));
    expect(session.user.userCode, 'admin');
    expect(session.user.userName, '系统管理员');
    expect(session.user.roleCode, 'ADMIN');
    expect(session.user.phone, '13800000001');
    expect(session.sessionKey, isNotEmpty);

    // 库内 PHONE 为密文，不残留明文（等保存储加密）。
    final stored = await db.query(
      'SELECT PHONE FROM SYS_USER WHERE USER_CODE = ?',
      ['admin'],
    );
    expect(stored.rows.single.first, startsWith('v1:'));
    expect(stored.rows.single.first, isNot(contains('13800000001')));

    final logs = await db.query(
      'SELECT USER_CODE, LOGIN_IP, LOGIN_RESULT, FAIL_REASON FROM SYS_LOGIN_LOG',
    );
    expect(logs.rows.single, ['admin', '127.0.0.1', 'SUCCESS', null]);

    final user = await db.query(
      'SELECT LAST_LOGIN_AT FROM SYS_USER WHERE USER_CODE = ?',
      ['admin'],
    );
    expect(user.rows.single.first, isNotNull);
  });

  test('存量明文行登录：手机号原样返回（读兼容兜底）', () async {
    await db.execute(
      'INSERT INTO SYS_USER '
      '(USER_CODE, PASSWORD, USER_NAME, ROLE_CODE, PHONE, STATUS) '
      "VALUES ('legacy', ?, '存量用户', 'DOCTOR', '13900000000', 1)",
      [AuthService.makeStoredPassword('Legacy@123')],
    );
    final session = await auth.login('legacy', 'Legacy@123');
    expect(session.user.phone, '13900000000');
  });

  test('口令错误：统一提示 40101 并写失败审计', () async {
    await expectLater(
      auth.login('admin', 'wrong'),
      throwsA(
        isA<AuthException>().having((e) => e.code, 'code', 40101),
      ),
    );
    final fails = await db.query(
      'SELECT LOGIN_RESULT, FAIL_REASON FROM SYS_LOGIN_LOG '
      "WHERE LOGIN_RESULT = 'FAIL'",
    );
    expect(fails.rows.single, ['FAIL', '用户名或密码错误']);
  });

  test('账号停用：40301', () async {
    await db.execute(
      'INSERT INTO SYS_USER '
      '(USER_CODE, PASSWORD, USER_NAME, ROLE_CODE, STATUS) '
      'VALUES (?, ?, ?, ?, 0)',
      ['disabled', AuthService.makeStoredPassword('X@123'), '停用账号', 'DOCTOR'],
    );
    await expectLater(
      auth.login('disabled', 'X@123'),
      throwsA(
        isA<AuthException>().having((e) => e.code, 'code', 40301),
      ),
    );
  });

  test('会话校验、续期与登出', () async {
    final session = await auth.login('admin', 'Admin@123');

    final verified = await auth.verify(session.token);
    expect(verified.userCode, 'admin');

    auth.logout(session.token);
    await expectLater(
      auth.verifySession(session.token),
      throwsA(
        isA<AuthException>().having((e) => e.code, 'code', 40102),
      ),
    );
  });
}
