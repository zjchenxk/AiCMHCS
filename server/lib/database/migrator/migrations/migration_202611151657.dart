import 'package:server/database/migrator/migrations/base/migration.dart';

/// v16：扩容 CHILD_INFO.ADDRESS_DETAILS 列（密文列）。
///
/// 该列为 FieldCipher 密文（列宽 = 明文最大字节数 × 1.5 + 64），v15 按
/// 建表 DDL 建为 VARCHAR(100)，反推明文上限仅 (100-64)/1.5 = 24 字节
/// ≈ 8 个汉字——「路/门牌号码」实际业务长度（如「谷阳新村三区1栋305」
/// 10 个汉字 = 30 字节）即超限。扩容为 VARCHAR(250)：明文上限提升至
/// 100 字节（100 × 1.5 + 64 = 250，≈ 33 个汉字），服务端校验口径同步
/// 放宽为 100 字节。SQLite 的 TEXT 列无长度约束，无需变更。
const dbMigration_202611151657 = DbMigration(
  version: 16,
  description: '儿童建档：扩容 CHILD_INFO.ADDRESS_DETAILS 密文列至 VARCHAR(250)',
  dm: [
    'ALTER TABLE CHILD_INFO MODIFY ADDRESS_DETAILS VARCHAR(250) NOT NULL',
  ],
);
