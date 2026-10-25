import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/admin_division_service.dart';
import 'package:test/test.dart';

/// 行政区划管理服务单元测试（SQLite :memory:）：层级查询、新增校验、
/// 改名、子树统计与级联删除。
void main() {
  late SqliteGateway db;
  late AdminDivisionService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    await db.executeDirect('''
CREATE TABLE BASE_ADMIN_DIVISIONS (
  CODE TEXT NOT NULL,
  NAME TEXT NOT NULL,
  PARENT_CODE TEXT,
  CONSTRAINT PK_BASE_ADMIN_DIVISIONS PRIMARY KEY (CODE)
)''');
    await db.executeDirect(
      'CREATE INDEX IDX_BASE_ADMIN_DIVISIONS_PARENT ON BASE_ADMIN_DIVISIONS (PARENT_CODE)',
    );
    // 树形：北京市 → 东城区 → 东华门街道 → 多福巷社区；兄弟分支西城区、天津市。
    await db.execute(
      'INSERT INTO BASE_ADMIN_DIVISIONS (CODE, NAME, PARENT_CODE) VALUES (?, ?, ?)',
      ['110000', '北京市', null],
    );
    await db.execute(
      'INSERT INTO BASE_ADMIN_DIVISIONS (CODE, NAME, PARENT_CODE) VALUES (?, ?, ?)',
      ['110100', '市辖区', '110000'],
    );
    await db.execute(
      'INSERT INTO BASE_ADMIN_DIVISIONS (CODE, NAME, PARENT_CODE) VALUES (?, ?, ?)',
      ['110101', '东城区', '110100'],
    );
    await db.execute(
      'INSERT INTO BASE_ADMIN_DIVISIONS (CODE, NAME, PARENT_CODE) VALUES (?, ?, ?)',
      ['110102', '西城区', '110100'],
    );
    await db.execute(
      'INSERT INTO BASE_ADMIN_DIVISIONS (CODE, NAME, PARENT_CODE) VALUES (?, ?, ?)',
      ['110101001', '东华门街道', '110101'],
    );
    await db.execute(
      'INSERT INTO BASE_ADMIN_DIVISIONS (CODE, NAME, PARENT_CODE) VALUES (?, ?, ?)',
      ['110101001001', '多福巷社区', '110101001'],
    );
    await db.execute(
      'INSERT INTO BASE_ADMIN_DIVISIONS (CODE, NAME, PARENT_CODE) VALUES (?, ?, ?)',
      ['120000', '天津市', null],
    );
    service = AdminDivisionService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listChildren：省级列表（parentCode 为空）含 hasChildren 并按代码排序', () async {
    final provinces = await service.listChildren();
    expect(provinces.map((d) => d.code), ['110000', '120000']);
    expect(provinces.first.name, '北京市');
    expect(provinces.first.parentCode, isNull);
    expect(provinces.first.hasChildren, isTrue);
  });

  test('listChildren：按 parentCode 查子级，叶子节点 hasChildren 为 false', () async {
    final cities = await service.listChildren(parentCode: '110000');
    expect(cities.map((d) => d.code), ['110100']);
    expect(cities.single.parentCode, '110000');

    final villages = await service.listChildren(parentCode: '110101001');
    expect(villages.single.name, '多福巷社区');
    expect(villages.single.hasChildren, isFalse);

    expect(await service.listChildren(parentCode: '999999'), isEmpty);
  });

  test('create：新增子级成功（parentCode 存在）', () async {
    final created = await service.create(code: '110103', name: '崇文区', parentCode: '110100');
    expect(created.code, '110103');
    expect(created.parentCode, '110100');

    final rows = await db.query(
      'SELECT NAME, PARENT_CODE FROM BASE_ADMIN_DIVISIONS WHERE CODE = ?',
      ['110103'],
    );
    expect(rows.rows.single, ['崇文区', '110100']);
  });

  test('create：上级行政区划为村/居委会级（12 位）时报错', () async {
    await expectLater(
      service.create(code: '999999', name: '村民小组', parentCode: '110101001001'),
      throwsA(isA<AdminDivisionException>().having((e) => e.message, 'message', contains('最末级'))),
    );
  });

  test('create：新增省级（parentCode 为空字符串按 null 处理）', () async {
    final created = await service.create(code: '440000', name: '广东省', parentCode: '');
    expect(created.parentCode, isNull);
  });

  test('create：代码重复 / 上级不存在 / 代码格式非法 / 名称为空均报错', () async {
    await expectLater(
      service.create(code: '110000', name: '北京'),
      throwsA(isA<AdminDivisionException>().having((e) => e.message, 'message', contains('已存在'))),
    );
    await expectLater(
      service.create(code: '110103', name: '崇文区', parentCode: '999999'),
      throwsA(isA<AdminDivisionException>().having((e) => e.message, 'message', contains('上级'))),
    );
    await expectLater(
      service.create(code: 'abc', name: '非法'),
      throwsA(isA<AdminDivisionException>().having((e) => e.message, 'message', contains('2~12 位数字'))),
    );
    await expectLater(
      service.create(code: '1', name: '位数不足'),
      throwsA(isA<AdminDivisionException>()),
    );
    await expectLater(
      service.create(code: '110103', name: '  '),
      throwsA(isA<AdminDivisionException>().having((e) => e.message, 'message', contains('名称不能为空'))),
    );
    await expectLater(
      service.create(code: '110103', name: '崇文区', parentCode: '110103'),
      throwsA(isA<AdminDivisionException>().having((e) => e.message, 'message', contains('自身'))),
    );
  });

  test('update：改名成功且不影响其他行；不存在时报错', () async {
    final updated = await service.update('110101', newName: '东城区（旧）');
    expect(updated.name, '东城区（旧）');

    final rows = await db.query(
      'SELECT NAME FROM BASE_ADMIN_DIVISIONS WHERE CODE = ?',
      ['110101'],
    );
    expect(rows.rows.single.single, '东城区（旧）');

    await expectLater(
      service.update('999999', newName: '不存在'),
      throwsA(isA<AdminDivisionException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('update：改编码级联更新全部下级父引用', () async {
    final updated = await service.update('110101', newCode: '110199');
    expect(updated.code, '110199');

    final rows = await db.query(
      'SELECT CODE, PARENT_CODE FROM BASE_ADMIN_DIVISIONS WHERE CODE IN (?, ?) ORDER BY CODE',
      ['110199', '110101001'],
    );
    expect(rows.rows, [
      ['110101001', '110199'],
      ['110199', '110100'],
    ]);
    // 旧编码不再存在
    final old = await db.query(
      'SELECT COUNT(*) AS CNT FROM BASE_ADMIN_DIVISIONS WHERE CODE = ?',
      ['110101'],
    );
    expect(old.rowsAsMaps.first['CNT'], '0');
  });

  test('update：同时改编码与名称', () async {
    final updated = await service.update('110102', newCode: '110299', newName: '西城区（新）');
    expect(updated.code, '110299');
    expect(updated.name, '西城区（新）');
  });

  test('update：新编码重复 / 格式非法 / 名称空时报错', () async {
    await expectLater(
      service.update('110101', newCode: '120000'),
      throwsA(isA<AdminDivisionException>().having((e) => e.message, 'message', contains('已存在'))),
    );
    await expectLater(
      service.update('110101', newCode: 'abc'),
      throwsA(isA<AdminDivisionException>().having((e) => e.message, 'message', contains('2~12 位数字'))),
    );
    await expectLater(
      service.update('110101', newName: '  '),
      throwsA(isA<AdminDivisionException>().having((e) => e.message, 'message', contains('名称不能为空'))),
    );
  });

  test('subtreeCount：统计含自身的多层子树规模', () async {
    expect(await service.subtreeCount('110000'), 6);
    expect(await service.subtreeCount('110101'), 3);
    expect(await service.subtreeCount('110101001001'), 1);
  });

  test('deleteSubtree：级联删除全部下级、兄弟分支不受影响', () async {
    final deleted = await service.deleteSubtree('110101');
    expect(deleted, 3);

    final remain = await db.query(
      'SELECT CODE FROM BASE_ADMIN_DIVISIONS ORDER BY CODE',
    );
    expect(remain.rows.expand((r) => r), ['110000', '110100', '110102', '120000']);
  });

  test('deleteSubtree：删除省级删除整棵子树', () async {
    final deleted = await service.deleteSubtree('110000');
    expect(deleted, 6);

    final remain = await db.query(
      'SELECT CODE FROM BASE_ADMIN_DIVISIONS ORDER BY CODE',
    );
    expect(remain.rows.expand((r) => r), ['120000']);
  });

  test('deleteSubtree：删除叶子节点；不存在时报错', () async {
    expect(await service.deleteSubtree('110101001001'), 1);

    await expectLater(
      service.deleteSubtree('999999'),
      throwsA(isA<AdminDivisionException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });
}
