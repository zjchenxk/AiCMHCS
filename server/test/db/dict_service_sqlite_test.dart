import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/dict_service.dart';
import 'package:test/test.dart';

// 种子数据固定 UUID（任意 36 位字符串均可作 TEXT/CHAR(36) 主键值，固定值
// 便于跨行引用；按字符串序排好，保证「ORDER BY ID」类排序断言稳定）。
const hosp1Id = 'a0000000-0000-0000-0000-000000000001'; // 示例人民医院
const hosp2Id = 'a0000000-0000-0000-0000-000000000002'; // 示例儿童医院
const creator1Id = 'b0000000-0000-0000-0000-000000000009'; // 张三
const creator2Id = 'b0000000-0000-0000-0000-000000000008'; // 李四
const dict1Id = 'e0000000-0000-0000-0000-000000000001'; // D001 性别（医院 1 顶级）
const dict2Id = 'e0000000-0000-0000-0000-000000000002'; // D002 学历（医院 1，挂性别下）
const dict3Id = 'e0000000-0000-0000-0000-000000000003'; // D001 血型（医院 2 顶级，编码跨院重复）
const item1Id = 'f0000000-0000-0000-0000-000000000001'; // M 男（性别字典）
const item2Id = 'f0000000-0000-0000-0000-000000000002'; // F 女（性别字典，默认项）
const item3Id = 'f0000000-0000-0000-0000-000000000003'; // P 小学（学历字典）

/// 不存在的 ID 取值（UUID 主键不校验格式，任意非空未知取值统一走「不存在」）。
const unknownId = '99999999-9999-9999-9999-999999999999';

/// UUID v7 主键形态（36 位连字符形式）。
final _uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// 数据字典管理服务单元测试（SQLite :memory:）：医院隔离列表、详情、
/// 顶级/下级字典新增与 UUID 主键回读、同医院编码唯一、数据项新增与同
/// 字典编码唯一、默认项互斥、字段级修改、删除与下级/数据项阻止。
void main() {
  late SqliteGateway db;
  late DictService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    await db.executeDirect('''
CREATE TABLE BASE_DICT (
  ID TEXT PRIMARY KEY NOT NULL,
  PARENT_ID TEXT, -- 上级字典ID
  DICT_CODE TEXT NOT NULL, -- 字典编码
  DICT_NAME TEXT NOT NULL, -- 字典名称
  DISPLAY_ORDER INTEGER, -- 显示顺序
  CREATOR_ID TEXT NOT NULL, -- 创建人ID
  CREATOR_NAME TEXT NOT NULL, -- 创建人姓名
  HOSP_ID TEXT NOT NULL, -- 医院ID
  HOSP_NAME TEXT NOT NULL, -- 医院名称
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 更新时间
)''');
    await db.executeDirect('''
CREATE TABLE BASE_DICT_ITEM (
  ID TEXT PRIMARY KEY NOT NULL,
  DICT_ID TEXT NOT NULL, -- 字典ID
  ITEM_CODE TEXT NOT NULL, -- 项目编码
  ITEM_VALUE TEXT NOT NULL, -- 项目值
  DISPLAY_ORDER INTEGER, -- 显示顺序
  IS_DEFAULT TEXT NOT NULL, -- 是否默认值（1-是，0-否）
  CREATOR_ID TEXT NOT NULL, -- 创建人ID
  CREATOR_NAME TEXT NOT NULL, -- 创建人姓名
  HOSP_ID TEXT NOT NULL, -- 医院ID
  HOSP_NAME TEXT NOT NULL, -- 医院名称
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 更新时间
)''');
    // 字典：性别/学历属医院 1（学历挂性别下），血型属医院 2（编码与性别
    // 相同——同医院内唯一、跨医院不冲突）；数据项男/女属性别字典（女为
    // 默认项），小学属学历字典。
    Future<void> seedDict(String id, String? parentId, String code, String name, int? order, String hospId, String hospName, String creatorName, String creatorId) async {
      await db.execute(
        'INSERT INTO BASE_DICT (ID, PARENT_ID, DICT_CODE, DICT_NAME, DISPLAY_ORDER, '
        'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, parentId, code, name, order, creatorId, creatorName, hospId, hospName, '2026-11-13 10:00:00'],
      );
    }

    Future<void> seedItem(String id, String dictId, String code, String value, int? order, String isDefault, String hospId, String hospName, String creatorName, String creatorId) async {
      await db.execute(
        'INSERT INTO BASE_DICT_ITEM (ID, DICT_ID, ITEM_CODE, ITEM_VALUE, DISPLAY_ORDER, '
        'IS_DEFAULT, CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, dictId, code, value, order, isDefault, creatorId, creatorName, hospId, hospName, '2026-11-13 10:00:00'],
      );
    }

    await seedDict(dict1Id, null, 'D001', '性别', 1, hosp1Id, '示例人民医院', '张三', creator1Id);
    await seedDict(dict2Id, dict1Id, 'D002', '学历', 2, hosp1Id, '示例人民医院', '张三', creator1Id);
    await seedDict(dict3Id, null, 'D001', '血型', null, hosp2Id, '示例儿童医院', '李四', creator2Id);
    await seedItem(item1Id, dict1Id, 'M', '男', 1, '0', hosp1Id, '示例人民医院', '张三', creator1Id);
    await seedItem(item2Id, dict1Id, 'F', '女', 2, '1', hosp1Id, '示例人民医院', '张三', creator1Id);
    await seedItem(item3Id, dict2Id, 'P', '小学', null, '0', hosp1Id, '示例人民医院', '张三', creator1Id);
    service = DictService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listByHospital：按医院隔离返回；hospId 为空返回空列表', () async {
    final hosp1 = await service.listByHospital(hosp1Id);
    expect(hosp1.map((d) => d.id), [dict1Id, dict2Id]);
    expect(hosp1.first.dictCode, 'D001');
    expect(hosp1.first.hospName, '示例人民医院');

    final hosp2 = await service.listByHospital(hosp2Id);
    expect(hosp2.map((d) => d.id), [dict3Id]);
    expect(hosp2.first.dictName, '血型');

    expect(await service.listByHospital(''), isEmpty);
    expect(await service.listByHospital('  '), isEmpty);
    // 医院 ID 不校验格式，未知取值查不到数据返回空列表
    expect(await service.listByHospital('abc'), isEmpty);
  });

  test('getById：查详情；未知 ID 报不存在', () async {
    final dict = await service.getById(dict2Id);
    expect(dict.dictCode, 'D002');
    expect(dict.parentId, dict1Id);
    expect(dict.displayOrder, '2');
    expect(dict.creatorName, '张三');

    // UUID 主键不校验格式：任意非空未知取值统一走「不存在」（40001）
    await expectLater(
      service.getById(unknownId),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('create：顶级与下级均成功，返回新生成的 UUID 主键', () async {
    final top = await service.create(
      dictCode: 'D003',
      dictName: '民族',
      hospId: hosp1Id,
      hospName: '示例人民医院',
      creatorId: creator1Id,
      creatorName: '张三',
      displayOrder: '3',
    );
    expect(top.id, matches(_uuidPattern));
    expect(top.parentId, isNull);
    expect(top.displayOrder, '3');
    expect(top.createTime, isNotNull);

    final child = await service.create(
      parentId: top.id,
      dictCode: 'D004',
      dictName: '民族细类',
      hospId: hosp1Id,
      hospName: '示例人民医院',
      creatorId: creator1Id,
      creatorName: '张三',
    );
    expect(child.id, matches(_uuidPattern));
    expect(child.id, isNot(top.id));
    expect(child.parentId, top.id);
    expect(child.displayOrder, isNull);
  });

  test('create：同码跨医院不冲突；同医院重码/上级跨院/上级不存在均报错', () async {
    // 医院 2 新建编码 D002（医院 1 已占用）→ 成功（唯一性按医院隔离）
    final otherHosp = await service.create(
      dictCode: 'D002',
      dictName: '学历',
      hospId: hosp2Id,
      hospName: '示例儿童医院',
      creatorId: creator2Id,
      creatorName: '李四',
    );
    expect(otherHosp.id, matches(_uuidPattern));

    // 医院 1 内重码 → 报错
    await expectLater(
      service.create(dictCode: 'D001', dictName: '重码字典', hospId: hosp1Id, hospName: '示例人民医院', creatorId: creator1Id, creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('该医院下字典编码已存在'))),
    );
    // 上级字典属其他医院 → 视为不存在（数据隔离）
    await expectLater(
      service.create(
        parentId: dict1Id,
        dictCode: 'D005',
        dictName: '跨院挂载',
        hospId: hosp2Id,
        hospName: '示例儿童医院',
        creatorId: creator2Id,
        creatorName: '李四',
      ),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('上级字典不存在'))),
    );
    // 上级不存在 / 未知取值 ID / 必填缺失 / 超长 / 显示顺序非法
    await expectLater(
      service.create(parentId: unknownId, dictCode: 'D006', dictName: '孤儿字典', hospId: hosp1Id, hospName: '示例人民医院', creatorId: creator1Id, creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('上级字典不存在'))),
    );
    await expectLater(
      service.create(parentId: 'x', dictCode: 'D007', dictName: '未知上级', hospId: hosp1Id, hospName: '示例人民医院', creatorId: creator1Id, creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('上级字典不存在'))),
    );
    await expectLater(
      service.create(dictCode: '  ', dictName: '无编码', hospId: hosp1Id, hospName: '示例人民医院', creatorId: creator1Id, creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('字典编码不能为空'))),
    );
    await expectLater(
      service.create(dictCode: 'D' * 11, dictName: '超长编码', hospId: hosp1Id, hospName: '示例人民医院', creatorId: creator1Id, creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不能超过'))),
    );
    await expectLater(
      service.create(dictCode: 'D008', dictName: '顺序非法', hospId: hosp1Id, hospName: '示例人民医院', creatorId: creator1Id, creatorName: '张三', displayOrder: 'x'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('显示顺序应为'))),
    );
    await expectLater(
      service.create(dictCode: 'D009', dictName: '顺序越界', hospId: hosp1Id, hospName: '示例人民医院', creatorId: creator1Id, creatorName: '张三', displayOrder: '32768'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('显示顺序应为'))),
    );
  });

  test('update：改名称/编码、清空显示顺序，更新时间落库', () async {
    final updated = await service.update(dict2Id, {
      'dictName': '学历层次',
      'displayOrder': null,
      'dictCode': 'D002X',
    });
    expect(updated.dictName, '学历层次');
    expect(updated.displayOrder, isNull);
    expect(updated.dictCode, 'D002X');
    expect(updated.updateTime, isNotNull);
    // 创建人与归属医院不随修改变化
    expect(updated.creatorName, '张三');
    expect(updated.hospId, hosp1Id);
  });

  test('update：与自身同码不算重复；重码/必填置空/未知字段均报错', () async {
    final ok = await service.update(dict1Id, {'dictCode': 'D001'});
    expect(ok.dictCode, 'D001');

    await expectLater(
      service.update(dict2Id, {'dictCode': 'D001'}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('该医院下字典编码已存在'))),
    );
    await expectLater(
      service.update(dict1Id, {'dictName': null}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('字典名称不能为空'))),
    );
    await expectLater(
      service.update(dict1Id, {'parentId': dict2Id}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
    await expectLater(
      service.update(dict1Id, {'hospId': hosp2Id}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('delete：叶子字典删除成功；下级字典与数据项均阻止删除', () async {
    // 性别字典有下级学历字典 → 阻止
    await expectLater(
      service.delete(dict1Id),
      throwsA(isA<DictException>().having((e) => e.message, 'message', '请先删除下级字典后，再删除该字典')),
    );
    // 学历字典有数据项小学 → 阻止
    await expectLater(
      service.delete(dict2Id),
      throwsA(isA<DictException>().having((e) => e.message, 'message', '该字典下存在数据项，请先删除全部数据项')),
    );
    // 逐层清空后即可删除
    expect(await service.deleteItem(item3Id), 1);
    expect(await service.delete(dict2Id), 1);
    expect(await service.deleteItem(item1Id), 1);
    expect(await service.deleteItem(item2Id), 1);
    expect(await service.delete(dict1Id), 1);

    await expectLater(
      service.delete(dict1Id),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('listItems：按字典返回数据项（创建顺序）；空字典返回空列表', () async {
    final items = await service.listItems(dict1Id);
    expect(items.map((i) => i.id), [item1Id, item2Id]);
    expect(items.map((i) => i.isDefault), ['0', '1']);
    expect(items.first.hospName, '示例人民医院');

    expect(await service.listItems(dict3Id), isEmpty);
    // 字典 ID 不校验格式，未知取值查不到数据返回空列表
    expect(await service.listItems('abc'), isEmpty);
  });

  test('createItem：成功并回读；isDefault 置默认时清字典内原默认位', () async {
    final item = await service.createItem(
      dictId: dict1Id,
      itemCode: 'U',
      itemValue: '未知',
      displayOrder: '3',
      isDefault: '1',
      creatorId: creator1Id,
      creatorName: '张三',
    );
    expect(item.id, matches(_uuidPattern));
    expect(item.dictId, dict1Id);
    expect(item.isDefault, '1');
    expect(item.hospId, hosp1Id, reason: '医院冗余列取自所属字典');
    expect(item.hospName, '示例人民医院');

    // 原默认项（女）被互斥清位
    final items = await service.listItems(dict1Id);
    final defaults = items.where((i) => i.isDefault == '1').toList();
    expect(defaults.map((i) => i.id), [item.id]);
  });

  test('createItem：同字典重码/跨字典同码/字典不存在/默认标记非法均校验', () async {
    // 同字典内重码 → 报错
    await expectLater(
      service.createItem(dictId: dict1Id, itemCode: 'M', itemValue: '重复编码', isDefault: '0', creatorId: creator1Id, creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('该字典下项目编码已存在'))),
    );
    // 不同字典同码 → 成功
    final otherDict = await service.createItem(dictId: dict2Id, itemCode: 'M', itemValue: '初中', isDefault: '0', creatorId: creator1Id, creatorName: '张三');
    expect(otherDict.id, matches(_uuidPattern));

    await expectLater(
      service.createItem(dictId: unknownId, itemCode: 'X', itemValue: '孤儿数据项', isDefault: '0', creatorId: creator1Id, creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('数据字典不存在'))),
    );
    await expectLater(
      service.createItem(dictId: dict1Id, itemCode: 'X', itemValue: '非法默认标记', isDefault: '2', creatorId: creator1Id, creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('是否默认值应为'))),
    );
    await expectLater(
      service.createItem(dictId: dict1Id, itemCode: 'X', itemValue: '  ', isDefault: '0', creatorId: creator1Id, creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('项目值不能为空'))),
    );
    await expectLater(
      service.createItem(dictId: dict1Id, itemCode: 'C' * 51, itemValue: '超长编码', isDefault: '0', creatorId: creator1Id, creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不能超过'))),
    );
  });

  test('updateItem：改编码/值/顺序；重码与未知字段报错', () async {
    final updated = await service.updateItem(item1Id, {'itemCode': 'MALE', 'itemValue': '男性', 'displayOrder': '10'});
    expect(updated.itemCode, 'MALE');
    expect(updated.itemValue, '男性');
    expect(updated.displayOrder, '10');
    expect(updated.updateTime, isNotNull);

    await expectLater(
      service.updateItem(item1Id, {'itemCode': 'F'}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('该字典下项目编码已存在'))),
    );
    await expectLater(
      service.updateItem(item1Id, {'isDefault': '1'}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('deleteItem：删除成功；不存在报错', () async {
    expect(await service.deleteItem(item2Id), 1);
    // 删除默认项后性别字典无默认项
    final items = await service.listItems(dict1Id);
    expect(items.where((i) => i.isDefault == '1'), isEmpty);

    await expectLater(
      service.deleteItem(item2Id),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('setItemDefault：互斥置位；已是默认项为空操作；不存在报错', () async {
    final item = await service.setItemDefault(item1Id);
    expect(item.isDefault, '1');
    // 原默认项（女）被清位
    final items = await service.listItems(dict1Id);
    expect(items.firstWhere((i) => i.id == item2Id).isDefault, '0');

    // 已是默认项 → 直接返回，不再写库
    final again = await service.setItemDefault(item1Id);
    expect(again.isDefault, '1');

    await expectLater(
      service.setItemDefault(unknownId),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });
}
