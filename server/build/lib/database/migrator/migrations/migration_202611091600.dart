import 'package:server/database/migrator/migrations/base/migration.dart';

/// v12：系统表 SYS_USER_ROLE 用户角色表。
/// 用户与角色多对多关联（复合主键 USER_ID+ROLE_ID，USER_ID 逻辑关联
/// SYS_USER、ROLE_ID 逻辑关联 SYS_ROLE），不建物理外键、无时间列（与
/// SYS_ROLE_PERMISSION 同策略）。用户保存接口带 roleIds 时全量覆盖，
/// 用户停用走 SYS_USER.STATUS（本期不做用户删除）。
const dbMigration_202611091600 = DbMigration(
  version: 12,
  description: '系统表：SYS_USER_ROLE 用户角色表',
  dm: [
    '''
CREATE TABLE IF NOT EXISTS SYS_USER_ROLE(
    USER_ID BIGINT NOT NULL,
    ROLE_ID BIGINT NOT NULL,
    PRIMARY KEY (USER_ID,ROLE_ID)
)''',
    "COMMENT ON TABLE SYS_USER_ROLE IS '用户角色表'",
    "COMMENT ON COLUMN SYS_USER_ROLE.USER_ID IS '用户ID'",
    "COMMENT ON COLUMN SYS_USER_ROLE.ROLE_ID IS '角色ID'",
  ],
  sqlite: [
    '''
CREATE TABLE IF NOT EXISTS SYS_USER_ROLE (
  USER_ID INTEGER NOT NULL, -- 用户ID
  ROLE_ID INTEGER NOT NULL, -- 角色ID
  PRIMARY KEY (USER_ID, ROLE_ID)
)''',
  ],
);
