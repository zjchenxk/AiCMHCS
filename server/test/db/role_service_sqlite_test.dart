import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/role_service.dart';
import 'package:test/test.dart';

// 种子数据固定 UUID（任意 36 位字符串均可作 TEXT/CHAR(36) 主键值，固定值
// 便于跨行引用；按字符串序排好，保证「ORDER BY ID」类排序断言稳定）。
const hosp1Id = 'a0000000-0000-0000-0000-000000000001'; // 示例人民医院
const hosp2Id = 'a0000000-0000-0000-0000-000000000002'; // 儿童心理分院
const menu1Id = 'c0000000-0000-0000-0000-000000000001'; // 顶级模块
const menu2Id = 'c0000000-0000-0000-0000-000000000002'; // 挂模块 menu1Id 下
const menu3Id = 'c0000000-0000-0000-0000-000000000003'; // 挂菜单 menu2Id 下

/// 不存在的 ID 取值（UUID 主键不校验格式，任意非空未知取值统一走「不存在」）。
const unknownId = '99999999-9999-9999-9999-999999999999';

/// UUID v7 主键形态（36 位连字符形式）。
final _uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// 角色管理服务单元测试（SQLite :memory:）：列表、详情、新增校验与
/// UUID 主键回读、字段级修改、删除连带清权限与用户角色关联、菜单权限
/// 全量保存与查询。
void main() {
  late SqliteGateway db;
  late RoleService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    await db.executeDirect('''
CREATE TABLE SYS_HOSPITAL (
  ID TEXT PRIMARY KEY NOT NULL,
  PARENT_ID TEXT,
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
  ID TEXT PRIMARY KEY NOT NULL,
  PARENT_ID TEXT, -- 上级项目ID
  ITEM_CODE TEXT NOT NULL, -- 项目编码
  ITEM_NAME TEXT NOT NULL, -- 项目名称
  ITEM_TYPE TEXT NOT NULL, -- 项目类型：1-模块，2-菜单，3-操作
  MENU_ROUTE TEXT, -- 菜单路由
  MENU_ICON TEXT -- 菜单图标
)''');
    await db.executeDirect('''
CREATE TABLE SYS_ROLE (
  ID TEXT PRIMARY KEY NOT NULL,
  ROLE_CODE TEXT NOT NULL, -- 角色编码
  ROLE_NAME TEXT NOT NULL, -- 角色名称
  REMARK TEXT, -- 备注
  HOSP_ID TEXT NOT NULL, -- 所属医院ID
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 更新时间
)''');
    await db.executeDirect('''
CREATE TABLE SYS_ROLE_PERMISSION (
  ROLE_ID TEXT NOT NULL, -- 角色ID
  MENU_ID TEXT NOT NULL, -- 菜单ID
  PRIMARY KEY (ROLE_ID, MENU_ID)
)''');
    await db.executeDirect('''
CREATE TABLE SYS_USER_ROLE (
  USER_ID TEXT NOT NULL, -- 用户ID
  ROLE_ID TEXT NOT NULL, -- 角色ID
  DEPT_ID TEXT NOT NULL, -- 科室ID（v18 起三元复合主键）
  PRIMARY KEY (USER_ID, ROLE_ID, DEPT_ID)
)''');
    // 医院：示例人民医院、儿童心理分院。
    Future<void> seedHospital(String id, String name) async {
      await db.execute(
        'INSERT INTO SYS_HOSPITAL (ID, PARENT_ID, CODE, NAME, PROVINCE, CITY, '
        'ADDRESS, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, null, 'H00$id', name, '浙江省', '杭州市', '示例路1号', '2026-01-01 00:00:00'],
      );
    }

    await seedHospital(hosp1Id, '示例人民医院');
    await seedHospital(hosp2Id, '儿童心理分院');
    // 菜单：顶级模块、其下级菜单、菜单的下级操作。
    Future<void> seedMenu(String id, String? parentId, String code) async {
      await db.execute(
        'INSERT INTO SYS_MENU (ID, PARENT_ID, ITEM_CODE, ITEM_NAME, ITEM_TYPE) '
        'VALUES (?, ?, ?, ?, ?)',
        [id, parentId, code, '项目$code', '1'],
      );
    }

    await seedMenu(menu1Id, null, 'M001');
    await seedMenu(menu2Id, menu1Id, 'M002');
    await seedMenu(menu3Id, menu2Id, 'M003');
    service = RoleService(db);
  });

  tearDown(() {
    db.close();
  });

  test('create：成功生成 UUID 主键并回读；备注可空', () async {
    final role = await service.create(
      hospId: hosp1Id,
      roleCode: 'R001',
      roleName: '系统管理员',
    );
    expect(role.id, matches(_uuidPattern));
    expect(role.hospId, hosp1Id);
    expect(role.remark, isNull);
  });

  test('create：不同医院允许同编码/同名称（按医院隔离判重）', () async {
    final first = await service.create(hospId: hosp1Id, roleCode: 'R001', roleName: '医生');
    final other = await service.create(hospId: hosp2Id, roleCode: 'R001', roleName: '医生');
    expect(other.id, matches(_uuidPattern));
    expect(other.id, isNot(first.id));
    expect(other.hospId, hosp2Id);
  });

  test('create：医院不存在 / 同医院编码或名称重复 / 必填缺失 / 超长均报错', () async {
    await service.create(hospId: hosp1Id, roleCode: 'R001', roleName: '系统管理员');
    await expectLater(
      service.create(hospId: unknownId, roleCode: 'R002', roleName: '医生'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('所属医院不存在'))),
    );
    await expectLater(
      service.create(hospId: hosp1Id, roleCode: 'R001', roleName: '其他角色'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('角色编码已存在'))),
    );
    await expectLater(
      service.create(hospId: hosp1Id, roleCode: 'R002', roleName: '系统管理员'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('角色名称已存在'))),
    );
    await expectLater(
      service.create(hospId: hosp1Id, roleCode: ' ', roleName: '无编码'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('角色编码不能为空'))),
    );
    await expectLater(
      service.create(hospId: hosp1Id, roleCode: 'R' * 11, roleName: '超长编码'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不能超过'))),
    );
  });

  test('listByHospital：仅返回指定医院的角色，按创建顺序', () async {
    await service.create(hospId: hosp1Id, roleCode: 'R001', roleName: '系统管理员');
    // newUuid() 带同毫秒单调计数器（字符串序=生成序），此延时仅为
    // 防御性保险，不依赖它保证排序
    await service.create(hospId: hosp1Id, roleCode: 'R002', roleName: '医生', remark: '临床');
    await service.create(hospId: hosp2Id, roleCode: 'R003', roleName: '护士');
    final roles = await service.listByHospital(hosp1Id);
    expect(roles.map((r) => r.roleCode), ['R001', 'R002']);
    expect(roles.last.remark, '临床');
  });

  test('getById：查详情；未知 ID 报不存在', () async {
    final created = await service.create(hospId: hosp1Id, roleCode: 'R001', roleName: '系统管理员');
    final role = await service.getById(created.id);
    expect(role.roleName, '系统管理员');

    // UUID 主键不校验格式：任意非空未知取值统一走「不存在」（40001）
    await expectLater(
      service.getById(unknownId),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('update：改名称、清空备注；与自身同名不算重复', () async {
    final created = await service.create(hospId: hosp1Id, roleCode: 'R001', roleName: '系统管理员', remark: '旧备注');
    final updated = await service.update(created.id, {
      'roleName': '系统管理员',
      'remark': null,
    });
    expect(updated.roleName, '系统管理员');
    expect(updated.remark, isNull);
    // UPDATE_TIME 已写入
    final row = await db.query('SELECT UPDATE_TIME FROM SYS_ROLE WHERE ID = ?', [created.id]);
    expect(row.rows.first[0], isNotNull);
  });

  test('update：归属不可改 / 必填列置空 / 同医院重名 / 未知字段均报错', () async {
    final created = await service.create(hospId: hosp1Id, roleCode: 'R001', roleName: '系统管理员');
    await service.create(hospId: hosp1Id, roleCode: 'R002', roleName: '医生');
    await expectLater(
      service.update(created.id, {'hospId': hosp2Id}),
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
      service.update(created.id, {'id': hosp2Id}),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('savePermissions：全量覆盖保存与查询；去重；空列表清空', () async {
    final role = await service.create(hospId: hosp1Id, roleCode: 'R001', roleName: '系统管理员');
    expect(await service.savePermissions(role.id, [menu1Id, menu2Id, menu2Id]), 2);
    expect(await service.listPermissionMenuIds(role.id), [menu1Id, menu2Id]);

    // 覆盖保存：换成 menu3Id、menu2Id（按 MENU_ID 升序返回）
    expect(await service.savePermissions(role.id, [menu3Id, menu2Id]), 2);
    expect(await service.listPermissionMenuIds(role.id), [menu2Id, menu3Id]);

    // 空列表清空权限
    expect(await service.savePermissions(role.id, []), 0);
    expect(await service.listPermissionMenuIds(role.id), isEmpty);
  });

  test('savePermissions：角色不存在 / 无效菜单 ID 报错', () async {
    final role = await service.create(hospId: hosp1Id, roleCode: 'R001', roleName: '系统管理员');
    await expectLater(
      service.savePermissions(unknownId, [menu1Id]),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.savePermissions(role.id, [menu1Id, unknownId]),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('无效的菜单项目'))),
    );
    // 菜单 ID 不校验格式：非空未知取值同样走「无效的菜单项目」
    await expectLater(
      service.savePermissions(role.id, ['x']),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('无效的菜单项目'))),
    );
  });

  test('permissionQuery：未授权角色返回空列表', () async {
    final role = await service.create(hospId: hosp1Id, roleCode: 'R001', roleName: '系统管理员');
    expect(await service.listPermissionMenuIds(role.id), isEmpty);
    await expectLater(
      service.listPermissionMenuIds(unknownId),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('delete：删除角色连带清空权限与用户角色关联；不存在报错', () async {
    final role = await service.create(hospId: hosp1Id, roleCode: 'R001', roleName: '系统管理员');
    await service.savePermissions(role.id, [menu1Id, menu2Id]);
    // 种子用户角色关联（含科室维度：同一用户两行不同科室）
    Future<void> seedUserRole(String deptId) => db.execute(
      'INSERT INTO SYS_USER_ROLE (USER_ID, ROLE_ID, DEPT_ID) VALUES (?, ?, ?)',
      ['u0000001', role.id, deptId],
    );

    await seedUserRole('d0000001');
    await seedUserRole('d0000002');
    expect(await service.delete(role.id), 1);

    final remainPerm = await db.query('SELECT COUNT(*) AS CNT FROM SYS_ROLE_PERMISSION');
    expect(remainPerm.rowsAsMaps.first['CNT'], '0');
    final remainUserRole = await db.query('SELECT COUNT(*) AS CNT FROM SYS_USER_ROLE');
    expect(remainUserRole.rowsAsMaps.first['CNT'], '0');
    await expectLater(
      service.delete(role.id),
      throwsA(isA<RoleException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });
}
