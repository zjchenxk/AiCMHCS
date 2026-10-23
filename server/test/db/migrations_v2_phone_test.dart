// v2 迁移（PHONE 加密存储 + 盲索引列）测试：模拟「已应用 v1 的存量库」
// 升级路径——存量明文被加密回填、盲索引可精确命中、回填幂等、未注入
// 密钥时执行任何语句前即报错。
import 'dart:convert';

import 'package:server/db/migrations.dart';
import 'package:server/db/schema_migrator.dart';
import 'package:server/db/sqlite_gateway.dart';
import 'package:server/security/field_cipher.dart';
import 'package:test/test.dart';

void main() {
  late SqliteGateway db;
  late FieldCipher cipher;

  setUp(() async {
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

  tearDown(() => db.close());

  Future<void> insertUser(String userCode, String? phone) => db.execute(
    'INSERT INTO SYS_USER '
    '(USER_CODE, PASSWORD, USER_NAME, ROLE_CODE, PHONE, STATUS) '
    "VALUES (?, 'salt:hash', '用户', 'DOCTOR', ?, 1)",
    [userCode, phone],
  );

  test('存量明文手机号升级后变为密文并写入盲索引，可精确查询', () async {
    await insertUser('legacy', '13800000001');

    final applied = await SchemaMigrator(db, fieldCipher: cipher).migrate();
    expect(applied.map((m) => m.version), [2]);

    final row = (await db.query(
      'SELECT PHONE, PHONE_HMAC FROM SYS_USER WHERE USER_CODE = ?',
      ['legacy'],
    )).rowsAsMaps.single;
    expect(row['PHONE'], startsWith('v1:'));
    // 库内不残留明文。
    expect(row['PHONE'], isNot(contains('13800000001')));
    expect(
      row['PHONE_HMAC'],
      await cipher.mac(FieldCipher.phonePurpose, '13800000001'),
    );
    // 与库中密文可用同一把钥匙还原。
    expect(
      await cipher.open(FieldCipher.phonePurpose, row['PHONE']),
      '13800000001',
    );

    // 盲索引等值查询可命中（应用侧计算 HMAC 后绑定参数，全 ASCII）。
    final hit = await db.query(
      'SELECT USER_CODE FROM SYS_USER WHERE PHONE_HMAC = ?',
      [await cipher.mac(FieldCipher.phonePurpose, ' 13800000001 ')],
    );
    expect(hit.rows.single.single, 'legacy');
  });

  test('PHONE 为 NULL 的行保持 NULL，盲索引列同为 NULL', () async {
    await insertUser('no-phone', null);
    await SchemaMigrator(db, fieldCipher: cipher).migrate();

    final row = (await db.query(
      'SELECT PHONE, PHONE_HMAC FROM SYS_USER WHERE USER_CODE = ?',
      ['no-phone'],
    )).rowsAsMaps.single;
    expect(row['PHONE'], isNull);
    expect(row['PHONE_HMAC'], isNull);
  });

  test('回填幂等：重复执行对已加密行不再改动', () async {
    await insertUser('legacy', '13800000001');
    await SchemaMigrator(db, fieldCipher: cipher).migrate();
    final before = (await db.query(
      'SELECT PHONE, PHONE_HMAC FROM SYS_USER ORDER BY ID',
    )).rows;

    await encryptExistingPhones(db, cipher);

    final after = (await db.query(
      'SELECT PHONE, PHONE_HMAC FROM SYS_USER ORDER BY ID',
    )).rows;
    expect(after, before);
  });

  test('待应用迁移含 dataFix 但未注入密钥时，执行任何语句前即报错', () async {
    await insertUser('legacy', '13800000001');
    await expectLater(
      SchemaMigrator(db).migrate(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('FieldCipher'),
        ),
      ),
    );
    // 加列与索引均未执行（DDL 尚未发生，不会留下半途状态）。
    final idx = await db.query(
      "SELECT COUNT(*) AS CNT FROM sqlite_master "
      "WHERE name = 'IDX_SYS_USER_PHONE_HMAC'",
    );
    expect(idx.rowsAsMaps.first['CNT'], '0');
  });
}
