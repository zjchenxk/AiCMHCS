// 用户管理服务集成测试（SQLite 内存库，走全量迁移建表——顺带验证
// v12 的 SYS_USER_ROLE 结构）：新增校验与自然键回读、敏感字段加密与
// 盲索引、列表携带角色 ID、字段级修改与口令重置、角色全量覆盖保存。
import 'dart:convert';

import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/user_service.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:test/test.dart';

import '../support/test_divisions.dart';

void main() {
  late SqliteGateway db;
  late UserService service;
  // 固定测试主密钥（与 auth_service_sqlite_test 同款），v2 dataFix 需注入。
  final cipher = FieldCipher.fromMasterKeyBase64(
    base64Encode(utf8.encode('0123456789abcdef0123456789abcdef')),
  );

  setUp(() async {
    final divisionsDir = setUpTestDivisionsCsv();
    db = await SqliteGateway.start(':memory:');
    await SchemaMigrator(db, fieldCipher: cipher).migrate();
    // fixture：医院 1/2；医院 1 的科室 11（顶级）与 12（11 的下级）、
    // 医院 2 的科室 21；医院 1 的角色 101/102 与医院 2 的角色 201。
    await db.execute(
      'INSERT INTO SYS_HOSPITAL (ID, PARENT_ID, CODE, NAME, PROVINCE, CITY, '
      'ADDRESS, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [1, null, 'H001', '示例人民医院', '北京市', '北京市', '示例路1号', '2026-01-01 00:00:00'],
    );
    await db.execute(
      'INSERT INTO SYS_HOSPITAL (ID, PARENT_ID, CODE, NAME, PROVINCE, CITY, '
      'ADDRESS, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [2, 1, 'H002', '儿童心理分院', '北京市', '北京市', '示例路1-1号', '2026-01-01 00:00:00'],
    );
    Future<void> seedDept(int id, int hospId, int? parentId, String code) async {
      await db.execute(
        'INSERT INTO SYS_DEPARTMENT (ID, HOSP_ID, CAMPUS_ID, PARENT_ID, CODE, '
        'NAME, CREATE_TIME) VALUES (?, ?, NULL, ?, ?, ?, ?)',
        [id, hospId, parentId, code, '科室$id', '2026-01-01 00:00:00'],
      );
    }

    await seedDept(11, 1, null, 'D001');
    await seedDept(12, 1, 11, 'D002');
    await seedDept(21, 2, null, 'D101');
    Future<void> seedRole(int id, int hospId, String code) async {
      await db.execute(
        'INSERT INTO SYS_ROLE (ID, ROLE_CODE, ROLE_NAME, HOSP_ID, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?)',
        [id, code, '角色$id', hospId, '2026-01-01 00:00:00'],
      );
    }

    await seedRole(101, 1, 'R001');
    await seedRole(102, 1, 'R002');
    await seedRole(201, 2, 'R101');
    service = UserService(db, cipher);
    addTearDown(() {
      db.close();
      clearTestDivisionsCsv(divisionsDir);
    });
  });

  test('create：成功并经登录账号回读自增 ID；手机号/身份证号密文入库、盲索引可命中', () async {
    final user = await service.create(
      hospId: '1',
      deptId: '11',
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
      userType: 'DOCTOR',
      permissionLevel: '1',
      phone: '13900000111',
      idCardNo: '110101199001011234',
      roleIds: ['101', '102'],
    );
    expect(user.id, isNotEmpty);
    expect(user.userCode, 'doctor01');
    expect(user.hospId, '1');
    expect(user.deptId, '11');
    expect(user.roleIds, ['101', '102']);

    // 库中为密文（非明文）、盲索引等值查询可命中
    final row = await db.query(
      'SELECT PASSWORD, PHONE, PHONE_HMAC, ID_CARD_NO, ID_CARD_NO_HMAC '
      'FROM SYS_USER WHERE ID = ?',
      [int.parse(user.id)],
    );
    final cols = row.rowsAsMaps.first;
    expect(cols['PHONE'], isNot('13900000111'));
    expect(cols['PHONE']!.startsWith('v1:'), isTrue);
    expect(cols['ID_CARD_NO'], isNot('110101199001011234'));
    final byMac = await db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_USER WHERE PHONE_HMAC = ?',
      [await cipher.mac(FieldCipher.phonePurpose, '13900000111')],
    );
    expect(byMac.rowsAsMaps.first['CNT'], '1');
    // 口令为 salt:hash 格式且可校验通过
    expect(AuthService.verifyStoredPassword(cols['PASSWORD']!, 'Doctor@123'), isTrue);
  });

  test('listByHospital：仅返回指定医院用户、携带各自角色；getById 解密回明文', () async {
    final u1 = await service.create(
      hospId: '1',
      deptId: '11',
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
      phone: '13900000111',
      roleIds: ['101'],
    );
    await service.create(
      hospId: '1',
      deptId: '12',
      userCode: 'nurse01',
      userName: '陈晓',
      password: 'Nurse@123',
    );
    await service.create(
      hospId: '2',
      deptId: '21',
      userCode: 'doctor99',
      userName: '分院医生',
      password: 'Doctor@123',
    );

    final users = await service.listByHospital('1');
    expect(users.map((u) => u.userCode), ['doctor01', 'nurse01']);
    expect(users.first.phone, '13900000111');
    expect(users.first.roleIds, ['101']);
    expect(users.last.roleIds, isEmpty);

    final detail = await service.getById(u1.id);
    expect(detail.idCardNo, isNull);
    expect(detail.phone, '13900000111');
  });

  test('create：医院/科室/账号/口令校验与角色归属校验均报错', () async {
    Future<void> expectCreate(
      String hospId,
      String deptId,
      String userCode,
      String password,
      String fragment, {
      List<String> roleIds = const [],
    }) async {
      await expectLater(
        service.create(
          hospId: hospId,
          deptId: deptId,
          userCode: userCode,
          userName: '张三',
          password: password,
          roleIds: roleIds,
        ),
        throwsA(isA<UserException>().having((e) => e.message, 'message', contains(fragment))),
      );
    }

    await expectCreate('99', '11', 'a001', 'Pass@123', '不存在');
    await expectCreate('1', '99', 'a001', 'Pass@123', '挂载科室不存在');
    await expectCreate('1', '21', 'a001', 'Pass@123', '不属于当前医院');
    await service.create(
      hospId: '1',
      deptId: '11',
      userCode: 'dup',
      userName: '张三',
      password: 'Pass@123',
    );
    await expectCreate('1', '11', 'dup', 'Pass@123', '登录账号已存在');
    await expectCreate('1', '11', 'a002', '123', '密码长度');
    await expectCreate('1', '11', ' ', 'Pass@123', '不能为空');
    // 无效角色 / 跨医院角色
    await expectCreate('1', '11', 'a003', 'Pass@123', '无效的角色', roleIds: ['999']);
    await expectCreate('1', '11', 'a003', 'Pass@123', '无效的角色', roleIds: ['201']);
  });

  test('update：改姓名/手机号并重算密文盲索引、重置口令、清空可空字段', () async {
    final created = await service.create(
      hospId: '1',
      deptId: '11',
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
      phone: '13900000111',
      roleIds: ['101'],
    );
    final updated = await service.update(
      created.id,
      {'userName': '王心怡医生', 'phone': '13900000222', 'hisUserCode': null},
      password: 'NewPass@123',
    );
    expect(updated.userName, '王心怡医生');
    expect(updated.phone, '13900000222');
    expect(updated.hisUserCode, isNull);

    final row = await db.query(
      'SELECT PASSWORD, PHONE, PHONE_HMAC FROM SYS_USER WHERE ID = ?',
      [int.parse(created.id)],
    );
    final cols = row.rowsAsMaps.first;
    expect(AuthService.verifyStoredPassword(cols['PASSWORD']!, 'NewPass@123'), isTrue);
    expect(AuthService.verifyStoredPassword(cols['PASSWORD']!, 'Doctor@123'), isFalse);
    final byMac = await db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_USER WHERE PHONE_HMAC = ?',
      [await cipher.mac(FieldCipher.phonePurpose, '13900000222')],
    );
    expect(byMac.rowsAsMaps.first['CNT'], '1');
    // UPDATE_TIME 已写入
    final ts = await db.query(
      'SELECT UPDATE_TIME FROM SYS_USER WHERE ID = ?',
      [int.parse(created.id)],
    );
    expect(ts.rows.first[0], isNotNull);
  });

  test('update：roleIds 全量覆盖、仅改角色、roleIds 传 null 不动角色', () async {
    final created = await service.create(
      hospId: '1',
      deptId: '11',
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
      roleIds: ['101', '102'],
    );

    // 覆盖为单角色
    var updated = await service.update(created.id, {}, roleIds: ['102']);
    expect(updated.roleIds, ['102']);

    // 空列表清空
    updated = await service.update(created.id, {}, roleIds: []);
    expect(updated.roleIds, isEmpty);

    // null 不动角色：先补回再验证
    await service.update(created.id, {}, roleIds: ['101']);
    updated = await service.update(created.id, {'userName': '王医生'});
    expect(updated.userName, '王医生');
    expect(updated.roleIds, ['101']);
  });

  test('update：登录账号/归属/挂载科室/未知字段不可改、用户不存在报错', () async {
    final created = await service.create(
      hospId: '1',
      deptId: '11',
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
    );
    for (final key in ['userCode', 'hospId', 'deptId', 'id', 'foo']) {
      await expectLater(
        service.update(created.id, {key: '1'}),
        throwsA(isA<UserException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
      );
    }
    await expectLater(
      service.update('999', {'userName': '张三'}),
      throwsA(isA<UserException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('update：permissionLevel / status 取值校验', () async {
    final created = await service.create(
      hospId: '1',
      deptId: '11',
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
    );
    final updated = await service.update(created.id, {'permissionLevel': '2', 'status': '0'});
    expect(updated.permissionLevel, '2');
    expect(updated.status, '0');
    await expectLater(
      service.update(created.id, {'permissionLevel': '3'}),
      throwsA(isA<UserException>().having((e) => e.message, 'message', contains('权限级别'))),
    );
    await expectLater(
      service.update(created.id, {'status': '9'}),
      throwsA(isA<UserException>().having((e) => e.message, 'message', contains('状态'))),
    );
  });
}
