import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/campus_service.dart';
import 'package:server/utils/uuid_util.dart';
import 'package:test/test.dart';

// 种子数据固定 UUID（任意 36 位字符串均可作 CHAR(36) 主键值，固定值
// 便于跨行引用，并保证「ORDER BY ID」按字符串序排序稳定）。
const hosp1Id = 'a0000000-0000-0000-0000-000000000001';
const hosp2Id = 'a0000000-0000-0000-0000-000000000002';
const campus1Id = 'b0000000-0000-0000-0000-000000000001';
const campus2Id = 'b0000000-0000-0000-0000-000000000002';
const campus3Id = 'b0000000-0000-0000-0000-000000000003';

// UUID v7 标准 36 位连字符形式（新建行 ID 断言用）。
final uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// 院区管理服务单元测试（SQLite :memory:）：列表、详情、新增校验与
/// ID 回读、字段级修改与归属调整、删除。
void main() {
  late SqliteGateway db;
  late CampusService service;

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
    // 科室表（delete 前置校验依赖；用例按需写入行）。
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
    // 医院：示例人民医院 → 儿童心理分院。
    Future<void> seedHospital(String id, String? parentId, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_HOSPITAL (ID, PARENT_ID, CODE, NAME, PROVINCE, CITY, '
        'COUNTY, ADDRESS, TEL, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, parentId, code, name, '北京市', '北京市', '东城区', '测试路1号', '010-12345678', '2026-10-26 10:00:00'],
      );
    }

    await seedHospital(hosp1Id, null, 'H110101001', '示例人民医院');
    await seedHospital(hosp2Id, hosp1Id, 'H110101002', '示例人民医院-儿童心理分院');
    // 院区：医院 1 下两条、医院 2 下一条。
    Future<void> seedCampus(String id, String hospId, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_CAMPUS (ID, HOSP_ID, CODE, NAME, ADDRESS, TEL, '
        'CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, hospId, code, name, '测试路1号', '010-87654321', '2026-11-06 09:00:00'],
      );
    }

    await seedCampus(campus1Id, hosp1Id, 'C0001', '主院区');
    await seedCampus(campus2Id, hosp1Id, 'C0002', '顺义院区');
    await seedCampus(campus3Id, hosp2Id, 'C0003', '东城院区');
    service = CampusService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listAll：全量按医院、ID 排序（固定 UUID 按字符串序）', () async {
    final campuses = await service.listAll();
    expect(campuses.map((c) => c.id), [campus1Id, campus2Id, campus3Id]);
    expect(campuses.first.hospId, hosp1Id);
    expect(campuses.first.code, 'C0001');
    expect(campuses.first.name, '主院区');
    expect(campuses.first.address, '测试路1号');
    expect(campuses.first.tel, '010-87654321');
    expect(campuses.last.hospId, hosp2Id);
  });

  test('getById：查详情；不存在 ID 报错', () async {
    final campus = await service.getById(campus2Id);
    expect(campus.name, '顺义院区');
    expect(campus.hospId, hosp1Id);

    // 主键为 UUID 字符串，任意未种子化的取值（含乱串）均走「不存在」路径
    await expectLater(
      service.getById('999'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('create：新增成功，ID 前置生成经 CODE 回读', () async {
    final created = await service.create(
      hospId: hosp2Id,
      code: 'C0004',
      name: '西城院区',
      address: '测试路2号',
      tel: '010-11112222',
    );
    // 服务在 INSERT 前生成 UUID v7 并以新 ID 回读
    expect(uuidPattern.hasMatch(created.id), isTrue);
    expect(created.hospId, hosp2Id);
    expect(created.code, 'C0004');

    final rows = await db.query(
      'SELECT HOSP_ID, NAME, ADDRESS, CREATE_TIME FROM SYS_CAMPUS WHERE ID = ?',
      [created.id],
    );
    expect(rows.rows.single[0], hosp2Id);
    expect(rows.rows.single[1], '西城院区');
    // CREATE_TIME 由 Dart 侧生成绑定
    expect(rows.rows.single[3], isNotEmpty);
  });

  test('create：医院不存在 / 代码重复 / 同院名称重复 / 必填缺失 / 超长均报错', () async {
    await expectLater(
      service.create(hospId: '999', code: 'C9999', name: '孤儿院区'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('所属医院不存在'))),
    );
    await expectLater(
      service.create(hospId: hosp1Id, code: 'C0001', name: '重码院区'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('院区代码已存在'))),
    );
    await expectLater(
      service.create(hospId: hosp1Id, code: 'C0009', name: '主院区'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('该医院下院区名称已存在'))),
    );
    // 名称与另一医院院区同名不冲突
    final ok = await service.create(hospId: hosp2Id, code: 'C0010', name: '主院区');
    expect(ok.hospId, hosp2Id);
    await expectLater(
      service.create(hospId: hosp1Id, code: '  ', name: '无代码'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('院区代码不能为空'))),
    );
    await expectLater(
      service.create(hospId: hosp1Id, code: 'C0011', name: ' '),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('院区名称不能为空'))),
    );
    await expectLater(
      service.create(hospId: hosp1Id, code: 'C0012', name: '超长', address: '测' * 101),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('院区地址不能超过'))),
    );
    // ID 不再校验数字格式，未知取值按「医院不存在」处理
    await expectLater(
      service.create(hospId: 'x', code: 'C0013', name: '非法'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('所属医院不存在'))),
    );
  });

  test('update：改名称、清空可空列、改代码', () async {
    final updated = await service.update(campus1Id, {
      'name': '本部院区',
      'address': null,
      'code': 'C0001X',
    });
    expect(updated.name, '本部院区');
    expect(updated.address, isNull);
    expect(updated.code, 'C0001X');

    final rows = await db.query(
      'SELECT NAME, ADDRESS, UPDATE_TIME FROM SYS_CAMPUS WHERE ID = ?',
      [campus1Id],
    );
    expect(rows.rows.single[0], '本部院区');
    expect(rows.rows.single[1], isNull);
    expect(rows.rows.single[2], isNotEmpty);
  });

  test('update：调整归属医院', () async {
    final updated = await service.update(campus1Id, {'hospId': hosp2Id});
    expect(updated.hospId, hosp2Id);
  });

  test('update：归属与名称同改按目标归属判重', () async {
    // 院区 2（顺义院区）调往医院 2 并改名东城院区 → 与医院 2 下院区 3 冲突
    await expectLater(
      service.update(campus2Id, {'hospId': hosp2Id, 'name': '东城院区'}),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('该医院下院区名称已存在'))),
    );
    // 调往医院 2 且改名不冲突则成功
    final ok = await service.update(campus2Id, {'hospId': hosp2Id, 'name': '朝阳院区'});
    expect(ok.hospId, hosp2Id);
    expect(ok.name, '朝阳院区');
  });

  test('update：仅改归属时按当前名称在新归属下判重', () async {
    // 医院 2 下先造一个同名「主院区」，再把院区 1 调往医院 2 → 冲突
    await service.create(hospId: hosp2Id, code: 'C0011', name: '主院区');
    await expectLater(
      service.update(campus1Id, {'hospId': hosp2Id}),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('该医院下院区名称已存在'))),
    );
  });

  test('update：代码与名称与自身相同不算重复', () async {
    final updated = await service.update(campus1Id, {'code': 'C0001', 'name': '主院区'});
    expect(updated.code, 'C0001');
    expect(updated.name, '主院区');
  });

  test('update：目标医院不存在 / 必填列置空 / 未知字段报错', () async {
    await expectLater(
      service.update(campus1Id, {'hospId': '999'}),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('所属医院不存在'))),
    );
    await expectLater(
      service.update(campus1Id, {'name': null}),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('院区名称不能为空'))),
    );
    await expectLater(
      service.update(campus1Id, {'id': '2'}),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('delete：删除成功；不存在报错', () async {
    expect(await service.delete(campus1Id), 1);
    final remain = await db.query('SELECT ID FROM SYS_CAMPUS ORDER BY ID');
    expect(remain.rows.expand((r) => r), [campus2Id, campus3Id]);

    await expectLater(
      service.delete(campus1Id),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('delete：院区下存在科室时阻止删除', () async {
    await db.execute(
      'INSERT INTO SYS_DEPARTMENT (ID, HOSP_ID, CAMPUS_ID, CODE, NAME, '
      'CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?)',
      [newUuid(), hosp1Id, campus2Id, 'D0001', '儿童心理科', '2026-11-07 09:00:00'],
    );

    await expectLater(
      service.delete(campus2Id),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', '院区下存在科室，不能删除，请先删除科室')),
    );
    // 无科室的院区不受影响
    expect(await service.delete(campus1Id), 1);
  });
}
