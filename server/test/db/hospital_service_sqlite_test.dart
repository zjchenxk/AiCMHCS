import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/hospital_service.dart';
import 'package:server/utils/uuid_util.dart';
import 'package:test/test.dart';

// 种子数据固定 UUID（任意 36 位字符串均可作 CHAR(36) 主键值，固定值
// 便于跨行引用，并保证「ORDER BY ID」按字符串序排序稳定）。
const hosp1Id = 'a0000000-0000-0000-0000-000000000001';
const hosp2Id = 'a0000000-0000-0000-0000-000000000002';
const hosp3Id = 'a0000000-0000-0000-0000-000000000003';
const hosp4Id = 'a0000000-0000-0000-0000-000000000004';

// UUID v7 标准 36 位连字符形式（新建行 ID 断言用）。
final uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// 医院管理服务单元测试（SQLite :memory:）：列表、详情、新增校验与
/// ID 回读、字段级修改、子树统计与级联删除。
void main() {
  late SqliteGateway db;
  late HospitalService service;

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
    // 树形：示例人民医院 → 第一/第二分院 → 第一分院下社区门诊。
    Future<void> seed(String id, String? parentId, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_HOSPITAL (ID, PARENT_ID, CODE, NAME, PROVINCE, CITY, '
        'COUNTY, ADDRESS, TEL, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, parentId, code, name, '北京市', '北京市', '东城区', '测试路1号', '010-12345678', '2026-10-26 10:00:00'],
      );
    }

    await seed(hosp1Id, null, 'H110101001', '示例人民医院');
    await seed(hosp2Id, hosp1Id, 'H110101002', '示例人民医院-第一分院');
    await seed(hosp3Id, hosp1Id, 'H110101003', '示例人民医院-第二分院');
    await seed(hosp4Id, hosp2Id, 'H110101004', '第一分院-社区门诊');
    // 院区表（deleteSubtree 前置校验依赖；用例按需写入行）
    await db.executeDirect('''
CREATE TABLE SYS_CAMPUS (
  ID TEXT PRIMARY KEY NOT NULL,
  HOSP_ID TEXT NOT NULL,
  CODE TEXT,
  NAME TEXT NOT NULL,
  ADDRESS TEXT,
  TEL TEXT,
  CREATE_TIME TEXT NOT NULL,
  UPDATE_TIME TEXT
)''');
    // 科室表（deleteSubtree 前置校验依赖；用例按需写入行）
    await db.executeDirect('''
CREATE TABLE SYS_DEPARTMENT (
  ID TEXT PRIMARY KEY NOT NULL,
  PARENT_ID TEXT,
  CODE TEXT NOT NULL,
  NAME TEXT NOT NULL,
  ADDRESS TEXT,
  TEL TEXT,
  CAMPUS_ID TEXT,
  HOSP_ID TEXT NOT NULL,
  CREATE_TIME TEXT NOT NULL,
  UPDATE_TIME TEXT
)''');
    service = HospitalService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listAll：扁平全量按 ID 排序（固定 UUID 按字符串序），hasChildren 标记正确', () async {
    final hospitals = await service.listAll();
    expect(hospitals.map((h) => h.id), [hosp1Id, hosp2Id, hosp3Id, hosp4Id]);
    expect(hospitals.first.code, 'H110101001');
    expect(hospitals.first.parentId, isNull);
    expect(hospitals.first.hasChildren, isTrue);
    expect(hospitals.last.hasChildren, isFalse);
    expect(hospitals.first.province, '北京市');
    expect(hospitals.first.county, '东城区');
  });

  test('listAll：scopeHospId 为空串/null 视为未限定，返回全量', () async {
    expect((await service.listAll(scopeHospId: null)).map((h) => h.id), [hosp1Id, hosp2Id, hosp3Id, hosp4Id]);
    expect((await service.listAll(scopeHospId: '  ')).map((h) => h.id), [hosp1Id, hosp2Id, hosp3Id, hosp4Id]);
  });

  test('listAll：scopeHospId 限定返回该医院及其全部嵌套下级', () async {
    // 以中间节点为范围根：只含自身与子树，兄弟分支与上级均不在结果内
    final scoped = await service.listAll(scopeHospId: hosp2Id);
    expect(scoped.map((h) => h.id), [hosp2Id, hosp4Id]);
    expect(scoped.first.hasChildren, isTrue, reason: '子级在结果内，hasChildren 应为真');
    expect(scoped.last.hasChildren, isFalse);

    // 以顶级为范围根：整棵子树
    expect((await service.listAll(scopeHospId: hosp1Id)).map((h) => h.id), [hosp1Id, hosp2Id, hosp3Id, hosp4Id]);

    // 叶子为范围根：仅自身
    expect((await service.listAll(scopeHospId: hosp3Id)).map((h) => h.id), [hosp3Id]);
  });

  test('listAll：scopeHospId 不存在或未知 ID 时返回空列表', () async {
    expect(await service.listAll(scopeHospId: '999'), isEmpty);
    expect(await service.listAll(scopeHospId: 'abc'), isEmpty);
  });

  test('getById：查详情；不存在 ID 报错', () async {
    final hospital = await service.getById(hosp2Id);
    expect(hospital.name, '示例人民医院-第一分院');
    expect(hospital.parentId, hosp1Id);

    // 主键为 UUID 字符串，任意未种子化的取值（含乱串）均走「不存在」路径
    await expectLater(
      service.getById('999'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('create：新增下级成功，ID 前置生成经 CODE 回读', () async {
    final created = await service.create(
      parentId: hosp3Id,
      code: 'H110101005',
      name: '第二分院-儿童心理科',
      province: '北京市',
      city: '北京市',
      county: '东城区',
      address: '测试路5号',
      tel: '010-87654321',
    );
    // 服务在 INSERT 前生成 UUID v7 并以新 ID 回读
    expect(uuidPattern.hasMatch(created.id), isTrue);
    expect(created.parentId, hosp3Id);

    final rows = await db.query(
      'SELECT NAME, PARENT_ID, CODE, CREATE_TIME FROM SYS_HOSPITAL WHERE ID = ?',
      [created.id],
    );
    expect(rows.rows.single[0], '第二分院-儿童心理科');
    expect(rows.rows.single[1], hosp3Id);
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
    final updated = await service.update(hosp4Id, {
      'name': '第一分院-儿童保健门诊',
      'county': null,
      'code': 'H110101004X',
    });
    expect(updated.name, '第一分院-儿童保健门诊');
    expect(updated.county, isNull);
    expect(updated.code, 'H110101004X');

    final rows = await db.query(
      'SELECT NAME, COUNTY, CODE, UPDATE_TIME FROM SYS_HOSPITAL WHERE ID = ?',
      [hosp4Id],
    );
    expect(rows.rows.single[0], '第一分院-儿童保健门诊');
    expect(rows.rows.single[1], isNull);
    expect(rows.rows.single[3], isNotEmpty);
  });

  test('update：代码与自身相同不算重复', () async {
    final updated = await service.update(hosp1Id, {'code': 'H110101001'});
    expect(updated.code, 'H110101001');
  });

  test('update：代码与其他医院重复 / 必填列置空 / 未知字段报错', () async {
    await expectLater(
      service.update(hosp2Id, {'code': 'H110101001'}),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('已存在'))),
    );
    await expectLater(
      service.update(hosp2Id, {'name': null}),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('医院名称不能为空'))),
    );
    await expectLater(
      service.update(hosp2Id, {'parentId': hosp3Id}),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('subtreeCount：统计含自身的多层子树规模', () async {
    expect(await service.subtreeCount(hosp1Id), 4);
    expect(await service.subtreeCount(hosp2Id), 2);
    expect(await service.subtreeCount(hosp3Id), 1);
  });

  test('deleteSubtree：级联删除全部下级、兄弟分支不受影响', () async {
    final deleted = await service.deleteSubtree(hosp2Id);
    expect(deleted, 2);

    final remain = await db.query('SELECT ID FROM SYS_HOSPITAL ORDER BY ID');
    expect(remain.rows.expand((r) => r), [hosp1Id, hosp3Id]);

    await expectLater(
      service.deleteSubtree('999'),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('subtreeCampusCount：统计子树各医院下的院区总数', () async {
    Future<void> seedCampus(String hospId, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_CAMPUS (ID, HOSP_ID, CODE, NAME, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?)',
        [newUuid(), hospId, code, name, '2026-11-06 09:00:00'],
      );
    }

    await seedCampus(hosp1Id, 'C0001', '主院区');
    await seedCampus(hosp2Id, 'C0002', '第一分院-东城院区');
    await seedCampus(hosp4Id, 'C0003', '社区门诊-西城院区');

    // 子树 1 → 医院 1/2/3/4，院区共 3 个；子树 2 → 医院 2/4，2 个
    expect(await service.subtreeCampusCount(hosp1Id), 3);
    expect(await service.subtreeCampusCount(hosp2Id), 2);
    expect(await service.subtreeCampusCount(hosp3Id), 0);
  });

  test('deleteSubtree：子树存在院区时阻止删除，无院区分支仍可删', () async {
    await db.execute(
      'INSERT INTO SYS_CAMPUS (ID, HOSP_ID, CODE, NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?)',
      [newUuid(), hosp2Id, 'C0002', '第一分院-东城院区', '2026-11-06 09:00:00'],
    );

    // 医院子树 1 含下级 2，2 下有院区 → 阻止（含自身有院区同理）
    await expectLater(
      service.deleteSubtree(hosp1Id),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', '请先删除院区后，再删除医院')),
    );
    await expectLater(
      service.deleteSubtree(hosp2Id),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', '请先删除院区后，再删除医院')),
    );

    // 无院区的兄弟分支不受影响
    expect(await service.deleteSubtree(hosp3Id), 1);
    final remain = await db.query('SELECT ID FROM SYS_HOSPITAL ORDER BY ID');
    expect(remain.rows.expand((r) => r), [hosp1Id, hosp2Id, hosp4Id]);
  });

  test('subtreeDeptCount：统计子树各医院下的科室总数', () async {
    Future<void> seedDept(String hospId, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_DEPARTMENT (ID, HOSP_ID, CODE, NAME, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?)',
        [newUuid(), hospId, code, name, '2026-11-07 09:00:00'],
      );
    }

    await seedDept(hosp1Id, 'D0001', '儿童保健科');
    await seedDept(hosp2Id, 'D0002', '儿童心理科');
    await seedDept(hosp4Id, 'D0003', '社区门诊-儿童保健科');

    // 子树 1 → 医院 1/2/3/4，科室共 3 个；子树 2 → 医院 2/4，2 个
    expect(await service.subtreeDeptCount(hosp1Id), 3);
    expect(await service.subtreeDeptCount(hosp2Id), 2);
    expect(await service.subtreeDeptCount(hosp3Id), 0);
  });

  test('deleteSubtree：子树存在直挂科室时阻止删除，删光科室后仍可删', () async {
    await db.execute(
      'INSERT INTO SYS_DEPARTMENT (ID, HOSP_ID, CODE, NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?)',
      [newUuid(), hosp4Id, 'D0003', '社区门诊-儿童保健科', '2026-11-07 09:00:00'],
    );

    // 医院子树 1 含下级 4，4 下有科室 → 阻止（删光院区后仍可能残留）
    await expectLater(
      service.deleteSubtree(hosp1Id),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', '请先删除科室后，再删除医院')),
    );
    await expectLater(
      service.deleteSubtree(hosp4Id),
      throwsA(isA<HospitalException>().having((e) => e.message, 'message', '请先删除科室后，再删除医院')),
    );

    // 无科室的兄弟分支不受影响
    expect(await service.deleteSubtree(hosp3Id), 1);
    final remain = await db.query('SELECT ID FROM SYS_HOSPITAL ORDER BY ID');
    expect(remain.rows.expand((r) => r), [hosp1Id, hosp2Id, hosp4Id]);
  });
}
