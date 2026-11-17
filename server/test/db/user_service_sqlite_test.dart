// 用户管理服务集成测试（SQLite 内存库，走全量迁移建表——顺带验证
// v12 的 SYS_USER_ROLE 结构）：新增校验与 UUID 主键回读、敏感字段加密
// 与盲索引、列表携带角色 ID、字段级修改与口令重置、角色全量覆盖保存。
import 'dart:convert';

import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/services/user_service.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:server/utils/password_helper.dart';
import 'package:test/test.dart';

import '../support/test_divisions.dart';

// fixture 固定 UUID（任意 36 位字符串均可作 CHAR(36) 主键值，固定值便于
// 跨行引用；按字符串序排好，保证「ORDER BY ID/ROLE_ID」类排序断言稳定）。
const hosp1Id = 'a0000000-0000-0000-0000-000000000001'; // 示例人民医院
const hosp2Id = 'a0000000-0000-0000-0000-000000000002'; // 儿童心理分院
const dept11Id = 'a0000000-0000-0000-0000-000000000011'; // 医院 1 顶级科室
const dept12Id = 'a0000000-0000-0000-0000-000000000012'; // 医院 1，挂 dept11Id 下
const dept21Id = 'a0000000-0000-0000-0000-000000000021'; // 医院 2 顶级科室
const role101Id = 'b0000000-0000-0000-0000-000000000101'; // 医院 1 角色
const role102Id = 'b0000000-0000-0000-0000-000000000102'; // 医院 1 角色
const role201Id = 'b0000000-0000-0000-0000-000000000201'; // 医院 2 角色

/// 不存在的 ID 取值（UUID 主键不校验格式，任意非空未知取值统一走「不存在」）。
const unknownId = '99999999-9999-9999-9999-999999999999';

/// UUID v7 主键形态（36 位连字符形式）。
final _uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

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
    // fixture：医院 1/2；医院 1 的两个科室（顶级 + 下级）、医院 2 的一个
    // 科室；医院 1 的两个角色与医院 2 的一个角色。
    await db.execute(
      'INSERT INTO SYS_HOSPITAL (ID, PARENT_ID, CODE, NAME, PROVINCE, CITY, '
      'ADDRESS, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [hosp1Id, null, 'H001', '示例人民医院', '北京市', '北京市', '示例路1号', '2026-01-01 00:00:00'],
    );
    await db.execute(
      'INSERT INTO SYS_HOSPITAL (ID, PARENT_ID, CODE, NAME, PROVINCE, CITY, '
      'ADDRESS, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [hosp2Id, hosp1Id, 'H002', '儿童心理分院', '北京市', '北京市', '示例路1-1号', '2026-01-01 00:00:00'],
    );
    Future<void> seedDept(String id, String hospId, String? parentId, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_DEPARTMENT (ID, HOSP_ID, CAMPUS_ID, PARENT_ID, CODE, '
        'NAME, CREATE_TIME) VALUES (?, ?, NULL, ?, ?, ?, ?)',
        [id, hospId, parentId, code, name, '2026-01-01 00:00:00'],
      );
    }

    await seedDept(dept11Id, hosp1Id, null, 'D001', '科室11');
    await seedDept(dept12Id, hosp1Id, dept11Id, 'D002', '科室12');
    await seedDept(dept21Id, hosp2Id, null, 'D101', '科室21');
    Future<void> seedRole(String id, String hospId, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_ROLE (ID, ROLE_CODE, ROLE_NAME, HOSP_ID, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?)',
        [id, code, name, hospId, '2026-01-01 00:00:00'],
      );
    }

    await seedRole(role101Id, hosp1Id, 'R001', '角色101');
    await seedRole(role102Id, hosp1Id, 'R002', '角色102');
    await seedRole(role201Id, hosp2Id, 'R101', '角色201');
    service = UserService(db, cipher);
    addTearDown(() {
      db.close();
      clearTestDivisionsCsv(divisionsDir);
    });
  });

  test('create：成功生成 UUID 主键；手机号/身份证号密文入库、盲索引可命中', () async {
    final user = await service.create(
      hospId: hosp1Id,
      deptId: dept11Id,
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
      userType: 'DOCTOR',
      permissionLevel: '1',
      phone: '13900000111',
      idCardNo: '110101199001011234',
      avatarImage: 'aV1oYXZhX2Jhc2U2NA==',
      roleIds: [role101Id, role102Id],
    );
    expect(user.id, matches(_uuidPattern));
    expect(user.userCode, 'doctor01');
    expect(user.hospId, hosp1Id);
    expect(user.deptId, dept11Id);
    expect(user.roleIds, [role101Id, role102Id]);
    expect(user.avatarImage, 'aV1oYXZhX2Jhc2U2NA==');

    // 库中为密文（非明文）、盲索引等值查询可命中
    final row = await db.query(
      'SELECT PASSWORD, PHONE, PHONE_HMAC, ID_CARD_NO, ID_CARD_NO_HMAC '
      'FROM SYS_USER WHERE ID = ?',
      [user.id],
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
    expect(PasswordHelper.verifyStoredPassword(cols['PASSWORD']!, 'Doctor@123'), isTrue);
  });

  test('listByHospital：仅返回指定医院用户、携带各自角色；getById 解密回明文', () async {
    final u1 = await service.create(
      hospId: hosp1Id,
      deptId: dept11Id,
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
      userType: 'DOCTOR',
      permissionLevel: '1',
      phone: '13900000111',
      roleIds: [role101Id],
    );
    // newUuid() 带同毫秒单调计数器（字符串序=生成序），此延时仅为
    // 防御性保险，不依赖它保证排序
    await service.create(
      hospId: hosp1Id,
      deptId: dept12Id,
      userCode: 'nurse01',
      userName: '陈晓',
      password: 'Nurse@123',
      userType: 'NURSE',
      permissionLevel: '0',
    );
    await service.create(
      hospId: hosp2Id,
      deptId: dept21Id,
      userCode: 'doctor99',
      userName: '分院医生',
      password: 'Doctor@123',
      userType: 'DOCTOR',
      permissionLevel: '1',
    );

    final users = await service.listByHospital(hosp1Id);
    expect(users.map((u) => u.userCode), ['doctor01', 'nurse01']);
    expect(users.first.phone, '13900000111');
    expect(users.first.roleIds, [role101Id]);
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
      String? userType = 'DOCTOR',
      String? permissionLevel = '1',
    }) async {
      await expectLater(
        service.create(
          hospId: hospId,
          deptId: deptId,
          userCode: userCode,
          userName: '张三',
          password: password,
          userType: userType,
          permissionLevel: permissionLevel,
          roleIds: roleIds,
        ),
        throwsA(isA<UserException>().having((e) => e.message, 'message', contains(fragment))),
      );
    }

    await expectCreate(unknownId, dept11Id, 'a001', 'Pass@123', '不存在');
    await expectCreate(hosp1Id, unknownId, 'a001', 'Pass@123', '挂载科室不存在');
    await expectCreate(hosp1Id, dept21Id, 'a001', 'Pass@123', '不属于当前医院');
    await service.create(
      hospId: hosp1Id,
      deptId: dept11Id,
      userCode: 'dup',
      userName: '张三',
      password: 'Pass@123',
      userType: 'DOCTOR',
      permissionLevel: '1',
    );
    await expectCreate(hosp1Id, dept11Id, 'dup', 'Pass@123', '登录账号已存在');
    await expectCreate(hosp1Id, dept11Id, 'a002', '123', '密码长度');
    await expectCreate(hosp1Id, dept11Id, ' ', 'Pass@123', '不能为空');
    // 无效角色 / 跨医院角色
    await expectCreate(hosp1Id, dept11Id, 'a003', 'Pass@123', '无效的角色', roleIds: [unknownId]);
    await expectCreate(hosp1Id, dept11Id, 'a003', 'Pass@123', '无效的角色', roleIds: [role201Id]);
    // 用户类别 / 权限级别必填
    await expectCreate(hosp1Id, dept11Id, 'a004', 'Pass@123', '用户类别不能为空', userType: null);
    await expectCreate(hosp1Id, dept11Id, 'a004', 'Pass@123', '权限级别不能为空', permissionLevel: null);
  });

  test('create：口令等保三级复杂度校验（8-32 位、至少三类字符、不与账号相同）', () async {
    Future<void> expectPwd(String userCode, String password, String fragment) async {
      await expectLater(
        service.create(
          hospId: hosp1Id,
          deptId: dept11Id,
          userCode: userCode,
          userName: '张三',
          password: password,
          userType: 'DOCTOR',
          permissionLevel: '1',
        ),
        throwsA(isA<UserException>().having((e) => e.message, 'message', contains(fragment))),
      );
    }

    // 长度不足（不足 8 位，四类字符也无济于事）
    await expectPwd('a001', 'Ab@1x9', '密码长度');
    // 复杂度不足：小写 + 数字仅两类
    await expectPwd('a002', 'password1', '复杂度不足');
    // 复杂度不足：纯字母（大小写各一类共两类）
    await expectPwd('a003', 'PasswordAbc', '复杂度不足');
    // 与登录账号相同
    await expectPwd('Admin@123', 'Admin@123', '不能与登录账号相同');
    // 三类字符（大写 + 小写 + 数字，无特殊字符）合规通过
    final ok = await service.create(
      hospId: hosp1Id,
      deptId: dept11Id,
      userCode: 'a004',
      userName: '张三',
      password: 'Password123',
      userType: 'DOCTOR',
      permissionLevel: '1',
    );
    expect(ok.userCode, 'a004');
  });

  test('update：改姓名/手机号并重算密文盲索引、重置口令、清空可空字段', () async {
    final created = await service.create(
      hospId: hosp1Id,
      deptId: dept11Id,
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
      userType: 'DOCTOR',
      permissionLevel: '1',
      phone: '13900000111',
      roleIds: [role101Id],
    );
    final updated = await service.update(
      created.id,
      {'userName': '王心怡医生', 'phone': '13900000222', 'hisUserCode': null, 'avatarImage': 'YXZhdGFyX25ldw=='},
      password: 'NewPass@123',
    );
    expect(updated.userName, '王心怡医生');
    expect(updated.phone, '13900000222');
    expect(updated.hisUserCode, isNull);
    expect(updated.avatarImage, 'YXZhdGFyX25ldw==');

    final row = await db.query(
      'SELECT PASSWORD, PHONE, PHONE_HMAC FROM SYS_USER WHERE ID = ?',
      [created.id],
    );
    final cols = row.rowsAsMaps.first;
    expect(PasswordHelper.verifyStoredPassword(cols['PASSWORD']!, 'NewPass@123'), isTrue);
    expect(PasswordHelper.verifyStoredPassword(cols['PASSWORD']!, 'Doctor@123'), isFalse);
    final byMac = await db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_USER WHERE PHONE_HMAC = ?',
      [await cipher.mac(FieldCipher.phonePurpose, '13900000222')],
    );
    expect(byMac.rowsAsMaps.first['CNT'], '1');
    // UPDATE_TIME 已写入
    final ts = await db.query(
      'SELECT UPDATE_TIME FROM SYS_USER WHERE ID = ?',
      [created.id],
    );
    expect(ts.rows.first[0], isNotNull);
  });

  test('update：roleIds 全量覆盖、仅改角色、roleIds 传 null 不动角色', () async {
    final created = await service.create(
      hospId: hosp1Id,
      deptId: dept11Id,
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
      userType: 'DOCTOR',
      permissionLevel: '1',
      roleIds: [role101Id, role102Id],
    );

    // 覆盖为单角色
    var updated = await service.update(created.id, {}, roleIds: [role102Id]);
    expect(updated.roleIds, [role102Id]);

    // 空列表清空
    updated = await service.update(created.id, {}, roleIds: []);
    expect(updated.roleIds, isEmpty);

    // null 不动角色：先补回再验证
    await service.update(created.id, {}, roleIds: [role101Id]);
    updated = await service.update(created.id, {'userName': '王医生'});
    expect(updated.userName, '王医生');
    expect(updated.roleIds, [role101Id]);
  });

  test('update：登录账号/归属/挂载科室/未知字段不可改、用户不存在报错', () async {
    final created = await service.create(
      hospId: hosp1Id,
      deptId: dept11Id,
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
      userType: 'DOCTOR',
      permissionLevel: '1',
    );
    for (final key in ['userCode', 'hospId', 'deptId', 'id', 'foo']) {
      await expectLater(
        service.update(created.id, {key: hosp2Id}),
        throwsA(isA<UserException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
      );
    }
    // UUID 主键不校验格式：任意非空未知取值统一走「不存在」（40001）
    await expectLater(
      service.update(unknownId, {'userName': '张三'}),
      throwsA(isA<UserException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('update：permissionLevel / status 取值校验；必填字段不可清空、口令复杂度兜底', () async {
    final created = await service.create(
      hospId: hosp1Id,
      deptId: dept11Id,
      userCode: 'doctor01',
      userName: '王心怡',
      password: 'Doctor@123',
      userType: 'DOCTOR',
      permissionLevel: '1',
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
    // 用户类别 / 权限级别必填：传 null（清空语义）直接拒绝
    await expectLater(
      service.update(created.id, {'userType': null}),
      throwsA(isA<UserException>().having((e) => e.message, 'message', contains('用户类别不能为空'))),
    );
    await expectLater(
      service.update(created.id, {'permissionLevel': null}),
      throwsA(isA<UserException>().having((e) => e.message, 'message', contains('权限级别不能为空'))),
    );
    // 口令重置同样走等保三级校验（长度 / 与账号相同 / 复杂度不足）
    await expectLater(
      service.update(created.id, {}, password: 'Ab@1x9'),
      throwsA(isA<UserException>().having((e) => e.message, 'message', contains('密码长度'))),
    );
    await expectLater(
      service.update(created.id, {}, password: 'doctor01'),
      throwsA(isA<UserException>().having((e) => e.message, 'message', contains('不能与登录账号相同'))),
    );
    await expectLater(
      service.update(created.id, {}, password: 'doctor012345'),
      throwsA(isA<UserException>().having((e) => e.message, 'message', contains('复杂度不足'))),
    );
  });
}
