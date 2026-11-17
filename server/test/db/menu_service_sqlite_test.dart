import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/menu_service.dart';
import 'package:test/test.dart';

// 种子数据固定 UUID（任意 36 位字符串均可作 TEXT/CHAR(36) 主键值，固定值
// 便于跨行引用；按字符串序排好，保证「ORDER BY ID」类排序断言稳定）。
const menuSystemId = 'c0000000-0000-0000-0000-000000000001'; // M001 系统管理（顶级模块）
const menuHospitalId = 'c0000000-0000-0000-0000-000000000002'; // M002 医院管理（系统管理下级菜单）
const menuAddHospitalId = 'c0000000-0000-0000-0000-000000000003'; // M003 新增医院（医院管理下级操作）
const menuChildId = 'c0000000-0000-0000-0000-000000000004'; // M004 儿童管理（顶级模块）
const menuHiddenId = 'c0000000-0000-0000-0000-000000000005'; // M005 隐藏菜单（系统管理下级菜单）
const rolePermId = 'b0000000-0000-0000-0000-000000000007'; // 已授权角色
const roleEmptyId = 'b0000000-0000-0000-0000-000000000008'; // 未授权角色

/// 不存在的 ID 取值（UUID 主键不校验格式，任意非空未知取值统一走「不存在」）。
const unknownId = '99999999-9999-9999-9999-999999999999';

/// UUID v7 主键形态（36 位连字符形式）。
final _uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// 菜单管理服务单元测试（SQLite :memory:）：列表、详情、顶级/下级新增
/// 校验与 UUID 主键回读、类型与路由联动校验、字段级修改、删除与下级
/// 阻止。
void main() {
  late SqliteGateway db;
  late MenuService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    await db.executeDirect('''
CREATE TABLE SYS_MENU (
  ID TEXT PRIMARY KEY NOT NULL,
  PARENT_ID TEXT, -- 上级项目ID
  ITEM_CODE TEXT NOT NULL, -- 项目编码
  ITEM_NAME TEXT NOT NULL, -- 项目名称
  ITEM_TYPE TEXT NOT NULL, -- 项目类型：1-模块，2-菜单，3-操作
  MENU_ROUTE TEXT, -- 菜单路由
  MENU_ICON TEXT, -- 菜单图标
  VISIBLE TEXT NOT NULL -- 是否显示
)''');
    // 菜单：系统管理/儿童管理为顶级模块，医院管理挂系统管理下，新增医院挂医院管理下。
    Future<void> seedMenu(String id, String? parentId, String code, String name, String type, String? route, String? icon, String visible) async {
      await db.execute(
        'INSERT INTO SYS_MENU (ID, PARENT_ID, ITEM_CODE, ITEM_NAME, ITEM_TYPE, '
        'MENU_ROUTE, MENU_ICON, VISIBLE) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, parentId, code, name, type, route, icon, visible],
      );
    }

    await seedMenu(menuSystemId, null, 'M001', '系统管理', '1', null, 'settings_outlined', '1');
    await seedMenu(menuHospitalId, menuSystemId, 'M002', '医院管理', '2', '/system/hospital', 'local_hospital_outlined', '1');
    await seedMenu(menuAddHospitalId, menuHospitalId, 'M003', '新增医院', '3', null, null, '1');
    await seedMenu(menuChildId, null, 'M004', '儿童管理', '1', null, 'child_care', '1');
    service = MenuService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listAll：全量按上级项目、ID 排序', () async {
    final menus = await service.listAll();
    // SQLite 排序 NULL 在前：顶级（系统管理、儿童管理）先于下级（医院管理、新增医院），
    // 同级按 ID 字符串序（固定 UUID 种子 0001 < 0004）
    expect(menus.map((m) => m.id), [menuSystemId, menuChildId, menuHospitalId, menuAddHospitalId]);
    expect(menus.first.parentId, isNull);
    expect(menus[2].parentId, menuSystemId);
    expect(menus[2].menuRoute, '/system/hospital');
    expect(menus.last.itemType, MenuService.itemTypeAction);
  });

  test('getById：查详情；未知 ID 报不存在', () async {
    final menu = await service.getById(menuHospitalId);
    expect(menu.itemName, '医院管理');
    expect(menu.parentId, menuSystemId);
    expect(menu.itemType, '2');
    expect(menu.menuRoute, '/system/hospital');
    expect(menu.menuIcon, 'local_hospital_outlined');

    // UUID 主键不校验格式：任意非空未知取值统一走「不存在」（40001）
    await expectLater(
      service.getById(unknownId),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('create：顶级与下级均成功，返回新生成的 UUID 主键', () async {
    final top = await service.create(
      itemCode: 'M005',
      itemName: '智力测验',
      itemType: MenuService.itemTypeModule,
      visible: '1',
    );
    expect(top.id, matches(_uuidPattern));
    expect(top.parentId, isNull);
    expect(top.menuRoute, isNull);

    final child = await service.create(
      parentId: top.id,
      itemCode: 'M006',
      itemName: '瑞文测验',
      itemType: MenuService.itemTypeMenu,
      menuRoute: '/intelligence/raven',
      menuIcon: 'grid_on_outlined',
      visible: '1',
    );
    expect(child.id, matches(_uuidPattern));
    expect(child.id, isNot(top.id));
    expect(child.parentId, top.id);
    expect(child.itemType, MenuService.itemTypeMenu);
    expect(child.menuRoute, '/intelligence/raven');
  });

  test('create：各类型路由均可空（占位菜单可暂不配置路由）', () async {
    // 菜单类型不填路由也成功
    final menu = await service.create(
      itemCode: 'M0010',
      itemName: '占位菜单',
      itemType: MenuService.itemTypeMenu,
      visible: '1',
    );
    expect(menu.menuRoute, isNull);
    final action = await service.create(
      parentId: menuHospitalId,
      itemCode: 'M0011',
      itemName: '删除医院',
      itemType: MenuService.itemTypeAction,
      visible: '1',
    );
    expect(action.menuRoute, isNull);
  });

  test('create：类型非法 / 编码重复 / 必填缺失 / 超长 / 上级不存在均报错', () async {
    await expectLater(
      service.create(itemCode: 'M0021', itemName: '非法类型', itemType: '9', visible: '1'),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目类型应为'))),
    );
    await expectLater(
      service.create(itemCode: 'M001', itemName: '重码项目', itemType: MenuService.itemTypeModule, visible: '1'),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目编码已存在'))),
    );
    await expectLater(
      service.create(itemCode: '  ', itemName: '无编码', itemType: MenuService.itemTypeModule, visible: '1'),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目编码不能为空'))),
    );
    await expectLater(
      service.create(itemCode: 'M0022', itemName: ' ', itemType: MenuService.itemTypeModule, visible: '1'),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目名称不能为空'))),
    );
    await expectLater(
      service.create(itemCode: 'M' * 11, itemName: '超长编码', itemType: MenuService.itemTypeModule, visible: '1'),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('不能超过'))),
    );
    await expectLater(
      service.create(
        parentId: unknownId,
        itemCode: 'M0023',
        itemName: '孤儿项目',
        itemType: MenuService.itemTypeMenu,
        menuRoute: '/x',
        visible: '1',
      ),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('上级项目不存在'))),
    );
    await expectLater(
      service.create(
        itemCode: 'M0024',
        itemName: '未知上级',
        parentId: 'x',
        itemType: MenuService.itemTypeAction,
        visible: '1',
      ),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('上级项目不存在'))),
    );
  });

  test('update：改名称、清空可空列、改编码', () async {
    final updated = await service.update(menuHospitalId, {
      'itemName': '医院信息管理',
      'menuIcon': null,
      'itemCode': 'M002X',
    });
    expect(updated.itemName, '医院信息管理');
    expect(updated.menuIcon, isNull);
    expect(updated.itemCode, 'M002X');
    // 菜单类型原有路由未随本次修改变化
    expect(updated.menuRoute, '/system/hospital');
  });

  test('update：与自身同编码不算重复', () async {
    final ok = await service.update(menuSystemId, {'itemCode': 'M001', 'itemName': '系统管理'});
    expect(ok.itemCode, 'M001');
  });

  test('update：类型与路由互不联动（路由可随时填、改、清空）', () async {
    // 模块改成菜单类型但不提供路由 → 成功（路由可选）
    final toMenu = await service.update(menuSystemId, {'itemType': MenuService.itemTypeMenu});
    expect(toMenu.itemType, MenuService.itemTypeMenu);
    expect(toMenu.menuRoute, isNull);
    // 菜单类型清空路由 → 成功
    final cleared = await service.update(menuHospitalId, {'menuRoute': null});
    expect(cleared.itemType, MenuService.itemTypeMenu);
    expect(cleared.menuRoute, isNull);
    // 补路由 → 成功
    final routed = await service.update(menuHospitalId, {'menuRoute': '/hospital'});
    expect(routed.menuRoute, '/hospital');
  });

  test('update：上级不可改 / 必填列置空 / 未知字段 / 类型非法均报错', () async {
    await expectLater(
      service.update(menuSystemId, {'parentId': menuHospitalId}),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
    await expectLater(
      service.update(menuSystemId, {'itemCode': null}),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目编码不能为空'))),
    );
    await expectLater(
      service.update(menuSystemId, {'id': menuHospitalId}),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
    await expectLater(
      service.update(menuSystemId, {'itemType': 'x'}),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目类型应为'))),
    );
  });

  test('delete：删除成功；不存在报错', () async {
    expect(await service.delete(menuChildId), 1);
    final remain = await db.query('SELECT ID FROM SYS_MENU ORDER BY ID');
    expect(remain.rows.expand((r) => r), [menuSystemId, menuHospitalId, menuAddHospitalId]);

    await expectLater(
      service.delete(menuChildId),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('delete：存在下级项目时阻止删除', () async {
    await expectLater(
      service.delete(menuHospitalId),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', '请先删除下级项目后，再删除该项目')),
    );
    // 先删下级新增医院再删医院管理即可成功
    expect(await service.delete(menuAddHospitalId), 1);
    expect(await service.delete(menuHospitalId), 1);
  });

  test('listRoleAll：返回角色已授权的模块/菜单（操作类与未授权排除，隐藏项目按设计下发）', () async {
    await db.executeDirect('''
CREATE TABLE SYS_ROLE_PERMISSION (
  ROLE_ID TEXT NOT NULL, -- 角色ID
  MENU_ID TEXT NOT NULL, -- 菜单ID
  PRIMARY KEY (ROLE_ID, MENU_ID)
)''');
    // 追加一个隐藏菜单（挂系统管理下）：VISIBLE 不参与服务端过滤，
    // 隐藏项目有意随登录下发（客户端按 visible 决定展示形态）
    await db.execute(
      'INSERT INTO SYS_MENU (ID, PARENT_ID, ITEM_CODE, ITEM_NAME, ITEM_TYPE, '
      'MENU_ROUTE, MENU_ICON, VISIBLE) '
      "VALUES (?, ?, 'M005', '隐藏菜单', '2', '/system/hidden', null, '0')",
      [menuHiddenId, menuSystemId],
    );
    // 已授权角色：系统管理、医院管理、新增医院、隐藏菜单（儿童管理未授权）
    for (final menuId in [menuSystemId, menuHospitalId, menuAddHospitalId, menuHiddenId]) {
      await db.execute(
        'INSERT INTO SYS_ROLE_PERMISSION (ROLE_ID, MENU_ID) VALUES (?, ?)',
        [rolePermId, menuId],
      );
    }

    // 系统管理、医院管理、隐藏菜单下发（按 ITEM_CODE 排序）；新增医院
    // （操作类型）、儿童管理（未授权）不下发
    final menus = await service.listRoleAll(rolePermId);
    expect(menus.map((m) => m.id), [menuSystemId, menuHospitalId, menuHiddenId]);
    expect(menus.map((m) => m.itemType), ['1', '2', '2']);
    expect(menus.last.menuRoute, '/system/hidden');
    expect(menus.last.visible, '0', reason: 'VISIBLE 原样下发供客户端处理');

    // 未授权角色返回空列表；角色 ID 不校验格式，未知取值同样返回空列表
    expect(await service.listRoleAll(roleEmptyId), isEmpty);
    expect(await service.listRoleAll('abc'), isEmpty);
  });

  test('listRoleOperationCodes：返回角色已授权的操作类编码集合（模块/菜单除外）', () async {
    await db.executeDirect('''
CREATE TABLE SYS_ROLE_PERMISSION (
  ROLE_ID TEXT NOT NULL, -- 角色ID
  MENU_ID TEXT NOT NULL, -- 菜单ID
  PRIMARY KEY (ROLE_ID, MENU_ID)
)''');
    // 已授权角色：系统管理、医院管理、新增医院——仅操作类下发编码
    for (final menuId in [menuSystemId, menuHospitalId, menuAddHospitalId]) {
      await db.execute(
        'INSERT INTO SYS_ROLE_PERMISSION (ROLE_ID, MENU_ID) VALUES (?, ?)',
        [rolePermId, menuId],
      );
    }
    // 未授权角色仅授权医院管理（非操作类）

    expect(await service.listRoleOperationCodes(rolePermId), {'M003'});
    expect(await service.listRoleOperationCodes(roleEmptyId), isEmpty);
    // 角色 ID 不校验格式，未知取值无关联权限返回空集合
    expect(await service.listRoleOperationCodes('abc'), isEmpty);
  });
}
