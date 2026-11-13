import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/dict_service.dart';
import 'package:test/test.dart';

/// 数据字典管理服务单元测试（SQLite :memory:）：医院隔离列表、详情、
/// 顶级/下级字典新增与「医院ID+字典编码」回读、同医院编码唯一、数据项
/// 新增与「字典ID+项目编码」回读、同字典编码唯一、默认项互斥、字段级
/// 修改、删除与下级/数据项阻止。
void main() {
  late SqliteGateway db;
  late DictService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    await db.executeDirect('''
CREATE TABLE BASE_DICT (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
  PARENT_ID INTEGER, -- 上级字典ID
  DICT_CODE TEXT NOT NULL, -- 字典编码
  DICT_NAME TEXT NOT NULL, -- 字典名称
  DISPLAY_ORDER INTEGER, -- 显示顺序
  CREATOR_ID INTEGER NOT NULL, -- 创建人ID
  CREATOR_NAME TEXT NOT NULL, -- 创建人姓名
  HOSP_ID INTEGER NOT NULL, -- 医院ID
  HOSP_NAME TEXT NOT NULL, -- 医院名称
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 更新时间
)''');
    await db.executeDirect('''
CREATE TABLE BASE_DICT_ITEM (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
  DICT_ID INTEGER NOT NULL, -- 字典ID
  ITEM_CODE TEXT NOT NULL, -- 项目编码
  ITEM_VALUE TEXT NOT NULL, -- 项目值
  DISPLAY_ORDER INTEGER, -- 显示顺序
  IS_DEFAULT TEXT NOT NULL, -- 是否默认值（1-是，0-否）
  CREATOR_ID INTEGER NOT NULL, -- 创建人ID
  CREATOR_NAME TEXT NOT NULL, -- 创建人姓名
  HOSP_ID INTEGER NOT NULL, -- 医院ID
  HOSP_NAME TEXT NOT NULL, -- 医院名称
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 更新时间
)''');
    // 字典：1/2 属医院 1（2 挂 1 下），3 属医院 2（编码与 1 相同——
    // 同医院内唯一、跨医院不冲突）；数据项 1/2 属字典 1（2 为默认项），
    // 3 属字典 2。
    Future<void> seedDict(int id, int? parentId, String code, String name, int? order, int hospId, String hospName, String creatorName) async {
      await db.execute(
        'INSERT INTO BASE_DICT (ID, PARENT_ID, DICT_CODE, DICT_NAME, DISPLAY_ORDER, '
        'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?, 9, ?, ?, ?, ?)',
        [id, parentId, code, name, order, creatorName, hospId, hospName, '2026-11-13 10:00:00'],
      );
    }

    Future<void> seedItem(int id, int dictId, String code, String value, int? order, String isDefault, int hospId, String hospName, String creatorName) async {
      await db.execute(
        'INSERT INTO BASE_DICT_ITEM (ID, DICT_ID, ITEM_CODE, ITEM_VALUE, DISPLAY_ORDER, '
        'IS_DEFAULT, CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?, ?, 9, ?, ?, ?, ?)',
        [id, dictId, code, value, order, isDefault, creatorName, hospId, hospName, '2026-11-13 10:00:00'],
      );
    }

    await seedDict(1, null, 'D001', '性别', 1, 1, '示例人民医院', '张三');
    await seedDict(2, 1, 'D002', '学历', 2, 1, '示例人民医院', '张三');
    await seedDict(3, null, 'D001', '血型', null, 2, '示例儿童医院', '李四');
    await seedItem(1, 1, 'M', '男', 1, '0', 1, '示例人民医院', '张三');
    await seedItem(2, 1, 'F', '女', 2, '1', 1, '示例人民医院', '张三');
    await seedItem(3, 2, 'P', '小学', null, '0', 1, '示例人民医院', '张三');
    service = DictService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listByHospital：按医院隔离返回；hospId 为空返回空列表', () async {
    final hosp1 = await service.listByHospital('1');
    expect(hosp1.map((d) => d.id), ['1', '2']);
    expect(hosp1.first.dictCode, 'D001');
    expect(hosp1.first.hospName, '示例人民医院');

    final hosp2 = await service.listByHospital('2');
    expect(hosp2.map((d) => d.id), ['3']);
    expect(hosp2.first.dictName, '血型');

    expect(await service.listByHospital(''), isEmpty);
    expect(await service.listByHospital('  '), isEmpty);
    await expectLater(
      service.listByHospital('abc'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('getById：查详情；不存在与非法 ID 报错', () async {
    final dict = await service.getById('2');
    expect(dict.dictCode, 'D002');
    expect(dict.parentId, '1');
    expect(dict.displayOrder, '2');
    expect(dict.creatorName, '张三');

    await expectLater(
      service.getById('999'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('create：顶级与下级均成功，自增 ID 经「医院ID+字典编码」回读', () async {
    final top = await service.create(
      dictCode: 'D003',
      dictName: '民族',
      hospId: '1',
      hospName: '示例人民医院',
      creatorId: '9',
      creatorName: '张三',
      displayOrder: '3',
    );
    expect(top.id, '4');
    expect(top.parentId, isNull);
    expect(top.displayOrder, '3');
    expect(top.createTime, isNotNull);

    final child = await service.create(
      parentId: '4',
      dictCode: 'D004',
      dictName: '民族细类',
      hospId: '1',
      hospName: '示例人民医院',
      creatorId: '9',
      creatorName: '张三',
    );
    expect(child.id, '5');
    expect(child.parentId, '4');
    expect(child.displayOrder, isNull);
  });

  test('create：同码跨医院不冲突；同医院重码/上级跨院/上级不存在均报错', () async {
    // 医院 2 新建编码 D002（医院 1 已占用）→ 成功（唯一性按医院隔离）
    final otherHosp = await service.create(
      dictCode: 'D002',
      dictName: '学历',
      hospId: '2',
      hospName: '示例儿童医院',
      creatorId: '8',
      creatorName: '李四',
    );
    expect(otherHosp.id, '4');

    // 医院 1 内重码 → 报错
    await expectLater(
      service.create(dictCode: 'D001', dictName: '重码字典', hospId: '1', hospName: '示例人民医院', creatorId: '9', creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('该医院下字典编码已存在'))),
    );
    // 上级字典属其他医院 → 视为不存在（数据隔离）
    await expectLater(
      service.create(
        parentId: '1',
        dictCode: 'D005',
        dictName: '跨院挂载',
        hospId: '2',
        hospName: '示例儿童医院',
        creatorId: '8',
        creatorName: '李四',
      ),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('上级字典不存在'))),
    );
    // 上级不存在 / 非法 ID / 必填缺失 / 超长 / 显示顺序非法
    await expectLater(
      service.create(parentId: '999', dictCode: 'D006', dictName: '孤儿字典', hospId: '1', hospName: '示例人民医院', creatorId: '9', creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('上级字典不存在'))),
    );
    await expectLater(
      service.create(parentId: 'x', dictCode: 'D007', dictName: '非法上级', hospId: '1', hospName: '示例人民医院', creatorId: '9', creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
    await expectLater(
      service.create(dictCode: '  ', dictName: '无编码', hospId: '1', hospName: '示例人民医院', creatorId: '9', creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('字典编码不能为空'))),
    );
    await expectLater(
      service.create(dictCode: 'D' * 11, dictName: '超长编码', hospId: '1', hospName: '示例人民医院', creatorId: '9', creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不能超过'))),
    );
    await expectLater(
      service.create(dictCode: 'D008', dictName: '顺序非法', hospId: '1', hospName: '示例人民医院', creatorId: '9', creatorName: '张三', displayOrder: 'x'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('显示顺序应为'))),
    );
    await expectLater(
      service.create(dictCode: 'D009', dictName: '顺序越界', hospId: '1', hospName: '示例人民医院', creatorId: '9', creatorName: '张三', displayOrder: '32768'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('显示顺序应为'))),
    );
  });

  test('update：改名称/编码、清空显示顺序，更新时间落库', () async {
    final updated = await service.update('2', {
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
    expect(updated.hospId, '1');
  });

  test('update：与自身同码不算重复；重码/必填置空/未知字段均报错', () async {
    final ok = await service.update('1', {'dictCode': 'D001'});
    expect(ok.dictCode, 'D001');

    await expectLater(
      service.update('2', {'dictCode': 'D001'}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('该医院下字典编码已存在'))),
    );
    await expectLater(
      service.update('1', {'dictName': null}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('字典名称不能为空'))),
    );
    await expectLater(
      service.update('1', {'parentId': '2'}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
    await expectLater(
      service.update('1', {'hospId': '2'}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('delete：叶子字典删除成功；下级字典与数据项均阻止删除', () async {
    // 字典 1 有下级字典 2 → 阻止
    await expectLater(
      service.delete('1'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', '请先删除下级字典后，再删除该字典')),
    );
    // 字典 2 有数据项 3 → 阻止
    await expectLater(
      service.delete('2'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', '该字典下存在数据项，请先删除全部数据项')),
    );
    // 逐层清空后即可删除
    expect(await service.deleteItem('3'), 1);
    expect(await service.delete('2'), 1);
    expect(await service.deleteItem('1'), 1);
    expect(await service.deleteItem('2'), 1);
    expect(await service.delete('1'), 1);

    await expectLater(
      service.delete('1'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('listItems：按字典返回数据项（创建顺序）；空字典返回空列表', () async {
    final items = await service.listItems('1');
    expect(items.map((i) => i.id), ['1', '2']);
    expect(items.map((i) => i.isDefault), ['0', '1']);
    expect(items.first.hospName, '示例人民医院');

    expect(await service.listItems('3'), isEmpty);
    await expectLater(
      service.listItems('abc'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('createItem：成功并回读；isDefault 置默认时清字典内原默认位', () async {
    final item = await service.createItem(
      dictId: '1',
      itemCode: 'U',
      itemValue: '未知',
      displayOrder: '3',
      isDefault: '1',
      creatorId: '9',
      creatorName: '张三',
    );
    expect(item.id, '4');
    expect(item.dictId, '1');
    expect(item.isDefault, '1');
    expect(item.hospId, '1', reason: '医院冗余列取自所属字典');
    expect(item.hospName, '示例人民医院');

    // 原默认项（2）被互斥清位
    final items = await service.listItems('1');
    final defaults = items.where((i) => i.isDefault == '1').toList();
    expect(defaults.map((i) => i.id), ['4']);
  });

  test('createItem：同字典重码/跨字典同码/字典不存在/默认标记非法均校验', () async {
    // 同字典内重码 → 报错
    await expectLater(
      service.createItem(dictId: '1', itemCode: 'M', itemValue: '重复编码', isDefault: '0', creatorId: '9', creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('该字典下项目编码已存在'))),
    );
    // 不同字典同码 → 成功
    final otherDict = await service.createItem(dictId: '2', itemCode: 'M', itemValue: '初中', isDefault: '0', creatorId: '9', creatorName: '张三');
    expect(otherDict.id, '4');

    await expectLater(
      service.createItem(dictId: '999', itemCode: 'X', itemValue: '孤儿数据项', isDefault: '0', creatorId: '9', creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('数据字典不存在'))),
    );
    await expectLater(
      service.createItem(dictId: '1', itemCode: 'X', itemValue: '非法默认标记', isDefault: '2', creatorId: '9', creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('是否默认值应为'))),
    );
    await expectLater(
      service.createItem(dictId: '1', itemCode: 'X', itemValue: '  ', isDefault: '0', creatorId: '9', creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('项目值不能为空'))),
    );
    await expectLater(
      service.createItem(dictId: '1', itemCode: 'C' * 51, itemValue: '超长编码', isDefault: '0', creatorId: '9', creatorName: '张三'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不能超过'))),
    );
  });

  test('updateItem：改编码/值/顺序；重码与未知字段报错', () async {
    final updated = await service.updateItem('1', {'itemCode': 'MALE', 'itemValue': '男性', 'displayOrder': '10'});
    expect(updated.itemCode, 'MALE');
    expect(updated.itemValue, '男性');
    expect(updated.displayOrder, '10');
    expect(updated.updateTime, isNotNull);

    await expectLater(
      service.updateItem('1', {'itemCode': 'F'}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('该字典下项目编码已存在'))),
    );
    await expectLater(
      service.updateItem('1', {'isDefault': '1'}),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('deleteItem：删除成功；不存在报错', () async {
    expect(await service.deleteItem('2'), 1);
    // 删除默认项后字典 1 无默认项
    final items = await service.listItems('1');
    expect(items.where((i) => i.isDefault == '1'), isEmpty);

    await expectLater(
      service.deleteItem('2'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('setItemDefault：互斥置位；已是默认项为空操作；不存在报错', () async {
    final item = await service.setItemDefault('1');
    expect(item.isDefault, '1');
    // 原默认项 2 被清位
    final items = await service.listItems('1');
    expect(items.firstWhere((i) => i.id == '2').isDefault, '0');

    // 已是默认项 → 直接返回，不再写库
    final again = await service.setItemDefault('1');
    expect(again.isDefault, '1');

    await expectLater(
      service.setItemDefault('999'),
      throwsA(isA<DictException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });
}
