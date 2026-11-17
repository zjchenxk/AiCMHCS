import 'package:server/database/migrator/migrations/base/migration.dart';

/// v18：SYS_USER_ROLE 增加科室维度。
///
/// 用户角色关联由「用户-角色」二元组升级为「用户-角色-科室」三元组
/// （复合主键扩展为 USER_ID+ROLE_ID+DEPT_ID）：同一角色可按科室细分
/// 授权，记录各角色适用的科室（科室必填——勾选角色须至少设置一个
/// 适用科室，由用户服务兜底校验）。DEPT_ID 存 SYS_DEPARTMENT.ID；
/// 约定哨兵值 '00000000-0000-0000-0000-000000000000' 仅作存量关联行
/// 的「未指定科室」回填占位（升级用户须重新编辑保存补选科室，读取
/// 侧归一为空列表）——不用空串占位：达梦按 Oracle 兼容语义把空串
/// 作 NULL（撞 NOT NULL）、CHAR 定长列又按定长补空格，空串哨兵在
/// 达梦侧语义不稳定。新保存链路不再产生哨兵行。
///
/// 达梦 / PostgreSQL 走「加列（存量行由 DEFAULT 回填哨兵）→ 删旧主键
/// → 建新主键」三步（PG 内联主键的自动约束名为 <表>_pkey）；SQLite
/// 不支持改主键，按建影子表 → 拷数据 → 换名重建。首句先清残留影子
/// 表：迁移逐条自动提交、失败重跑整条迁移，影子表可能留有上次半途
/// 数据，清掉重拷即幂等（影子表只含半途拷贝、不含业务数据，无丢失
/// 风险；不违反「迁移不 DROP 业务表」铁律）。
const dbMigration_202611171000 = DbMigration(
  version: 18,
  description: '用户角色：SYS_USER_ROLE 增加科室维度（USER_ID+ROLE_ID+DEPT_ID 复合主键）',
  dm: [
    "ALTER TABLE SYS_USER_ROLE ADD DEPT_ID CHAR(36) DEFAULT '00000000-0000-0000-0000-000000000000' NOT NULL",
    'ALTER TABLE SYS_USER_ROLE DROP PRIMARY KEY',
    'ALTER TABLE SYS_USER_ROLE ADD CONSTRAINT PK_SYS_USER_ROLE PRIMARY KEY (USER_ID, ROLE_ID, DEPT_ID)',
    "COMMENT ON COLUMN SYS_USER_ROLE.DEPT_ID IS '科室ID（UUID v7；00000000-0000-0000-0000-000000000000=未指定，适用全部科室）'",
  ],
  // PostgreSQL 方言：与达梦同构，逐句对应（差异句已注释标注）。
  postgres: [
    "ALTER TABLE SYS_USER_ROLE ADD DEPT_ID CHAR(36) DEFAULT '00000000-0000-0000-0000-000000000000' NOT NULL",
    // 差异句：删主键须指名约束（PG 无 DROP PRIMARY KEY 语法；内联主键
    // 自动命名为小写 <表>_pkey）
    'ALTER TABLE SYS_USER_ROLE DROP CONSTRAINT SYS_USER_ROLE_pkey',
    'ALTER TABLE SYS_USER_ROLE ADD CONSTRAINT PK_SYS_USER_ROLE PRIMARY KEY (USER_ID, ROLE_ID, DEPT_ID)',
    "COMMENT ON COLUMN SYS_USER_ROLE.DEPT_ID IS '科室ID（UUID v7；00000000-0000-0000-0000-000000000000=未指定，适用全部科室）'",
  ],
  sqlite: [
    'DROP TABLE IF EXISTS SYS_USER_ROLE_NEW',
    '''
CREATE TABLE SYS_USER_ROLE_NEW (
  USER_ID TEXT NOT NULL, -- 用户ID
  ROLE_ID TEXT NOT NULL, -- 角色ID
  DEPT_ID TEXT NOT NULL, -- 科室ID（00000000-0000-0000-0000-000000000000=未指定，适用全部科室）
  PRIMARY KEY (USER_ID, ROLE_ID, DEPT_ID)
)''',
    "INSERT INTO SYS_USER_ROLE_NEW (USER_ID, ROLE_ID, DEPT_ID) SELECT USER_ID, ROLE_ID, '00000000-0000-0000-0000-000000000000' FROM SYS_USER_ROLE",
    'DROP TABLE SYS_USER_ROLE',
    'ALTER TABLE SYS_USER_ROLE_NEW RENAME TO SYS_USER_ROLE',
  ],
);
