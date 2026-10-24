import 'package:server/database/engine/database_gateway.dart';
import 'package:server/database/migrator/migrations/base/migration.dart';
import 'package:server/utils/admin_division_importer.dart';

/// v3：行政区划基础表 BASE_ADMIN_DIVISIONS（单表承载省/市/县/乡/村五级，
/// CODE 为主键、PARENT_CODE 成树，PARENT_CODE 上建索引供级联查询）。
///
/// 数据本体在 assets/divisions/divisions.csv（约 70 万行，不内联进迁移
/// 代码），经 [seedAdminDivisions] 随迁移全量导入；国标版本更新时替换
/// 数据文件后执行 dart run tool/import_divisions.dart 重灌，无需新迁移。
const dbMigration_202610241630 = DbMigration(
  version: 3,
  description: '基础表：BASE_ADMIN_DIVISIONS 行政区划（seed 导入数据文件）',
  dm: [
    // DDL 幂等（IF NOT EXISTS）：seed 预检失败中断后（版本记录未写入）
    // 重跑迁移不再被「对象已存在」卡住，修复数据文件后直接重来。
    '''
CREATE TABLE IF NOT EXISTS BASE_ADMIN_DIVISIONS (
  CODE        VARCHAR(20) NOT NULL,
  NAME        VARCHAR(200) NOT NULL,
  PARENT_CODE VARCHAR(20),
  CONSTRAINT PK_BASE_ADMIN_DIVISIONS PRIMARY KEY (CODE)
)''',
    'CREATE INDEX IF NOT EXISTS IDX_BASE_ADMIN_DIVISIONS_PARENT ON BASE_ADMIN_DIVISIONS (PARENT_CODE)',
    "COMMENT ON TABLE BASE_ADMIN_DIVISIONS IS '行政区划表'",
    "COMMENT ON COLUMN BASE_ADMIN_DIVISIONS.CODE IS '行政区划代码'",
    "COMMENT ON COLUMN BASE_ADMIN_DIVISIONS.NAME IS '行政区划名称'",
    "COMMENT ON COLUMN BASE_ADMIN_DIVISIONS.PARENT_CODE IS '上级行政区划代码'",
  ],
  sqlite: [
    '''
CREATE TABLE IF NOT EXISTS BASE_ADMIN_DIVISIONS (
  -- 行政区划代码（村级最长 12 位）
  CODE        TEXT NOT NULL,
  -- 行政区划名称
  NAME        TEXT NOT NULL,
  -- 上级行政区划代码（省级为 NULL）
  PARENT_CODE TEXT,
  CONSTRAINT PK_BASE_ADMIN_DIVISIONS PRIMARY KEY (CODE)
)''',
    'CREATE INDEX IF NOT EXISTS IDX_BASE_ADMIN_DIVISIONS_PARENT ON BASE_ADMIN_DIVISIONS (PARENT_CODE)',
  ],
  seed: seedAdminDivisions,
);

/// v3 seed：全量导入行政区划基础数据。
///
/// 幂等：先清空再分批重灌（见 AdminDivisionImporter 说明），中断后
/// 重跑自愈，不要求字段加密密钥。
Future<void> seedAdminDivisions(DatabaseGateway db) => importAdminDivisions(db);
