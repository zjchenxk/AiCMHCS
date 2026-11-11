import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/department_service.dart';
import 'package:test/test.dart';

/// 科室管理服务单元测试（SQLite :memory:）：列表、详情、三种挂载方式的
/// 新增校验与 CODE 回读、字段级修改、删除与下级阻止。
void main() {
  late SqliteGateway db;
  late DepartmentService service;

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
    await db.executeDirect('''
CREATE TABLE SYS_DEPARTMENT (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
  PARENT_ID INTEGER, -- 上级科室ID
  CODE TEXT NOT NULL, -- 科室代码
  NAME TEXT NOT NULL, -- 科室名称
  ADDRESS TEXT, -- 地址
  TEL TEXT, -- 联系电话
  CAMPUS_ID INTEGER, -- 所属院区ID
  HOSP_ID INTEGER NOT NULL, -- 所属医院ID
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 更新时间
)''');
    // 医院 1（未设置院区）、医院 2（下设院区 3）。
    Future<void> seedHospital(int id, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_HOSPITAL (ID, CODE, NAME, PROVINCE, CITY, COUNTY, '
        'ADDRESS, TEL, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, code, name, '北京市', '北京市', '东城区', '测试路1号', '010-12345678', '2026-11-07 09:00:00'],
      );
    }

    await seedHospital(1, 'H110101001', '示例人民医院');
    await seedHospital(2, 'H110101002', '示例人民医院-儿童心理分院');
    await db.execute(
      'INSERT INTO SYS_CAMPUS (ID, HOSP_ID, CODE, NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?)',
      [3, 2, 'C0003', '东城院区', '2026-11-07 09:00:00'],
    );
    // 科室：1/2 直挂医院 1（无院区），3 为 2 的下级，4 挂医院 2 的院区 3。
    Future<void> seedDept(
      int id,
      int hospId,
      int? campusId,
      int? parentId,
      String code,
      String name,
    ) async {
      await db.execute(
        'INSERT INTO SYS_DEPARTMENT (ID, HOSP_ID, CAMPUS_ID, PARENT_ID, CODE, '
        'NAME, ADDRESS, TEL, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, hospId, campusId, parentId, code, name, '测试路1号', '010-87654321', '2026-11-07 09:30:00'],
      );
    }

    await seedDept(1, 1, null, null, 'D0001', '儿童保健科');
    await seedDept(2, 1, null, null, 'D0002', '儿童心理科');
    await seedDept(3, 1, null, 2, 'D0003', '儿童心理门诊');
    await seedDept(4, 2, 3, null, 'D0004', '儿童心理科');
    service = DepartmentService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listAll：全量按院区、上级、ID 排序', () async {
    final departments = await service.listAll();
    expect(departments.map((d) => d.id), ['1', '2', '3', '4']);
    expect(departments.first.hospId, '1');
    expect(departments.first.campusId, isNull);
    expect(departments[2].parentId, '2');
    expect(departments.last.hospId, '2');
    expect(departments.last.campusId, '3');
  });

  test('getById：查详情；不存在与非法 ID 报错', () async {
    final department = await service.getById('3');
    expect(department.name, '儿童心理门诊');
    expect(department.parentId, '2');
    expect(department.hospId, '1');
    expect(department.address, '测试路1号');
    expect(department.tel, '010-87654321');

    await expectLater(
      service.getById('999'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('create：直挂医院成功（医院未设置院区），自增 ID 经 CODE 回读', () async {
    final created = await service.create(
      hospId: '1',
      code: 'D0005',
      name: '发育行为科',
      address: '测试路2号',
      tel: '010-11112222',
    );
    expect(created.id, '5');
    expect(created.hospId, '1');
    expect(created.campusId, isNull);
    expect(created.parentId, isNull);
    expect(created.code, 'D0005');

    final rows = await db.query(
      'SELECT CAMPUS_ID, PARENT_ID, CREATE_TIME FROM SYS_DEPARTMENT WHERE ID = 5',
    );
    expect(rows.rows.single[0], isNull);
    expect(rows.rows.single[1], isNull);
    // CREATE_TIME 由 Dart 侧生成绑定
    expect(rows.rows.single[2], isNotEmpty);
  });

  test('create：挂院区下成功', () async {
    final created = await service.create(
      hospId: '2',
      campusId: '3',
      code: 'D0006',
      name: '儿童保健科',
    );
    expect(created.id, '5');
    expect(created.hospId, '2');
    expect(created.campusId, '3');
    expect(created.parentId, isNull);
  });

  test('create：下级科室成功并继承上级院区归属', () async {
    // 上级直挂医院（无院区）→ 下级同样无院区
    final underHospital = await service.create(
      hospId: '1',
      parentId: '2',
      code: 'D0007',
      name: '心理咨询室',
    );
    expect(underHospital.parentId, '2');
    expect(underHospital.campusId, isNull);
    // 上级挂院区 → 下级继承院区
    final underCampus = await service.create(
      hospId: '2',
      parentId: '4',
      code: 'D0008',
      name: '心理咨询室',
    );
    expect(underCampus.parentId, '4');
    expect(underCampus.campusId, '3');
  });

  test('create：医院已设置院区时也允许直挂医院下（2026-11-10 取消强制挂院区限制）', () async {
    final direct = await service.create(hospId: '2', code: 'D9999', name: '直挂科');
    expect(direct.id, '5');
    expect(direct.hospId, '2');
    expect(direct.campusId, isNull);
    expect(direct.parentId, isNull);
    // 未设置院区的医院不受影响
    final ok = await service.create(hospId: '1', code: 'D0005', name: '发育行为科');
    expect(ok.id, '6');
  });

  test('create：院区不存在或不属于该医院 / 上级科室不存在或跨医院均报错', () async {
    await expectLater(
      service.create(hospId: '2', campusId: '999', code: 'D0010', name: '孤儿科室'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('所属院区不存在'))),
    );
    // 院区 3 属医院 2，挂到医院 1 名下按不存在处理
    await expectLater(
      service.create(hospId: '1', campusId: '3', code: 'D0011', name: '跨院科室'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('所属院区不存在'))),
    );
    await expectLater(
      service.create(hospId: '1', parentId: '999', code: 'D0012', name: '孤儿下级'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('上级科室不存在'))),
    );
    // 科室 4 属医院 2，作为医院 1 的上级被拒
    await expectLater(
      service.create(hospId: '1', parentId: '4', code: 'D0013', name: '跨院下级'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('不能跨医院挂载'))),
    );
  });

  test('create：代码重复 / 同级名称重复 / 必填缺失 / 超长 / 非法 ID 均报错', () async {
    await expectLater(
      service.create(hospId: '1', code: 'D0001', name: '重码科室'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('科室代码已存在'))),
    );
    // 同为医院 1 直挂顶层，与科室 1 同名冲突
    await expectLater(
      service.create(hospId: '1', code: 'D0014', name: '儿童保健科'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('同级下科室名称已存在'))),
    );
    // 同为科室 2 的下级，与科室 3 同名冲突
    await expectLater(
      service.create(hospId: '1', parentId: '2', code: 'D0015', name: '儿童心理门诊'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('同级下科室名称已存在'))),
    );
    // 名称与另一挂载点同名不冲突：院区 3 下已有「儿童心理科」（科室 4），
    // 医院院区 3 下建「儿童保健科」、科室 1 下建「儿童心理门诊」均成功
    final okCampus = await service.create(hospId: '2', campusId: '3', code: 'D0016', name: '儿童保健科');
    expect(okCampus.campusId, '3');
    final okChild = await service.create(hospId: '1', parentId: '1', code: 'D0017', name: '儿童心理门诊');
    expect(okChild.parentId, '1');

    await expectLater(
      service.create(hospId: '1', code: '  ', name: '无代码'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('科室代码不能为空'))),
    );
    await expectLater(
      service.create(hospId: '1', code: 'D0018', name: ' '),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('科室名称不能为空'))),
    );
    await expectLater(
      service.create(hospId: '1', code: 'D0019', name: '超长', address: '测' * 101),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('地址不能超过'))),
    );
    await expectLater(
      service.create(hospId: 'x', code: 'D0020', name: '非法'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('格式不正确'))),
    );
  });

  test('update：改名称、清空可空列、改代码', () async {
    final updated = await service.update('3', {
      'name': '心理评估室',
      'address': null,
      'code': 'D0003X',
    });
    expect(updated.name, '心理评估室');
    expect(updated.address, isNull);
    expect(updated.code, 'D0003X');

    final rows = await db.query(
      'SELECT NAME, ADDRESS, UPDATE_TIME FROM SYS_DEPARTMENT WHERE ID = 3',
    );
    expect(rows.rows.single[0], '心理评估室');
    expect(rows.rows.single[1], isNull);
    expect(rows.rows.single[2], isNotEmpty);
  });

  test('update：同级改名判重 / 与自身同值不算重复', () async {
    // 科室 1 改为「儿童心理科」与同级（医院 1 直挂）科室 2 冲突
    await expectLater(
      service.update('1', {'name': '儿童心理科'}),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('同级下科室名称已存在'))),
    );
    // 与自身同值不算重复
    final ok = await service.update('1', {'code': 'D0001', 'name': '儿童保健科'});
    expect(ok.code, 'D0001');
    expect(ok.name, '儿童保健科');
  });

  test('update：归属字段不可改 / 必填列置空 / 未知字段报错', () async {
    for (final key in ['hospId', 'campusId', 'parentId']) {
      await expectLater(
        service.update('1', {key: '9'}),
        throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
      );
    }
    await expectLater(
      service.update('1', {'name': null}),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('科室名称不能为空'))),
    );
    await expectLater(
      service.update('1', {'id': '2'}),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('delete：删除成功；不存在报错', () async {
    expect(await service.delete('1'), 1);
    final remain = await db.query('SELECT ID FROM SYS_DEPARTMENT ORDER BY ID');
    expect(remain.rows.expand((r) => r), ['2', '3', '4']);

    await expectLater(
      service.delete('1'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('delete：存在下级科室时阻止删除', () async {
    await expectLater(
      service.delete('2'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', '请先删除下级科室后，再删除科室')),
    );
    // 先删下级 3 再删 2 即可成功
    expect(await service.delete('3'), 1);
    expect(await service.delete('2'), 1);
  });
}
