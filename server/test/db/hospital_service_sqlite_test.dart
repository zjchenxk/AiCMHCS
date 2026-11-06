import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/hospital_service.dart';
import 'package:test/test.dart';

/// 医院管理服务单元测试（SQLite :memory:）：列表、详情、新增校验与
/// CODE 回读、字段级修改、子树统计与级联删除。
void main() {
  late SqliteGateway db;
  late HospitalService service;

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
    // 树形：示例人民医院 → 第一/第二分院 → 第一分院下社区门诊。
    Future<void> seed(int id, int? parentId, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_HOSPITAL (ID, PARENT_ID, CODE, NAME, PROVINCE, CITY, '
        'COUNTY, ADDRESS, TEL, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, parentId, code, name, '北京市', '北京市', '东城区', '测试路1号', '010-12345678', '2026-10-26 10:00:00'],
      );
    }

    await seed(1, null, 'H110101001', '示例人民医院');
    await seed(2, 1, 'H110101002', '示例人民医院-第一分院');
    await seed(3, 1, 'H110101003', '示例人民医院-第二分院');
    await seed(4, 2, 'H110101004', '第一分院-社区门诊');
    // 院区表（deleteSubtree 前置校验依赖；用例按需写入行）
    await db.executeDirect('''
CREATE TABLE SYS_CAMPUS (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
  HOSP_ID INTEGER NOT NULL,
  CODE TEXT,
  NAME TEXT NOT NULL,
  ADDRESS TEXT,
  TEL TEXT,
  CREATE_TIME TEXT NOT NULL,
  UPDATE_TIME TEXT
)''');
    service = HospitalService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listAll：扁平全量按 ID 排序，hasChildren 标记正确', () async {
    final hospitals = await service.listAll();
    expect(hospitals.map((h) => h.id), ['1', '2', '3', '4']);
    expect(hospitals.first.code, 'H110101001');
    expect(hospitals.first.parentId, isNull);
    expect(hospitals.first.hasChildren, isTrue);
    expect(hospitals.last.hasChildren, isFalse);
    expect(hospitals.first.province, '北京市');
    expect(hospitals.first.county, '东城区');
  });

  test('getById：查详情；不存在与非法 ID 报错', () async {
    final hospital = await service.getById('2');
    expect(hospital.name, '示例人民医院-第一分院');
    expect(hospital.parentId, '1');

    await expectLater(
      service.getById('999'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('create：新增下级成功，自增 ID 经 CODE 回读', () async {
    final created = await service.create(
      parentId: '3',
      code: 'H110101005',
      name: '第二分院-儿童心理科',
      province: '北京市',
      city: '北京市',
      county: '东城区',
      address: '测试路5号',
      tel: '010-87654321',
    );
    expect(created.id, '5');
    expect(created.parentId, '3');

    final rows = await db.query(
      'SELECT NAME, PARENT_ID, CODE, CREATE_TIME FROM SYS_HOSPITAL WHERE ID = 5',
    );
    expect(rows.rows.single[0], '第二分院-儿童心理科');
    expect(rows.rows.single[1], '3');
    expect(rows.rows.single[2], 'H110101005');
    // CREATE_TIME 由 Dart 侧生成绑定
    expect(rows.rows.single[3], isNotEmpty);
  });

  test('create：新增顶级（parentId 空串按 null 处理）', () async {
    final created = await service.create(
      parentId: '',
      code: 'H110101006',
      name: '示例中医院',
      province: '天津市',
      city: '天津市',
      address: '测试路6号',
    );
    expect(created.parentId, isNull);
  });

  test('create：代码重复 / 上级不存在 / 必填缺失 / 超长均报错', () async {
    await expectLater(
      service.create(code: 'H110101001', name: '重复', province: '北京市', city: '北京市', address: '测试路'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('已存在'))),
    );
    await expectLater(
      service.create(parentId: '999', code: 'H999', name: '孤儿', province: '北京市', city: '北京市', address: '测试路'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.create(code: '  ', name: '无代码', province: '北京市', city: '北京市', address: '测试路'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('组织机构代码不能为空'))),
    );
    await expectLater(
      service.create(code: 'H1', name: ' ', province: '北京市', city: '北京市', address: '测试路'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('医院名称不能为空'))),
    );
    await expectLater(
      service.create(code: 'H1', name: '缺省', province: '', city: '北京市', address: '测试路'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('省份不能为空'))),
    );
    await expectLater(
      service.create(code: 'H1', name: '超长', province: '北京市', city: '北京市', address: '测' * 101),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('详细地址不能超过'))),
    );
  });

  test('update：改名称、清空可空列、改代码', () async {
    final updated = await service.update('4', {
      'name': '第一分院-儿童保健门诊',
      'county': null,
      'code': 'H110101004X',
    });
    expect(updated.name, '第一分院-儿童保健门诊');
    expect(updated.county, isNull);
    expect(updated.code, 'H110101004X');

    final rows = await db.query(
      'SELECT NAME, COUNTY, CODE, UPDATE_TIME FROM SYS_HOSPITAL WHERE ID = 4',
    );
    expect(rows.rows.single[0], '第一分院-儿童保健门诊');
    expect(rows.rows.single[1], isNull);
    expect(rows.rows.single[3], isNotEmpty);
  });

  test('update：代码与自身相同不算重复', () async {
    final updated = await service.update('1', {'code': 'H110101001'});
    expect(updated.code, 'H110101001');
  });

  test('update：代码与其他医院重复 / 必填列置空 / 未知字段报错', () async {
    await expectLater(
      service.update('2', {'code': 'H110101001'}),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('已存在'))),
    );
    await expectLater(
      service.update('2', {'name': null}),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('医院名称不能为空'))),
    );
    await expectLater(
      service.update('2', {'parentId': '3'}),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('subtreeCount：统计含自身的多层子树规模', () async {
    expect(await service.subtreeCount('1'), 4);
    expect(await service.subtreeCount('2'), 2);
    expect(await service.subtreeCount('3'), 1);
  });

  test('deleteSubtree：级联删除全部下级、兄弟分支不受影响', () async {
    final deleted = await service.deleteSubtree('2');
    expect(deleted, 2);

    final remain = await db.query('SELECT ID FROM SYS_HOSPITAL ORDER BY ID');
    expect(remain.rows.expand((r) => r), ['1', '3']);

    await expectLater(
      service.deleteSubtree('999'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('subtreeCampusCount：统计子树各医院下的院区总数', () async {
    Future<void> seedCampus(int id, int hospId, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_CAMPUS (ID, HOSP_ID, CODE, NAME, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?)',
        [id, hospId, code, name, '2026-11-06 09:00:00'],
      );
    }

    await seedCampus(1, 1, 'C0001', '主院区');
    await seedCampus(2, 2, 'C0002', '第一分院-东城院区');
    await seedCampus(3, 4, 'C0003', '社区门诊-西城院区');

    // 子树 1 → 医院 1/2/3/4，院区共 3 个；子树 2 → 医院 2/4，2 个
    expect(await service.subtreeCampusCount('1'), 3);
    expect(await service.subtreeCampusCount('2'), 2);
    expect(await service.subtreeCampusCount('3'), 0);
  });

  test('deleteSubtree：子树存在院区时阻止删除，无院区分支仍可删', () async {
    await db.execute(
      'INSERT INTO SYS_CAMPUS (HOSP_ID, CODE, NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?)',
      [2, 'C0002', '第一分院-东城院区', '2026-11-06 09:00:00'],
    );

    // 医院子树 1 含下级 2，2 下有院区 → 阻止（含自身有院区同理）
    await expectLater(
      service.deleteSubtree('1'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', '请先删除院区后，再删除医院')),
    );
    await expectLater(
      service.deleteSubtree('2'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', '请先删除院区后，再删除医院')),
    );

    // 无院区的兄弟分支不受影响
    expect(await service.deleteSubtree('3'), 1);
    final remain = await db.query('SELECT ID FROM SYS_HOSPITAL ORDER BY ID');
    expect(remain.rows.expand((r) => r), ['1', '2', '4']);
  });
}
