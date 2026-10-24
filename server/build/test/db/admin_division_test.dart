import 'dart:convert';
import 'dart:io';

import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/utils/admin_division_importer.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:test/test.dart';

import '../support/test_divisions.dart';

/// 行政区划导入器与 v3 迁移集成测试（SQLite :memory:，数据源为注入的
/// 小份临时 CSV，见 testDivisionsCsv helper）。
void main() {
  late SqliteGateway db;
  late String divisionsDir;
  final cipher = FieldCipher.fromMasterKeyBase64(
    'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=',
  );

  setUp(() async {
    divisionsDir = setUpTestDivisionsCsv();
    db = await SqliteGateway.start(':memory:');
  });

  tearDown(() {
    db.close();
    clearTestDivisionsCsv(divisionsDir);
  });

  test('全量迁移自动建表并导入行政区划', () async {
    final applied = await SchemaMigrator(
      db,
      fieldCipher: cipher,
    ).migrate();
    expect(applied.map((m) => m.version), [1, 2, 3]);

    final count = await db.query(
      'SELECT COUNT(*) AS CNT FROM BASE_ADMIN_DIVISIONS',
    );
    final total = int.parse(count.rowsAsMaps.first['CNT']!);
    expect(total, greaterThan(0));

    // 省级 PARENT_CODE 为 NULL；村级行 parent 链完整。
    final province = await db.query(
      "SELECT NAME, PARENT_CODE FROM BASE_ADMIN_DIVISIONS WHERE CODE = '110000'",
    );
    expect(province.rows, [
      ['北京市', null],
    ]);
    final village = await db.query(
      "SELECT NAME, PARENT_CODE FROM BASE_ADMIN_DIVISIONS WHERE CODE = '110101001001'",
    );
    expect(village.rows, [
      ['多福巷社区', '110101001'],
    ]);
  });

  test('全量重灌幂等：行数与内容不变', () async {
    await SchemaMigrator(db, fieldCipher: cipher).migrate();
    final before = await db.query(
      'SELECT COUNT(*) AS CNT FROM BASE_ADMIN_DIVISIONS',
    );
    final again = await importAdminDivisions(db);
    final after = await db.query(
      'SELECT COUNT(*) AS CNT FROM BASE_ADMIN_DIVISIONS',
    );
    expect(again, int.parse(after.rowsAsMaps.first['CNT']!));
    expect(after.rows, before.rows);

    // 重灌后抽查仍在（先清空后导入的回读验证）。
    final province = await db.query(
      "SELECT NAME FROM BASE_ADMIN_DIVISIONS WHERE CODE = '440100'",
    );
    expect(province.rows, [
      ['广州市'],
    ]);
  });

  test('数据文件路径解析命中资源文件', () {
    final path = resolveDivisionsCsvPath();
    expect(File(path).existsSync(), isTrue);
  });

  test('gzip 压缩数据文件按魔数自动识别', () async {
    await db.executeDirect('''
CREATE TABLE BASE_ADMIN_DIVISIONS (
  CODE TEXT NOT NULL,
  NAME TEXT NOT NULL,
  PARENT_CODE TEXT,
  CONSTRAINT PK_BASE_ADMIN_DIVISIONS PRIMARY KEY (CODE)
)''');
    final dir = await Directory.systemTemp.createTemp('divisions_gz_test');
    final csv = File('${dir.path}${Platform.pathSeparator}mini.csv.gz');
    await csv.writeAsBytes(
      gzip.encode(utf8.encode('CODE,NAME,PARENT_CODE\n110000,北京市,\n')),
    );
    try {
      final count = await importAdminDivisions(db, csvPath: csv.path);
      expect(count, 1);
      final row = (await db.query(
        'SELECT NAME, PARENT_CODE FROM BASE_ADMIN_DIVISIONS WHERE CODE = ?',
        ['110000'],
      )).rows.single;
      expect(row, ['北京市', null]);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('预检：科学计数法 CODE 报错且库保持原样', () async {
    await db.executeDirect('''
CREATE TABLE BASE_ADMIN_DIVISIONS (
  CODE TEXT NOT NULL,
  NAME TEXT NOT NULL,
  PARENT_CODE TEXT,
  CONSTRAINT PK_BASE_ADMIN_DIVISIONS PRIMARY KEY (CODE)
)''');
    await db.execute(
      "INSERT INTO BASE_ADMIN_DIVISIONS (CODE, NAME) VALUES ('999999', '既有行')",
    );
    final dir = await Directory.systemTemp.createTemp('divisions_precheck');
    final csv = File('${dir.path}${Platform.pathSeparator}sci.csv');
    await csv.writeAsString(
      'CODE,NAME,PARENT_CODE\n110000,北京市,\n1.10101E+11,某社区,110101001001\n',
    );
    try {
      await expectLater(
        importAdminDivisions(db, csvPath: csv.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('科学计数法'), contains('重新导出')),
          ),
        ),
      );
      // 预检在清空/写入之前，库中原有数据不被触碰。
      final count = await db.query(
        'SELECT COUNT(*) AS CNT FROM BASE_ADMIN_DIVISIONS',
      );
      expect(count.rowsAsMaps.first['CNT'], '1');
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('预检：重复 CODE 报错', () async {
    final dir = await Directory.systemTemp.createTemp('divisions_dup');
    final csv = File('${dir.path}${Platform.pathSeparator}dup.csv');
    await csv.writeAsString(
      'CODE,NAME,PARENT_CODE\n110000,北京市,\n110000,北京,110000\n',
    );
    try {
      await expectLater(
        precheckDivisionsCsv(csv.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('重复'), contains('110000')),
          ),
        ),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('最短码体系（省2/市4/县6/乡9位）可正常导入', () async {
    await db.executeDirect('''
CREATE TABLE BASE_ADMIN_DIVISIONS (
  CODE TEXT NOT NULL,
  NAME TEXT NOT NULL,
  PARENT_CODE TEXT,
  CONSTRAINT PK_BASE_ADMIN_DIVISIONS PRIMARY KEY (CODE)
)''');
    final dir = await Directory.systemTemp.createTemp('divisions_short_code');
    final csv = File('${dir.path}${Platform.pathSeparator}short.csv');
    await csv.writeAsString(
      'CODE,NAME,PARENT_CODE\n11,北京市,\n1101,市辖区,11\n110101,东城区,1101\n110101001,东华门街道,110101\n',
    );
    try {
      final count = await importAdminDivisions(db, csvPath: csv.path);
      expect(count, 4);
      final province = await db.query(
        'SELECT PARENT_CODE FROM BASE_ADMIN_DIVISIONS WHERE CODE = ?',
        ['11'],
      );
      expect(province.rows.single.first, isNull);
      final town = await db.query(
        'SELECT PARENT_CODE FROM BASE_ADMIN_DIVISIONS WHERE CODE = ?',
        ['110101001'],
      );
      expect(town.rows.single.first, '110101');
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('坏行报错带行号', () async {
    await db.executeDirect('''
CREATE TABLE BASE_ADMIN_DIVISIONS (
  CODE TEXT NOT NULL,
  NAME TEXT NOT NULL,
  PARENT_CODE TEXT,
  CONSTRAINT PK_BASE_ADMIN_DIVISIONS PRIMARY KEY (CODE)
)''');
    final dir = await Directory.systemTemp.createTemp('divisions_test');
    final csv = File('${dir.path}${Platform.pathSeparator}bad.csv');
    await csv.writeAsString(
      'CODE,NAME,PARENT_CODE\n110000,北京市\n',
    );
    try {
      await expectLater(
        importAdminDivisions(db, csvPath: csv.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('第 2 行'),
          ),
        ),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
