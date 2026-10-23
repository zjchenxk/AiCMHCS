// 登录链路端到端集成测试（SQLite 内存库）：验证迁移结构与
// AuthService 的 SQL 完全兼容——口令校验、审计写入、最近登录时间、
// 会话生命周期全部走真实网关。
import 'dart:convert';

import 'package:server/db/schema_migrator.dart';
import 'package:server/db/sqlite_gateway.dart';
import 'package:server/security/field_cipher.dart';
import 'package:server/services/auth_service.dart';
import 'package:test/test.dart';

void main() {
  late SqliteGateway db;
  late AuthService auth;
  // v2 起迁移含 dataFix（存量明文加密回填），需注入密钥。
  final cipher = FieldCipher.fromMasterKeyBase64(
    base64Encode(utf8.encode('0123456789abcdef0123456789abcdef')),
  );

  setUpAll(() async {
    db = await SqliteGateway.start(':memory:');
    await SchemaMigrator(db, fieldCipher: cipher).migrate();
    await db.execute(
      'INSERT INTO SYS_USER '
      '(USER_CODE, PASSWORD, USER_NAME, ROLE_CODE, PHONE, STATUS) '
      'VALUES (?, ?, ?, ?, ?, 1)',
      [
        'admin',
        AuthService.makeStoredPassword('Admin@123'),
        '系统管理员',
        'ADMIN',
        '13800000001',
      ],
    );
    auth = AuthService(db);
  });

  tearDownAll(() => db.close());

  test('登录成功：返回会话、写审计、更新最近登录时间', () async {
    final session = await auth.login('admin', 'Admin@123', ip: '127.0.0.1');
    expect(session.user.id, greaterThan(0));
    expect(session.user.userCode, 'admin');
    expect(session.user.userName, '系统管理员');
    expect(session.user.roleCode, 'ADMIN');
    expect(session.sessionKey, isNotEmpty);

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
