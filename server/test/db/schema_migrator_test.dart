import 'dart:convert';
import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/database/migrator/migrations/base/migration.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:test/test.dart';

import '../support/test_divisions.dart';

void main() {
  late SqliteGateway db;
  late String divisionsDir;
  // v2 起迁移含 dataFix（存量明文加密），全量迁移需注入密钥。
  final cipher = FieldCipher.fromMasterKeyBase64(
    base64Encode(utf8.encode('0123456789abcdef0123456789abcdef')),
  );

  setUp(() async {
    // v3 全量迁移的 seed 读注入的小份数据文件，不依赖 assets 真实数据。
    divisionsDir = setUpTestDivisionsCsv();
    db = await SqliteGateway.start(':memory:');
  });

  tearDown(() {
    db.close();
    clearTestDivisionsCsv(divisionsDir);
  });

  /// 查询当前库中的全部表名。
  Future<Set<String>> tableNames() async => (await db.query(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  )).rows.map((row) => row.first!).toSet();

  test('空库全量迁移：建表并记录版本', () async {
    final applied = await SchemaMigrator(db, fieldCipher: cipher).migrate();
    expect(applied.map((m) => m.version), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33]);

    final tables = await tableNames();
    expect(
      tables,
      containsAll([
        'SYS_USER',
        'SYS_LOGIN_LOG',
        'SYS_SCHEMA_VERSION',
        'BASE_ADMIN_DIVISIONS',
        'SYS_OPERATION_LOG',
        'SYS_HOSPITAL',
        'SYS_CAMPUS',
        'SYS_DEPARTMENT',
        'SYS_MENU',
        'SYS_ROLE',
        'SYS_ROLE_PERMISSION',
        'BASE_DICT',
        'BASE_DICT_ITEM',
        'BASE_HIGH_RISK_FACTOR',
        'BASE_HIGH_RISK_FACTOR_EXCLUSION',
        'BASE_HOLIDAY',
        'BASE_GUIDANCE_TEMPLATE',
        'BASE_GUIDANCE_TEMPLATE_ITEM',
      ]),
    );

    final versions = await db.query(
      'SELECT VERSION, DESCRIPTION FROM SYS_SCHEMA_VERSION',
    );
    expect(versions.rows, [
      ['1', '基础表：SYS_USER、SYS_LOGIN_LOG'],
      ['2', contains('PHONE_HMAC')],
      ['3', contains('行政区划')],
      ['4', contains('操作日志')],
      ['5', contains('医院')],
      ['6', contains('院区')],
      ['7', contains('SYS_USER')],
      ['8', contains('ROLE_CODE')],
      ['9', contains('科室')],
      ['10', contains('菜单')],
      ['11', contains('角色')],
      ['12', contains('SYS_USER_ROLE')],
      ['13', contains('AVATAR_IMAGE')],
      ['14', contains('数据字典')],
      ['15', contains('儿童建档')],
      ['16', contains('扩容')],
      ['17', contains('儿童照片表')],
      ['18', contains('科室维度')],
      ['19', contains('高危因素')],
      ['20', contains('儿童高危因素表')],
      ['21', contains('互斥规则')],
      ['22', contains('REMARK')],
      ['23', contains('PHOTO_THUMB')],
      ['24', contains('HIGH_RISK_FACTOR_ID')],
      ['25', contains('初筛记录表')],
      ['26', contains('儿童转诊表')],
      ['27', contains('法定节假日')],
      ['28', contains('GUIDANCE')],
      ['29', contains('指导建议自定义模板')],
      ['30', contains('CHILD_REFERRAL 列重命名')],
      ['31', contains('CHILD_APPOINTMENT')],
      ['32', contains('指导建议模板')],
      ['33', contains('删除 ASD_INITIAL_SCREENING_GUIDANCE')],
    ]);

    // 新建库 v20 建表已含 REMARK，v22 条件补列应幂等跳过（列仍在且仅一列）
    final remarkCols = await db.query(
      "SELECT COUNT(*) AS CNT FROM pragma_table_info('CHILD_HIGH_RISK_FACTOR') WHERE name = 'REMARK'",
    );
    expect(remarkCols.rowsAsMaps.first['CNT'], '1');

    // 新建库 v23 补列后 CHILD_PHOTO 应含缩略图列
    final photoCols = await db.query(
      "SELECT COUNT(*) AS CNT FROM pragma_table_info('CHILD_PHOTO') WHERE name = 'PHOTO_THUMB'",
    );
    expect(photoCols.rowsAsMaps.first['CNT'], '1');

    // 新建库 v24 改名后 CHILD_HIGH_RISK_FACTOR 应含 HIGH_RISK_FACTOR_ID 列
    final factorCols = await db.query(
      "SELECT COUNT(*) AS CNT FROM pragma_table_info('CHILD_HIGH_RISK_FACTOR') WHERE name = 'HIGH_RISK_FACTOR_ID'",
    );
    expect(factorCols.rowsAsMaps.first['CNT'], '1');
  });

  test('重复执行为空操作', () async {
    await SchemaMigrator(db, fieldCipher: cipher).migrate();
    final again = await SchemaMigrator(db, fieldCipher: cipher).migrate();
    expect(again, isEmpty);
  });

  test('增量迁移只执行缺失版本', () async {
    const v1 = DbMigration(
      version: 1,
      description: '一',
      common: ['CREATE TABLE A (ID INTEGER)'],
    );
    const v2 = DbMigration(
      version: 2,
      description: '二',
      common: ['CREATE TABLE B (ID INTEGER)'],
    );

    await SchemaMigrator(db, migrations: [v1]).migrate();
    final applied = await SchemaMigrator(db, migrations: [v1, v2]).migrate();

    expect(applied.map((m) => m.version), [2]);
    expect(await tableNames(), containsAll(['A', 'B']));
    final count = await db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_SCHEMA_VERSION',
    );
    expect(count.rowsAsMaps.first['CNT'], '2');
  });

  test('方言分组：只执行对应方言的语句', () async {
    const m = DbMigration(
      version: 1,
      description: '分组',
      common: ['CREATE TABLE C (ID INTEGER)'],
      dm: ['CREATE TABLE ONLY_DM (ID INT)'],
      sqlite: ['CREATE TABLE ONLY_SQLITE (ID INTEGER)'],
    );
    await SchemaMigrator(db, migrations: [m]).migrate();

    final tables = await tableNames();
    expect(tables, contains('C'));
    expect(tables, contains('ONLY_SQLITE'));
    expect(tables, isNot(contains('ONLY_DM')));
  });

  test('seed 回调在建表语句后执行且不要求密钥', () async {
    final m = DbMigration(
      version: 1,
      description: 'seed',
      common: ['CREATE TABLE SEED_TARGET (ID INTEGER)'],
      seed: (db) => db.execute('INSERT INTO SEED_TARGET (ID) VALUES (1)'),
    );
    // 不注入 cipher：seed 迁移不依赖字段加密密钥。
    await SchemaMigrator(db, migrations: [m]).migrate();

    final rows = await db.query('SELECT ID FROM SEED_TARGET');
    expect(rows.rows, [
      ['1'],
    ]);
  });

  test('未纳入迁移管理的存量结构直接报错', () async {
    await db.executeDirect('CREATE TABLE SYS_USER (ID INT)');
    await expectLater(
      SchemaMigrator(db).migrate(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('存量结构'),
        ),
      ),
    );
  });

  test('版本号必须严格递增', () {
    final bad = [
      const DbMigration(version: 2, description: '二'),
      const DbMigration(version: 1, description: '一'),
    ];
    expect(
      () => SchemaMigrator(db, migrations: bad),
      throwsA(isA<StateError>()),
    );
  });
}
