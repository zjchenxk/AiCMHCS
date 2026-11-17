import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/department_service.dart';
import 'package:test/test.dart';

// 种子数据固定 UUID（任意 36 位字符串均可作 CHAR(36) 主键值，固定值
// 便于跨行引用，并保证「ORDER BY ID」按字符串序排序稳定）。
const hosp1Id = 'a0000000-0000-0000-0000-000000000001';
const hosp2Id = 'a0000000-0000-0000-0000-000000000002';
const campus3Id = 'b0000000-0000-0000-0000-000000000003';
const dept1Id = 'c0000000-0000-0000-0000-000000000001';
const dept2Id = 'c0000000-0000-0000-0000-000000000002';
const dept3Id = 'c0000000-0000-0000-0000-000000000003';
const dept4Id = 'c0000000-0000-0000-0000-000000000004';

// UUID v7 标准 36 位连字符形式（新建行 ID 断言用）。
final uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// 科室管理服务单元测试（SQLite :memory:）：列表、详情、三种挂载方式的
/// 新增校验与 ID 回读、字段级修改、删除与下级阻止。
void main() {
  late SqliteGateway db;
  late DepartmentService service;

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
    await db.executeDirect('''
CREATE TABLE SYS_DEPARTMENT (
  ID TEXT PRIMARY KEY NOT NULL,
  PARENT_ID TEXT, -- 上级科室ID
  CODE TEXT NOT NULL, -- 科室代码
  NAME TEXT NOT NULL, -- 科室名称
  ADDRESS TEXT, -- 地址
  TEL TEXT, -- 联系电话
  CAMPUS_ID TEXT, -- 所属院区ID
  HOSP_ID TEXT NOT NULL, -- 所属医院ID
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 更新时间
)''');
    // 医院 1（未设置院区）、医院 2（下设院区 3）。
    Future<void> seedHospital(String id, String code, String name) async {
      await db.execute(
        'INSERT INTO SYS_HOSPITAL (ID, CODE, NAME, PROVINCE, CITY, COUNTY, '
        'ADDRESS, TEL, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, code, name, '北京市', '北京市', '东城区', '测试路1号', '010-12345678', '2026-11-07 09:00:00'],
      );
    }

    await seedHospital(hosp1Id, 'H110101001', '示例人民医院');
    await seedHospital(hosp2Id, 'H110101002', '示例人民医院-儿童心理分院');
    await db.execute(
      'INSERT INTO SYS_CAMPUS (ID, HOSP_ID, CODE, NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?)',
      [campus3Id, hosp2Id, 'C0003', '东城院区', '2026-11-07 09:00:00'],
    );
    // 科室：1/2 直挂医院 1（无院区），3 为 2 的下级，4 挂医院 2 的院区 3。
    Future<void> seedDept(
      String id,
      String hospId,
      String? campusId,
      String? parentId,
      String code,
      String name,
    ) async {
      await db.execute(
        'INSERT INTO SYS_DEPARTMENT (ID, HOSP_ID, CAMPUS_ID, PARENT_ID, CODE, '
        'NAME, ADDRESS, TEL, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, hospId, campusId, parentId, code, name, '测试路1号', '010-87654321', '2026-11-07 09:30:00'],
      );
    }

    await seedDept(dept1Id, hosp1Id, null, null, 'D0001', '儿童保健科');
    await seedDept(dept2Id, hosp1Id, null, null, 'D0002', '儿童心理科');
    await seedDept(dept3Id, hosp1Id, null, dept2Id, 'D0003', '儿童心理门诊');
    await seedDept(dept4Id, hosp2Id, campus3Id, null, 'D0004', '儿童心理科');
    service = DepartmentService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listAll：全量按院区、上级、ID 排序（固定 UUID 按字符串序）', () async {
    final departments = await service.listAll();
    expect(departments.map((d) => d.id), [dept1Id, dept2Id, dept3Id, dept4Id]);
    expect(departments.first.hospId, hosp1Id);
    expect(departments.first.campusId, isNull);
    expect(departments[2].parentId, dept2Id);
    expect(departments.last.hospId, hosp2Id);
    expect(departments.last.campusId, campus3Id);
  });

  test('getById：查详情；不存在 ID 报错', () async {
    final department = await service.getById(dept3Id);
    expect(department.name, '儿童心理门诊');
    expect(department.parentId, dept2Id);
    expect(department.hospId, hosp1Id);
    expect(department.address, '测试路1号');
    expect(department.tel, '010-87654321');

    // 主键为 UUID 字符串，任意未种子化的取值（含乱串）均走「不存在」路径
    await expectLater(
      service.getById('999'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('create：直挂医院成功（医院未设置院区），ID 前置生成', () async {
    final created = await service.create(
      hospId: hosp1Id,
      code: 'D0005',
      name: '发育行为科',
      address: '测试路2号',
      tel: '010-11112222',
    );
    // 服务在 INSERT 前生成 UUID v7 并以新 ID 回读
    expect(uuidPattern.hasMatch(created.id), isTrue);
    expect(created.hospId, hosp1Id);
    expect(created.campusId, isNull);
    expect(created.parentId, isNull);
    expect(created.code, 'D0005');

    final rows = await db.query(
      'SELECT CAMPUS_ID, PARENT_ID, CREATE_TIME FROM SYS_DEPARTMENT WHERE ID = ?',
      [created.id],
    );
    expect(rows.rows.single[0], isNull);
    expect(rows.rows.single[1], isNull);
    // CREATE_TIME 由 Dart 侧生成绑定
    expect(rows.rows.single[2], isNotEmpty);
  });

  test('create：挂院区下成功', () async {
    final created = await service.create(
      hospId: hosp2Id,
      campusId: campus3Id,
      code: 'D0006',
      name: '儿童保健科',
    );
    expect(uuidPattern.hasMatch(created.id), isTrue);
    expect(created.hospId, hosp2Id);
    expect(created.campusId, campus3Id);
    expect(created.parentId, isNull);
  });

  test('create：下级科室成功并继承上级院区归属', () async {
    // 上级直挂医院（无院区）→ 下级同样无院区
    final underHospital = await service.create(
      hospId: hosp1Id,
      parentId: dept2Id,
      code: 'D0007',
      name: '心理咨询室',
    );
    expect(underHospital.parentId, dept2Id);
    expect(underHospital.campusId, isNull);
    // 上级挂院区 → 下级继承院区
    final underCampus = await service.create(
      hospId: hosp2Id,
      parentId: dept4Id,
      code: 'D0008',
      name: '心理咨询室',
    );
    expect(underCampus.parentId, dept4Id);
    expect(underCampus.campusId, campus3Id);
  });

  test('create：医院已设置院区时也允许直挂医院下（2026-11-10 取消强制挂院区限制）', () async {
    final direct = await service.create(hospId: hosp2Id, code: 'D9999', name: '直挂科');
    expect(uuidPattern.hasMatch(direct.id), isTrue);
    expect(direct.hospId, hosp2Id);
    expect(direct.campusId, isNull);
    expect(direct.parentId, isNull);
    // 未设置院区的医院不受影响
    final ok = await service.create(hospId: hosp1Id, code: 'D0005', name: '发育行为科');
    expect(uuidPattern.hasMatch(ok.id), isTrue);
  });

  test('create：院区不存在或不属于该医院 / 上级科室不存在或跨医院均报错', () async {
    await expectLater(
      service.create(hospId: hosp2Id, campusId: '999', code: 'D0010', name: '孤儿科室'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('所属院区不存在'))),
    );
    // 院区 3 属医院 2，挂到医院 1 名下按不存在处理
    await expectLater(
      service.create(hospId: hosp1Id, campusId: campus3Id, code: 'D0011', name: '跨院科室'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('所属院区不存在'))),
    );
    await expectLater(
      service.create(hospId: hosp1Id, parentId: '999', code: 'D0012', name: '孤儿下级'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('上级科室不存在'))),
    );
    // 科室 4 属医院 2，作为医院 1 的上级被拒
    await expectLater(
      service.create(hospId: hosp1Id, parentId: dept4Id, code: 'D0013', name: '跨院下级'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('不能跨医院挂载'))),
    );
  });

  test('create：代码重复 / 同级名称重复 / 必填缺失 / 超长 / 医院不存在均报错', () async {
    await expectLater(
      service.create(hospId: hosp1Id, code: 'D0001', name: '重码科室'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('科室代码已存在'))),
    );
    // 同为医院 1 直挂顶层，与科室 1 同名冲突
    await expectLater(
      service.create(hospId: hosp1Id, code: 'D0014', name: '儿童保健科'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('同级下科室名称已存在'))),
    );
    // 同为科室 2 的下级，与科室 3 同名冲突
    await expectLater(
      service.create(hospId: hosp1Id, parentId: dept2Id, code: 'D0015', name: '儿童心理门诊'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('同级下科室名称已存在'))),
    );
    // 名称与另一挂载点同名不冲突：院区 3 下已有「儿童心理科」（科室 4），
    // 医院院区 3 下建「儿童保健科」、科室 1 下建「儿童心理门诊」均成功
    final okCampus = await service.create(hospId: hosp2Id, campusId: campus3Id, code: 'D0016', name: '儿童保健科');
    expect(okCampus.campusId, campus3Id);
    final okChild = await service.create(hospId: hosp1Id, parentId: dept1Id, code: 'D0017', name: '儿童心理门诊');
    expect(okChild.parentId, dept1Id);

    await expectLater(
      service.create(hospId: hosp1Id, code: '  ', name: '无代码'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('科室代码不能为空'))),
    );
    await expectLater(
      service.create(hospId: hosp1Id, code: 'D0018', name: ' '),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('科室名称不能为空'))),
    );
    await expectLater(
      service.create(hospId: hosp1Id, code: 'D0019', name: '超长', address: '测' * 101),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('地址不能超过'))),
    );
    // ID 不再校验数字格式，未知取值按「医院不存在」处理
    await expectLater(
      service.create(hospId: 'x', code: 'D0020', name: '非法'),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('所属医院不存在'))),
    );
  });

  test('update：改名称、清空可空列、改代码', () async {
    final updated = await service.update(dept3Id, {
      'name': '心理评估室',
      'address': null,
      'code': 'D0003X',
    });
    expect(updated.name, '心理评估室');
    expect(updated.address, isNull);
    expect(updated.code, 'D0003X');

    final rows = await db.query(
      'SELECT NAME, ADDRESS, UPDATE_TIME FROM SYS_DEPARTMENT WHERE ID = ?',
      [dept3Id],
    );
    expect(rows.rows.single[0], '心理评估室');
    expect(rows.rows.single[1], isNull);
    expect(rows.rows.single[2], isNotEmpty);
  });

  test('update：同级改名判重 / 与自身同值不算重复', () async {
    // 科室 1 改为「儿童心理科」与同级（医院 1 直挂）科室 2 冲突
    await expectLater(
      service.update(dept1Id, {'name': '儿童心理科'}),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('同级下科室名称已存在'))),
    );
    // 与自身同值不算重复
    final ok = await service.update(dept1Id, {'code': 'D0001', 'name': '儿童保健科'});
    expect(ok.code, 'D0001');
    expect(ok.name, '儿童保健科');
  });

  test('update：归属字段不可改 / 必填列置空 / 未知字段报错', () async {
    for (final key in ['hospId', 'campusId', 'parentId']) {
      await expectLater(
        service.update(dept1Id, {key: '9'}),
        throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
      );
    }
    await expectLater(
      service.update(dept1Id, {'name': null}),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('科室名称不能为空'))),
    );
    await expectLater(
      service.update(dept1Id, {'id': '2'}),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('delete：删除成功；不存在报错', () async {
    expect(await service.delete(dept1Id), 1);
    final remain = await db.query('SELECT ID FROM SYS_DEPARTMENT ORDER BY ID');
    expect(remain.rows.expand((r) => r), [dept2Id, dept3Id, dept4Id]);

    await expectLater(
      service.delete(dept1Id),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('delete：存在下级科室时阻止删除', () async {
    await expectLater(
      service.delete(dept2Id),
      throwsA(isA<DepartmentException>().having((e) => e.message, 'message', '请先删除下级科室后，再删除科室')),
    );
    // 先删下级 3 再删 2 即可成功
    expect(await service.delete(dept3Id), 1);
    expect(await service.delete(dept2Id), 1);
  });
}
