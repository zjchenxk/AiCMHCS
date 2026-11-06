import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/campus_service.dart';
import 'package:test/test.dart';

/// 院区管理服务单元测试（SQLite :memory:）：列表、详情、新增校验与
/// CODE 回读、字段级修改与归属调整、删除。
void main() {
  late SqliteGateway db;
  late CampusService service;

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
    // 医院：示例人民医院 → 儿童心理分院。
    Future<void> seedHospital(int id, int? parentId, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_HOSPITAL (ID, PARENT_ID, CODE, NAME, PROVINCE, CITY, '
        'COUNTY, ADDRESS, TEL, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, parentId, code, name, '北京市', '北京市', '东城区', '测试路1号', '010-12345678', '2026-10-26 10:00:00'],
      );
    }

    await seedHospital(1, null, 'H110101001', '示例人民医院');
    await seedHospital(2, 1, 'H110101002', '示例人民医院-儿童心理分院');
    // 院区：医院 1 下两条、医院 2 下一条。
    Future<void> seedCampus(int id, int hospId, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_CAMPUS (ID, HOSP_ID, CODE, NAME, ADDRESS, TEL, '
        'CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, hospId, code, name, '测试路1号', '010-87654321', '2026-11-06 09:00:00'],
      );
    }

    await seedCampus(1, 1, 'C0001', '主院区');
    await seedCampus(2, 1, 'C0002', '顺义院区');
    await seedCampus(3, 2, 'C0003', '东城院区');
    service = CampusService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listAll：全量按医院、ID 排序', () async {
    final campuses = await service.listAll();
    expect(campuses.map((c) => c.id), ['1', '2', '3']);
    expect(campuses.first.hospId, '1');
    expect(campuses.first.code, 'C0001');
    expect(campuses.first.name, '主院区');
    expect(campuses.first.address, '测试路1号');
    expect(campuses.first.tel, '010-87654321');
    expect(campuses.last.hospId, '2');
  });

  test('getById：查详情；不存在与非法 ID 报错', () async {
    final campus = await service.getById('2');
    expect(campus.name, '顺义院区');
    expect(campus.hospId, '1');

    await expectLater(
      service.getById('999'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('create：新增成功，自增 ID 经 CODE 回读', () async {
    final created = await service.create(
      hospId: '2',
      code: 'C0004',
      name: '西城院区',
      address: '测试路2号',
      tel: '010-11112222',
    );
    expect(created.id, '4');
    expect(created.hospId, '2');
    expect(created.code, 'C0004');

    final rows = await db.query(
      'SELECT HOSP_ID, NAME, ADDRESS, CREATE_TIME FROM SYS_CAMPUS WHERE ID = 4',
    );
    expect(rows.rows.single[0], '2');
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
      service.create(hospId: '1', code: 'C0001', name: '重码院区'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('院区代码已存在'))),
    );
    await expectLater(
      service.create(hospId: '1', code: 'C0009', name: '主院区'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('该医院下院区名称已存在'))),
    );
    // 名称与另一医院院区同名不冲突
    final ok = await service.create(hospId: '2', code: 'C0010', name: '主院区');
    expect(ok.hospId, '2');
    await expectLater(
      service.create(hospId: '1', code: '  ', name: '无代码'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('院区代码不能为空'))),
    );
    await expectLater(
      service.create(hospId: '1', code: 'C0011', name: ' '),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('院区名称不能为空'))),
    );
    await expectLater(
      service.create(hospId: '1', code: 'C0012', name: '超长', address: '测' * 101),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('院区地址不能超过'))),
    );
    await expectLater(
      service.create(hospId: 'x', code: 'C0013', name: '非法'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('update：改名称、清空可空列、改代码', () async {
    final updated = await service.update('1', {
      'name': '本部院区',
      'address': null,
      'code': 'C0001X',
    });
    expect(updated.name, '本部院区');
    expect(updated.address, isNull);
    expect(updated.code, 'C0001X');

    final rows = await db.query(
      'SELECT NAME, ADDRESS, UPDATE_TIME FROM SYS_CAMPUS WHERE ID = 1',
    );
    expect(rows.rows.single[0], '本部院区');
    expect(rows.rows.single[1], isNull);
    expect(rows.rows.single[2], isNotEmpty);
  });

  test('update：调整归属医院', () async {
    final updated = await service.update('1', {'hospId': '2'});
    expect(updated.hospId, '2');
  });

  test('update：归属与名称同改按目标归属判重', () async {
    // 院区 2（顺义院区）调往医院 2 并改名东城院区 → 与医院 2 下院区 3 冲突
    await expectLater(
      service.update('2', {'hospId': '2', 'name': '东城院区'}),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('该医院下院区名称已存在'))),
    );
    // 调往医院 2 且改名不冲突则成功
    final ok = await service.update('2', {'hospId': '2', 'name': '朝阳院区'});
    expect(ok.hospId, '2');
    expect(ok.name, '朝阳院区');
  });

  test('update：仅改归属时按当前名称在新归属下判重', () async {
    // 医院 2 下先造一个同名「主院区」，再把院区 1 调往医院 2 → 冲突
    await service.create(hospId: '2', code: 'C0011', name: '主院区');
    await expectLater(
      service.update('1', {'hospId': '2'}),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('该医院下院区名称已存在'))),
    );
  });

  test('update：代码与名称与自身相同不算重复', () async {
    final updated = await service.update('1', {'code': 'C0001', 'name': '主院区'});
    expect(updated.code, 'C0001');
    expect(updated.name, '主院区');
  });

  test('update：目标医院不存在 / 必填列置空 / 未知字段报错', () async {
    await expectLater(
      service.update('1', {'hospId': '999'}),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('所属医院不存在'))),
    );
    await expectLater(
      service.update('1', {'name': null}),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('院区名称不能为空'))),
    );
    await expectLater(
      service.update('1', {'id': '2'}),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('delete：删除成功；不存在报错', () async {
    expect(await service.delete('1'), 1);
    final remain = await db.query('SELECT ID FROM SYS_CAMPUS ORDER BY ID');
    expect(remain.rows.expand((r) => r), ['2', '3']);

    await expectLater(
      service.delete('1'),
      throwsA(isA<CampusException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });
}
