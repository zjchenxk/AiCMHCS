import 'package:server/database/engine/database_gateway.dart';
import 'package:server/database/migrator/migrations/base/migration.dart';

/// v22：儿童高危因素表 CHILD_HIGH_RISK_FACTOR 补 REMARK（备注）列。
///
/// REMARK 最初是直接补写进 v20 迁移文件的建表语句；先于该修改应用过
/// v20 的存量库（如开发库达梦）版本号已记录到 20+、不会重放 v20，导致
/// 表内缺列而服务端 SELECT/INSERT 报「无效的列名[REMARK]」。本版本按
/// 方言探测列是否已存在：缺失才 ALTER 补列（新建库 v20 已含列、此处
/// 幂等跳过），列定义与 v20 建表语句一致（dm/postgres VARCHAR(100) 可
/// 空，sqlite TEXT 可空）。
const dbMigration_202611202145 = DbMigration(
  version: 22,
  description: '儿童高危因素表补 REMARK 备注列',
  seed: _addRemarkColumnIfMissing,
);

/// 按方言探测 CHILD_HIGH_RISK_FACTOR 是否已有 REMARK 列，缺失才补列。
Future<void> _addRemarkColumnIfMissing(DatabaseGateway db) async {
  final hasRemark = switch (db.dialect) {
    DbDialect.dm =>
      (await db.query(
            "SELECT COUNT(*) AS CNT FROM USER_TAB_COLUMNS WHERE TABLE_NAME = 'CHILD_HIGH_RISK_FACTOR' AND COLUMN_NAME = 'REMARK'",
            const [],
          )).rowsAsMaps.first['CNT'] !=
          '0',
    DbDialect.postgres =>
      (await db.query(
            "SELECT COUNT(*) AS CNT FROM information_schema.columns WHERE table_name = 'child_high_risk_factor' AND column_name = 'remark'",
            const [],
          )).rowsAsMaps.first['CNT'] !=
          '0',
    DbDialect.sqlite =>
      (await db.query(
            "SELECT COUNT(*) AS CNT FROM pragma_table_info('CHILD_HIGH_RISK_FACTOR') WHERE name = 'REMARK'",
            const [],
          )).rowsAsMaps.first['CNT'] !=
          '0',
  };
  if (!hasRemark) {
    await db.executeDirect(
      switch (db.dialect) {
        // 达梦按 Oracle 兼容语法用 ADD (列定义)
        DbDialect.dm => 'ALTER TABLE CHILD_HIGH_RISK_FACTOR ADD (REMARK VARCHAR(100))',
        DbDialect.postgres => 'ALTER TABLE child_high_risk_factor ADD COLUMN remark VARCHAR(100)',
        DbDialect.sqlite => 'ALTER TABLE CHILD_HIGH_RISK_FACTOR ADD COLUMN REMARK TEXT',
      },
    );
  }
}
