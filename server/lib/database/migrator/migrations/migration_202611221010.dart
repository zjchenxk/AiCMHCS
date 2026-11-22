import 'package:server/database/migrator/migrations/base/migration.dart';

/// v24：儿童高危因素表 CHILD_HIGH_RISK_FACTOR 列改名
/// HIGH_RISK_FACTOR → HIGH_RISK_FACTOR_ID。
///
/// 该列存的是高危因素字典 BASE_HIGH_RISK_FACTOR.ID（UUID v7），原名
/// 缺「_ID」后缀与同表 RISK_FACTOR_CODE/RISK_FACTOR_NAME 快照列及
/// 协议字段 highRiskFactorId 的语义不对称，统一改为 HIGH_RISK_FACTOR_ID。
/// 三方言语法差异（勿混用，见 v7 迁移先例）：达梦为
/// `ALTER COLUMN 旧名 RENAME TO 新名`，PostgreSQL/SQLite 为
/// `RENAME COLUMN 旧名 TO 新名`；改名后原列注释随列携带（dm/pg），再以
/// COMMENT ON 按新列名刷新一遍。协议字段 highRiskFactorId 不变，仅
/// 服务端行取键同步。
const dbMigration_202611221010 = DbMigration(
  version: 24,
  description: '儿童高危因素表 HIGH_RISK_FACTOR 列改名为 HIGH_RISK_FACTOR_ID',
  dm: [
    'ALTER TABLE CHILD_HIGH_RISK_FACTOR ALTER COLUMN HIGH_RISK_FACTOR RENAME TO HIGH_RISK_FACTOR_ID',
    "COMMENT ON COLUMN CHILD_HIGH_RISK_FACTOR.HIGH_RISK_FACTOR_ID IS '高危因素ID（UUID v7）'",
  ],
  // PostgreSQL 方言：与 SQLite 同用 RENAME COLUMN（差异句已注释标注）。
  postgres: [
    // 差异句：PG 列改名用 RENAME COLUMN（达梦为 ALTER COLUMN ... RENAME TO）
    'ALTER TABLE CHILD_HIGH_RISK_FACTOR RENAME COLUMN HIGH_RISK_FACTOR TO HIGH_RISK_FACTOR_ID',
    "COMMENT ON COLUMN CHILD_HIGH_RISK_FACTOR.HIGH_RISK_FACTOR_ID IS '高危因素ID（UUID v7）'",
  ],
  sqlite: ['ALTER TABLE CHILD_HIGH_RISK_FACTOR RENAME COLUMN HIGH_RISK_FACTOR TO HIGH_RISK_FACTOR_ID'],
);
