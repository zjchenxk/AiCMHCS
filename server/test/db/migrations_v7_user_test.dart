// v7/v8 迁移（SYS_USER 表改造 + 清理旧列）测试：模拟「已应用 v1 的存量库」
// 升级路径——ROLE_CODE 原值搬迁至 USER_TYPE、PERMISSION_LEVEL 按角色回填、
// 时间列改名且值保留、旧列删除、盲索引就位、回填幂等。
import 'dart:convert';

import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/database/migrator/migrations/migration_202611071500.dart';
import 'package:server/database/migrator/migrations/migrations.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:test/test.dart';

import '../support/test_divisions.dart';

void main() {
  late SqliteGateway db;
  late FieldCipher cipher;
  late String divisionsDir;

  setUp(() async {
    // 全量 migrate 会连带应用 v3（seed 读注入的小份数据文件）。
    divisionsDir = setUpTestDivisionsCsv();
    db = await SqliteGateway.start(':memory:');
    cipher = FieldCipher.fromMasterKeyBase64(
      base64Encode(utf8.encode('0123456789abcdef0123456789abcdef')),
    );
    // 只应用 v1，模拟迁移机制启用期的存量库结构。
    await SchemaMigrator(
      db,
      migrations: dbMigrations.sublist(0, 1),
    ).migrate();
  });

  tearDown(() {
    db.close();
    clearTestDivisionsCsv(divisionsDir);
  });

  Future<void> insertUser(String userCode, String roleCode) => db.execute(
    'INSERT INTO SYS_USER '
    '(USER_CODE, PASSWORD, USER_NAME, ROLE_CODE, STATUS, CREATED_AT, '
    'UPDATED_AT) VALUES (?, ?, ?, ?, 1, ?, ?)',
    [userCode, 'salt:hash', '用户', roleCode, '2026-01-01 08:00:00', '2026-01-02 09:00:00'],
  );

  /// 查询 SYS_USER 当前的全部列名。
  Future<Set<String>> userColumns() async => (await db.query(
    "SELECT name FROM pragma_table_info('SYS_USER')",
  )).rows.map((row) => row.single!).toSet();

  test('存量角色原值搬迁至 USER_TYPE，PERMISSION_LEVEL 按角色回填', () async {
    await insertUser('admin01', 'ADMIN');
    await insertUser('doctor01', 'DOCTOR');
    await insertUser('teacher01', 'TEACHER');

    final applied = await SchemaMigrator(db, fieldCipher: cipher).migrate();
    expect(applied.map((m) => m.version), [2, 3, 4, 5, 6, 7, 8]);

    final rows = (await db.query(
      'SELECT USER_CODE, USER_TYPE, PERMISSION_LEVEL FROM SYS_USER '
      'ORDER BY USER_CODE',
    )).rows;
    expect(rows, [
      // ADMIN→2、DOCTOR→1；TEACHER 不在新值域内，原值保留、权限按其余→0。
      ['admin01', 'ADMIN', '2'],
      ['doctor01', 'DOCTOR', '1'],
      ['teacher01', 'TEACHER', '0'],
    ]);
  });

  test('时间列改名且存量值保留，旧列 ROLE_CODE / LAST_LOGIN_AT 已删除', () async {
    await insertUser('admin01', 'ADMIN');
    await SchemaMigrator(db, fieldCipher: cipher).migrate();

    final columns = await userColumns();
    expect(columns, containsAll(['CREATE_TIME', 'UPDATE_TIME']));
    expect(columns, isNot(contains('CREATED_AT')));
    expect(columns, isNot(contains('UPDATED_AT')));
    expect(columns, isNot(contains('ROLE_CODE')));
    expect(columns, isNot(contains('LAST_LOGIN_AT')));

    final row = (await db.query(
      'SELECT CREATE_TIME, UPDATE_TIME FROM SYS_USER WHERE USER_CODE = ?',
      ['admin01'],
    )).rows.single;
    expect(row, ['2026-01-01 08:00:00', '2026-01-02 09:00:00']);
  });

  test('新列就位：身份证盲索引有索引，新列可写入', () async {
    await SchemaMigrator(db, fieldCipher: cipher).migrate();

    final idx = await db.query(
      'SELECT COUNT(*) AS CNT FROM sqlite_master '
      "WHERE name = 'IDX_SYS_USER_ID_CARD_HMAC'",
    );
    expect(idx.rowsAsMaps.first['CNT'], '1');

    // 身份证号按等保口径 seal/mac 成对写入（独立 purpose 派生子钥）。
    await db.execute(
      'INSERT INTO SYS_USER '
      '(USER_CODE, PASSWORD, USER_NAME, USER_TYPE, PERMISSION_LEVEL, '
      'ID_CARD_NO, ID_CARD_NO_HMAC, STATUS, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)',
      [
        'nurse01',
        'salt:hash',
        '护士',
        'NURSE',
        0,
        await cipher.seal(FieldCipher.idCardNoPurpose, '110101199001011234'),
        await cipher.mac(FieldCipher.idCardNoPurpose, '110101199001011234'),
        '2026-11-07 10:00:00',
      ],
    );
    final hit = await db.query(
      'SELECT USER_CODE FROM SYS_USER WHERE ID_CARD_NO_HMAC = ?',
      [await cipher.mac(FieldCipher.idCardNoPurpose, '110101199001011234')],
    );
    expect(hit.rows.single.single, 'nurse01');
  });

  test('回填幂等：v7 状态下重复执行 dataFix 不再改动已搬迁数据', () async {
    await insertUser('admin01', 'ADMIN');
    await insertUser('doctor01', 'DOCTOR');
    // 只应用到 v7（ROLE_CODE 尚存、搬迁已完成），重复调用 dataFix 验证
    // IS NULL 判重条件对已处理行不再改动（中断重跑不重复处理）。
    await SchemaMigrator(
      db,
      migrations: dbMigrations.sublist(0, 7),
      fieldCipher: cipher,
    ).migrate();
    final before = (await db.query(
      'SELECT USER_TYPE, PERMISSION_LEVEL FROM SYS_USER ORDER BY USER_CODE',
    )).rows;

    await migrateRoleToUserType(db, cipher);
    await migrateRoleToUserType(db, cipher);

    final after = (await db.query(
      'SELECT USER_TYPE, PERMISSION_LEVEL FROM SYS_USER ORDER BY USER_CODE',
    )).rows;
    expect(after, before);
  });
}
