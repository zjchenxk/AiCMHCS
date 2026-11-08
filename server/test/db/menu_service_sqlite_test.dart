import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/menu_service.dart';
import 'package:test/test.dart';

/// 菜单管理服务单元测试（SQLite :memory:）：列表、详情、顶级/下级新增
/// 校验与 ITEM_CODE 回读、类型与路由联动校验、字段级修改、删除与下级
/// 阻止。
void main() {
  late SqliteGateway db;
  late MenuService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
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
    // 菜单：1/4 为顶级模块，2 为 1 的下级菜单，3 为 2 的下级操作。
    Future<void> seedMenu(
      int id,
      int? parentId,
      String code,
      String name,
      String type,
      String? route,
      String? icon,
    ) async {
      await db.execute(
        'INSERT INTO SYS_MENU (ID, PARENT_ID, ITEM_CODE, ITEM_NAME, ITEM_TYPE, '
        'MENU_ROUTE, MENU_ICON) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, parentId, code, name, type, route, icon],
      );
    }

    await seedMenu(1, null, 'M001', '系统管理', '1', null, 'settings_outlined');
    await seedMenu(2, 1, 'M002', '医院管理', '2', '/system/hospital', 'local_hospital_outlined');
    await seedMenu(3, 2, 'M003', '新增医院', '3', null, null);
    await seedMenu(4, null, 'M004', '儿童管理', '1', null, 'child_care');
    service = MenuService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listAll：全量按上级项目、ID 排序', () async {
    final menus = await service.listAll();
    // SQLite 排序 NULL 在前：顶级（1、4）先于下级（2、3）
    expect(menus.map((m) => m.id), ['1', '4', '2', '3']);
    expect(menus.first.parentId, isNull);
    expect(menus[2].parentId, '1');
    expect(menus[2].menuRoute, '/system/hospital');
    expect(menus.last.itemType, MenuService.itemTypeAction);
  });

  test('getById：查详情；不存在与非法 ID 报错', () async {
    final menu = await service.getById('2');
    expect(menu.itemName, '医院管理');
    expect(menu.parentId, '1');
    expect(menu.itemType, '2');
    expect(menu.menuRoute, '/system/hospital');
    expect(menu.menuIcon, 'local_hospital_outlined');

    await expectLater(
      service.getById('999'),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('create：顶级与下级均成功，自增 ID 经 ITEM_CODE 回读', () async {
    final top = await service.create(
      itemCode: 'M005',
      itemName: '智力测验',
      itemType: MenuService.itemTypeModule,
    );
    expect(top.id, '5');
    expect(top.parentId, isNull);
    expect(top.menuRoute, isNull);

    final child = await service.create(
      parentId: '5',
      itemCode: 'M006',
      itemName: '瑞文测验',
      itemType: MenuService.itemTypeMenu,
      menuRoute: '/intelligence/raven',
      menuIcon: 'grid_on_outlined',
    );
    expect(child.id, '6');
    expect(child.parentId, '5');
    expect(child.itemType, MenuService.itemTypeMenu);
    expect(child.menuRoute, '/intelligence/raven');
  });

  test('create：各类型路由均可空（占位菜单可暂不配置路由）', () async {
    // 菜单类型不填路由也成功
    final menu = await service.create(
      itemCode: 'M0010',
      itemName: '占位菜单',
      itemType: MenuService.itemTypeMenu,
    );
    expect(menu.menuRoute, isNull);
    final action = await service.create(
      parentId: '2',
      itemCode: 'M0011',
      itemName: '删除医院',
      itemType: MenuService.itemTypeAction,
    );
    expect(action.menuRoute, isNull);
  });

  test('create：类型非法 / 编码重复 / 必填缺失 / 超长 / 上级不存在均报错', () async {
    await expectLater(
      service.create(itemCode: 'M0021', itemName: '非法类型', itemType: '9'),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目类型应为'))),
    );
    await expectLater(
      service.create(itemCode: 'M001', itemName: '重码项目', itemType: MenuService.itemTypeModule),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目编码已存在'))),
    );
    await expectLater(
      service.create(itemCode: '  ', itemName: '无编码', itemType: MenuService.itemTypeModule),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目编码不能为空'))),
    );
    await expectLater(
      service.create(itemCode: 'M0022', itemName: ' ', itemType: MenuService.itemTypeModule),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目名称不能为空'))),
    );
    await expectLater(
      service.create(itemCode: 'M' * 11, itemName: '超长编码', itemType: MenuService.itemTypeModule),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('不能超过'))),
    );
    await expectLater(
      service.create(
        parentId: '999',
        itemCode: 'M0023',
        itemName: '孤儿项目',
        itemType: MenuService.itemTypeMenu,
        menuRoute: '/x',
      ),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('上级项目不存在'))),
    );
    await expectLater(
      service.create(
        itemCode: 'M0024',
        itemName: '非法上级',
        parentId: 'x',
        itemType: MenuService.itemTypeAction,
      ),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('update：改名称、清空可空列、改编码', () async {
    final updated = await service.update('2', {
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
    final ok = await service.update('1', {'itemCode': 'M001', 'itemName': '系统管理'});
    expect(ok.itemCode, 'M001');
  });

  test('update：类型与路由互不联动（路由可随时填、改、清空）', () async {
    // 模块改成菜单类型但不提供路由 → 成功（路由可选）
    final toMenu = await service.update('1', {'itemType': MenuService.itemTypeMenu});
    expect(toMenu.itemType, MenuService.itemTypeMenu);
    expect(toMenu.menuRoute, isNull);
    // 菜单类型清空路由 → 成功
    final cleared = await service.update('2', {'menuRoute': null});
    expect(cleared.itemType, MenuService.itemTypeMenu);
    expect(cleared.menuRoute, isNull);
    // 补路由 → 成功
    final routed = await service.update('2', {'menuRoute': '/hospital'});
    expect(routed.menuRoute, '/hospital');
  });

  test('update：上级不可改 / 必填列置空 / 未知字段 / 类型非法均报错', () async {
    await expectLater(
      service.update('1', {'parentId': '2'}),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
    await expectLater(
      service.update('1', {'itemCode': null}),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目编码不能为空'))),
    );
    await expectLater(
      service.update('1', {'id': '2'}),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
    await expectLater(
      service.update('1', {'itemType': 'x'}),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('项目类型应为'))),
    );
  });

  test('delete：删除成功；不存在报错', () async {
    expect(await service.delete('4'), 1);
    final remain = await db.query('SELECT ID FROM SYS_MENU ORDER BY ID');
    expect(remain.rows.expand((r) => r), ['1', '2', '3']);

    await expectLater(
      service.delete('4'),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('delete：存在下级项目时阻止删除', () async {
    await expectLater(
      service.delete('2'),
      throwsA(isA<MenuException>().having((e) => e.message, 'message', '请先删除下级项目后，再删除该项目')),
    );
    // 先删下级 3 再删 2 即可成功
    expect(await service.delete('3'), 1);
    expect(await service.delete('2'), 1);
  });
}
