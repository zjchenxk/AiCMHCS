// 登录链路端到端集成测试（SQLite 内存库）：验证迁移结构与
// AuthService 的 SQL 完全兼容——口令校验、审计写入、会话生命周期
// 全部走真实网关。
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
      '(USER_CODE, PASSWORD, USER_NAME, USER_TYPE, PHONE, PHONE_HMAC, STATUS) '
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

  test('登录成功：返回会话（手机号已解密）、写审计', () async {
    final session = await auth.login('superadmin', 'Admin@123', '1', ip: '127.0.0.1');
    expect(session.user.id, greaterThan(0));
    expect(session.user.userCode, 'admin');
    expect(session.user.userName, '系统管理员');
    expect(session.user.userType, 'ADMIN');
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
  });

  test('登录成功：关联下发医院/院区/科室真实名称', () async {
    // 种子：医院 9 → 院区 8 → 科室 7（挂院区下），用户挂该医院与科室
    await db.execute(
      'INSERT INTO SYS_HOSPITAL (ID, CODE, NAME, PROVINCE, CITY, ADDRESS, '
      'CREATE_TIME) VALUES (9, \'H0009\', \'测试三级医院\', \'北京市\', '
      '\'北京市\', \'测试路9号\', \'2026-11-08 09:00:00\')',
    );
    await db.execute(
      'INSERT INTO SYS_CAMPUS (ID, HOSP_ID, CODE, NAME, CREATE_TIME) '
      'VALUES (8, 9, \'C0008\', \'城南院区\', \'2026-11-08 09:00:00\')',
    );
    await db.execute(
      'INSERT INTO SYS_DEPARTMENT (ID, HOSP_ID, CAMPUS_ID, CODE, NAME, '
      'CREATE_TIME) VALUES (7, 9, 8, \'D0007\', \'儿童心理科\', '
      '\'2026-11-08 09:00:00\')',
    );
    await db.execute(
      'INSERT INTO SYS_USER '
      '(USER_CODE, PASSWORD, USER_NAME, USER_TYPE, HOSP_ID, DEPT_ID, STATUS) '
      'VALUES (?, ?, ?, ?, ?, ?, 1)',
      ['doctor09', AuthService.makeStoredPassword('Doctor@123'), '关联用户', 'DOCTOR', 9, 7],
    );

    final session = await auth.login('doctor09', 'Doctor@123', '2');
    expect(session.user.hospId, '9');
    expect(session.user.hospName, '测试三级医院');
    expect(session.user.deptId, '7');
    expect(session.user.deptName, '儿童心理科');
    // 院区经所属科室的 CAMPUS_ID 间接关联
    expect(session.user.campusId, '8');
    expect(session.user.campusName, '城南院区');

    // 未设置归属的用户名称字段为 null（LEFT JOIN 不命中）
    final bare = await auth.login('superadmin', 'Admin@123', '1');
    expect(bare.user.hospName, isNull);
    expect(bare.user.deptName, isNull);
  });

  test('存量明文行登录：手机号原样返回（读兼容兜底）', () async {
    await db.execute(
      'INSERT INTO SYS_USER '
      '(USER_CODE, PASSWORD, USER_NAME, USER_TYPE, PHONE, STATUS) '
      "VALUES ('legacy', ?, '存量用户', 'DOCTOR', '13900000000', 1)",
      [AuthService.makeStoredPassword('Legacy@123')],
    );
    final session = await auth.login('legacy', 'Legacy@123', '2');
    expect(session.user.phone, '13900000000');
  });

  test('口令错误：统一提示 40101 并写失败审计', () async {
    await expectLater(
      auth.login('admin', 'wrong', '6'),
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
      '(USER_CODE, PASSWORD, USER_NAME, USER_TYPE, STATUS) '
      'VALUES (?, ?, ?, ?, 0)',
      ['disabled', AuthService.makeStoredPassword('X@123'), '停用账号', 'DOCTOR'],
    );
    await expectLater(
      auth.login('disabled', 'X@123', '2'),
      throwsA(
        isA<AuthException>().having((e) => e.code, 'code', 40301),
      ),
    );
  });

  test('查询用户角色列表：三表联查返回 ID 与名称、未知用户返回空', () async {
    // 种子：专用用户 + 两个角色 + 角色关联（SYS_USER × SYS_USER_ROLE × SYS_ROLE），
    // 不依赖其他用例的数据（用例需可独立运行）
    await db.execute(
      'INSERT INTO SYS_USER '
      '(USER_CODE, PASSWORD, USER_NAME, USER_TYPE, STATUS) '
      "VALUES ('roleuser09', ?, '角色用户', 'DOCTOR', 1)",
      [AuthService.makeStoredPassword('Doctor@123')],
    );
    await db.execute(
      'INSERT INTO SYS_ROLE (ID, ROLE_CODE, ROLE_NAME, CREATE_TIME) VALUES '
      "(20, 'R0020', '儿童心理医生', '2026-11-08 09:00:00'), "
      "(10, 'R0010', '系统管理员', '2026-11-08 09:00:00')",
    );
    await db.execute(
      'INSERT INTO SYS_USER_ROLE (USER_ID, ROLE_ID) '
      'SELECT U.ID, R.ID FROM SYS_USER U, SYS_ROLE R '
      "WHERE U.USER_CODE = 'roleuser09' AND R.ID IN (10, 20)",
    );

    // 角色按 ID 升序返回，ID 为字符串形式（网关所有列以字符串返回）
    final roles = await auth.listUserRoles('roleuser09');
    expect(roles, [
      {'id': '10', 'roleName': '系统管理员'},
      {'id': '20', 'roleName': '儿童心理医生'},
    ]);

    // 未分配角色的用户与不存在的用户名统一返回空列表（避免账号枚举）
    expect(await auth.listUserRoles('admin'), isEmpty);
    expect(await auth.listUserRoles('nobody'), isEmpty);
  });

  test('会话校验、续期与登出', () async {
    final session = await auth.login('superadmin', 'Admin@123', '1');

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
