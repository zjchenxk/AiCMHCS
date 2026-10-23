import 'dart:convert';

import 'package:server/db/migration.dart';
import 'package:server/db/schema_migrator.dart';
import 'package:server/db/sqlite_gateway.dart';
import 'package:server/security/field_cipher.dart';
import 'package:test/test.dart';

void main() {
  late SqliteGateway db;
  // v2 起迁移含 dataFix（存量明文加密），全量迁移需注入密钥。
  final cipher = FieldCipher.fromMasterKeyBase64(
    base64Encode(utf8.encode('0123456789abcdef0123456789abcdef')),
  );

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
  });

  tearDown(() => db.close());

  /// 查询当前库中的全部表名。
  Future<Set<String>> tableNames() async => (await db.query(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  )).rows.map((row) => row.first!).toSet();

  test('空库全量迁移：建表并记录版本', () async {
    final applied = await SchemaMigrator(db, fieldCipher: cipher).migrate();
    expect(applied.map((m) => m.version), [1, 2]);

    final tables = await tableNames();
    expect(
      tables,
      containsAll(['SYS_USER', 'SYS_LOGIN_LOG', 'SYS_SCHEMA_VERSION']),
    );

    final versions = await db.query(
      'SELECT VERSION, DESCRIPTION FROM SYS_SCHEMA_VERSION',
    );
    expect(versions.rows, [
      ['1', '基础表：SYS_USER、SYS_LOGIN_LOG'],
      ['2', contains('PHONE_HMAC')],
    ]);
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
