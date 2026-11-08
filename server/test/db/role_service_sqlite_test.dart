import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/role_service.dart';
import 'package:test/test.dart';

/// 角色管理服务单元测试（SQLite :memory:）：列表、详情、新增校验与
/// 自然键回读、字段级修改、删除连带清权限、菜单权限全量保存与查询。
void main() {
  late SqliteGateway db;
  late RoleService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    await db.executeDirect('''
CREATE TABLE SYS_HOSPITAL (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
  PARENT_ID INTEGER,
  CODE TEXT,
  NAME TEXT NOT NULL,
  NAME_EN TEXT,
  PROVINCE TEXT NOT NULL,
  CITY TEXT NOT NULL,
  COUNTY TEXT,
  TOWN TEXT,
  ADDRESS TEXT NOT NULL,
  TEL TEXT,
  LOGO_IMAGE TEXT,
  SEAL_IMAGE TEXT,
  WATERMARK_IMAGE TEXT,
  CREATE_TIME TEXT NOT NULL,
  UPDATE_TIME TEXT
)''');
    await db.executeDirect('''
CREATE TABLE SYS_MENU (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
  PARENT_ID INTEGER, -- 上级项目ID
  ITEM_CODE TEXT NOT NULL, -- 项目编码
  ITEM_NAME TEXT NOT NULL, -- 项目名称
  ITEM_TYPE TEXT NOT NULL, -- 项目类型：1-模块，2-菜单，3-操作
  MENU_ROUTE TEXT, -- 菜单路由
  MENU_ICON TEXT -- 菜单图标
)''');
    await db.executeDirect('''
CREATE TABLE SYS_ROLE (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
  ROLE_CODE TEXT NOT NULL, -- 角色编码
  ROLE_NAME TEXT NOT NULL, -- 角色名称
  REMARK TEXT, -- 备注
  HOSP_ID INTEGER NOT NULL, -- 所属医院ID
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 更新时间
)''');
    await db.executeDirect('''
CREATE TABLE SYS_ROLE_PERMISSION (
  ROLE_ID INTEGER NOT NULL, -- 角色ID
  MENU_ID INTEGER NOT NULL, -- 菜单ID
  PRIMARY KEY (ROLE_ID, MENU_ID)
)''');
    // 医院：1-示例人民医院、2-儿童心理分院。
    Future<void> seedHospital(int id, String name) async {
      await db.execute(
        'INSERT INTO SYS_HOSPITAL (ID, PARENT_ID, CODE, NAME, PROVINCE, CITY, '
        'ADDRESS, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, null, 'H00$id', name, '浙江省', '杭州市', '示例路1号', '2026-01-01 00:00:00'],
      );
    }

    await seedHospital(1, '示例人民医院');
    await seedHospital(2, '儿童心理分院');
    // 菜单：1 顶级模块、2 为 1 的下级菜单、3 为 2 的下级操作。
    Future<void> seedMenu(int id, int? parentId, String code) async {
      await db.execute(
        'INSERT INTO SYS_MENU (ID, PARENT_ID, ITEM_CODE, ITEM_NAME, ITEM_TYPE) '
        'VALUES (?, ?, ?, ?, ?)',
        [id, parentId, code, '项目$id', '1'],
      );
    }

    await seedMenu(1, null, 'M001');
    await seedMenu(2, 1, 'M002');
    await seedMenu(3, 2, 'M003');
    service = RoleService(db);
  });

  tearDown(() {
    db.close();
  });

  test('create：成功并经「医院+编码」回读自增 ID；备注可空', () async {
    final role = await service.create(
      hospId: '1',
      roleCode: 'R001',
      roleName: '系统管理员',
    );
    expect(role.id, '1');
    expect(role.hospId, '1');
    expect(role.remark, isNull);
  });

  test('create：不同医院允许同编码/同名称（按医院隔离判重）', () async {
    await service.create(hospId: '1', roleCode: 'R001', roleName: '医生');
    final other = await service.create(hospId: '2', roleCode: 'R001', roleName: '医生');
    expect(other.id, '2');
    expect(other.hospId, '2');
  });

  test('create：医院不存在 / 同医院编码或名称重复 / 必填缺失 / 超长均报错', () async {
    await service.create(hospId: '1', roleCode: 'R001', roleName: '系统管理员');
    await expectLater(
      service.create(hospId: '99', roleCode: 'R002', roleName: '医生'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('所属医院不存在'))),
    );
    await expectLater(
      service.create(hospId: '1', roleCode: 'R001', roleName: '其他角色'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('角色编码已存在'))),
    );
    await expectLater(
      service.create(hospId: '1', roleCode: 'R002', roleName: '系统管理员'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('角色名称已存在'))),
    );
    await expectLater(
      service.create(hospId: '1', roleCode: ' ', roleName: '无编码'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('角色编码不能为空'))),
    );
    await expectLater(
      service.create(hospId: '1', roleCode: 'R' * 11, roleName: '超长编码'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不能超过'))),
    );
  });

  test('listByHospital：仅返回指定医院的角色，按创建顺序', () async {
    await service.create(hospId: '1', roleCode: 'R001', roleName: '系统管理员');
    await service.create(hospId: '1', roleCode: 'R002', roleName: '医生', remark: '临床');
    await service.create(hospId: '2', roleCode: 'R003', roleName: '护士');
    final roles = await service.listByHospital('1');
    expect(roles.map((r) => r.roleCode), ['R001', 'R002']);
    expect(roles.last.remark, '临床');
  });

  test('getById：查详情；不存在与非法 ID 报错', () async {
    final created = await service.create(hospId: '1', roleCode: 'R001', roleName: '系统管理员');
    final role = await service.getById(created.id);
    expect(role.roleName, '系统管理员');

    await expectLater(
      service.getById('999'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('update：改名称、清空备注；与自身同名不算重复', () async {
    final created = await service.create(hospId: '1', roleCode: 'R001', roleName: '系统管理员', remark: '旧备注');
    final updated = await service.update(created.id, {
      'roleName': '系统管理员',
      'remark': null,
    });
    expect(updated.roleName, '系统管理员');
    expect(updated.remark, isNull);
    // UPDATE_TIME 已写入
    final row = await db.query('SELECT UPDATE_TIME FROM SYS_ROLE WHERE ID = ?', [int.parse(created.id)]);
    expect(row.rows.first[0], isNotNull);
  });

  test('update：归属不可改 / 必填列置空 / 同医院重名 / 未知字段均报错', () async {
    final created = await service.create(hospId: '1', roleCode: 'R001', roleName: '系统管理员');
    await service.create(hospId: '1', roleCode: 'R002', roleName: '医生');
    await expectLater(
      service.update(created.id, {'hospId': '2'}),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
    await expectLater(
      service.update(created.id, {'roleName': null}),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('角色名称不能为空'))),
    );
    await expectLater(
      service.update(created.id, {'roleName': '医生'}),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('角色名称已存在'))),
    );
    await expectLater(
      service.update(created.id, {'id': '2'}),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('savePermissions：全量覆盖保存与查询；去重；空列表清空', () async {
    final role = await service.create(hospId: '1', roleCode: 'R001', roleName: '系统管理员');
    expect(await service.savePermissions(role.id, ['1', '2', '2']), 2);
    expect(await service.listPermissionMenuIds(role.id), ['1', '2']);

    // 覆盖保存：换成 2、3
    expect(await service.savePermissions(role.id, ['3', '2']), 2);
    expect(await service.listPermissionMenuIds(role.id), ['2', '3']);

    // 空列表清空权限
    expect(await service.savePermissions(role.id, []), 0);
    expect(await service.listPermissionMenuIds(role.id), isEmpty);
  });

  test('savePermissions：角色不存在 / 无效菜单 ID 报错', () async {
    final role = await service.create(hospId: '1', roleCode: 'R001', roleName: '系统管理员');
    await expectLater(
      service.savePermissions('999', ['1']),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.savePermissions(role.id, ['1', '99']),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('无效的菜单项目'))),
    );
    await expectLater(
      service.savePermissions(role.id, ['x']),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('permissionQuery：未授权角色返回空列表', () async {
    final role = await service.create(hospId: '1', roleCode: 'R001', roleName: '系统管理员');
    expect(await service.listPermissionMenuIds(role.id), isEmpty);
    await expectLater(
      service.listPermissionMenuIds('999'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('delete：删除角色连带清空权限关联；不存在报错', () async {
    final role = await service.create(hospId: '1', roleCode: 'R001', roleName: '系统管理员');
    await service.savePermissions(role.id, ['1', '2']);
    expect(await service.delete(role.id), 1);

    final remain = await db.query('SELECT COUNT(*) AS CNT FROM SYS_ROLE_PERMISSION');
    expect(remain.rowsAsMaps.first['CNT'], '0');
    await expectLater(
      service.delete(role.id),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });
}
