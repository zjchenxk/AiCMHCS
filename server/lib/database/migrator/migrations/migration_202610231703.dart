import 'package:server/database/engine/database_gateway.dart';
import 'package:server/database/migrator/migrations/base/migration.dart';
import 'package:server/utils/field_cipher.dart';

/// 结构迁移注册表：按版本号严格递增，已发布的迁移不可修改，只能追加新版本。
const dbMigration_202610231703 = DbMigration(
  version: 2,
  description: 'SYS_USER.PHONE 改存 AES-GCM 密文，新增 PHONE_HMAC 盲索引列并回填存量',
  dm: [
    'ALTER TABLE SYS_USER ADD COLUMN PHONE_HMAC VARCHAR(64)',
    // 扩宽容纳密文（11 位号码密文约 55 字符；达梦 VARCHAR 按字节计，
    // 预留充足）。
    'ALTER TABLE SYS_USER MODIFY PHONE VARCHAR(256)',
    'CREATE INDEX IDX_SYS_USER_PHONE_HMAC ON SYS_USER (PHONE_HMAC)',
    "COMMENT ON COLUMN SYS_USER.PHONE IS '联系电话（AES-256-GCM 密文，v1: 前缀）'",
    "COMMENT ON COLUMN SYS_USER.PHONE_HMAC IS '联系电话 HMAC-SHA256 盲索引（应用侧密钥，供精确查询）'",
  ],
  sqlite: [
    '''
-- 联系电话 HMAC-SHA256 盲索引（应用侧密钥，供精确查询）
ALTER TABLE SYS_USER ADD COLUMN PHONE_HMAC TEXT
''',
    'CREATE INDEX IDX_SYS_USER_PHONE_HMAC ON SYS_USER (PHONE_HMAC)',
  ],
  dataFix: encryptExistingPhones,
);

/// v2 数据订正：存量明文联系电话加密写回并计算盲索引。
///
/// 幂等：已是密文（`v<N>:` 前缀）或 PHONE 为空的行跳过，中断后重跑
/// 不会重复处理；行级 UPDATE 走 execute（网关约定不重试，无重复写）。
Future<void> encryptExistingPhones(
  DatabaseGateway db,
  FieldCipher cipher,
) async {
  final rows = await db.query(
    'SELECT ID, PHONE FROM SYS_USER WHERE PHONE IS NOT NULL',
  );
  for (final row in rows.rowsAsMaps) {
    final id = row['ID'];
    final phone = row['PHONE'];
    if (id == null || phone == null || FieldCipher.looksEncrypted(phone)) {
      continue;
    }
    await db.execute(
      'UPDATE SYS_USER SET PHONE = ?, PHONE_HMAC = ? WHERE ID = ?',
      [
        await cipher.seal(FieldCipher.phonePurpose, phone),
        await cipher.mac(FieldCipher.phonePurpose, phone),
        id,
      ],
    );
  }
}
