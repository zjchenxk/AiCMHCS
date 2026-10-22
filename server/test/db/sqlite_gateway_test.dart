import 'dart:io';

import 'package:server/db/database_gateway.dart';
import 'package:server/db/sqlite_gateway.dart';
import 'package:test/test.dart';

void main() {
  late SqliteGateway db;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
  });

  tearDown(() => db.close());

  test('建表、参数化写入与查询（含中文与 NULL）', () async {
    await db.executeDirect(
      'CREATE TABLE T (ID INTEGER PRIMARY KEY AUTOINCREMENT, NAME TEXT, AGE INT)',
    );
    final inserted = await db.execute(
      'INSERT INTO T (NAME, AGE) VALUES (?, ?)',
      ['王小明', null],
    );
    expect(inserted, 1);

    final result = await db.query('SELECT ID, NAME, AGE FROM T');
    expect(result.columns, ['ID', 'NAME', 'AGE']);
    // 所有列以字符串返回（与达梦网关契约一致），NULL 为 null。
    expect(result.rows, [
      ['1', '王小明', null],
    ]);
  });

  test('execute 返回受影响行数', () async {
    await db.executeDirect('CREATE TABLE T (ID INT, NAME TEXT)');
    await db.execute('INSERT INTO T (ID, NAME) VALUES (?, ?)', [1, 'a']);
    await db.execute('INSERT INTO T (ID, NAME) VALUES (?, ?)', [2, 'b']);
    final updated = await db.execute('UPDATE T SET NAME = ? WHERE ID = ?', [
      'c',
      1,
    ]);
    expect(updated, 1);
    final deleted = await db.execute('DELETE FROM T WHERE ID = ?', [2]);
    expect(deleted, 1);
  });

  test('rowsAsMaps 按列名取值', () async {
    await db.executeDirect('CREATE TABLE T (CODE TEXT, VALUE INT)');
    await db.execute('INSERT INTO T (CODE, VALUE) VALUES (?, ?)', ['k', 42]);
    final row = (await db.query('SELECT CODE, VALUE FROM T')).rowsAsMaps.single;
    expect(row['CODE'], 'k');
    expect(row['VALUE'], '42');
  });

  test('ping 探活', () async {
    await expectLater(db.ping(), completes);
  });

  test('SQL 错误抛出 DbException', () async {
    await expectLater(
      db.query('SELECT * FROM NOT_EXIST_TABLE'),
      throwsA(isA<DbException>()),
    );
  });

  test('文件库自动创建父目录，重开后数据仍在', () async {
    final dir = Directory.systemTemp.createTempSync('aicmhcs_db_test');
    final path =
        '${dir.path}${Platform.pathSeparator}nested'
        '${Platform.pathSeparator}aicmhcs.db';
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows 下 WAL/SHM 句柄释放有延迟，删不掉就留给系统临时目录清理。
      }
    });

    final db1 = await SqliteGateway.start(path);
    await db1.executeDirect('CREATE TABLE T (ID INT)');
    await db1.close();

    final db2 = await SqliteGateway.start(path);
    final tables = await db2.query(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'T'",
    );
    expect(tables.rows, isNotEmpty);
    await db2.close();
  });
}
