import 'package:server/database/migrator/migrations/base/migration.dart';

/// v6：系统表 SYS_CAMPUS 院区表（归属医院经 HOSP_ID 关联 SYS_HOSPITAL，
/// 不建物理外键——医院下存在院区时禁止删除医院，由服务层校验控制；
/// ID 自增；时间列由 Dart 侧生成后绑定，不用 SQL 端时间函数）。
const dbMigration_202611060910 = DbMigration(
  version: 6,
  description: '系统表：SYS_CAMPUS 院区表',
  dm: [
    '''
CREATE TABLE IF NOT EXISTS SYS_CAMPUS(
    ID BIGINT NOT NULL IDENTITY(1,1),
    HOSP_ID BIGINT NOT NULL,
    CODE VARCHAR(20),
    NAME VARCHAR(100) NOT NULL,
    ADDRESS VARCHAR(100),
    TEL VARCHAR(20),
    CREATE_TIME TIMESTAMP(0) NOT NULL,
    UPDATE_TIME TIMESTAMP(0),
    PRIMARY KEY (ID)
)''',
    "COMMENT ON TABLE SYS_CAMPUS IS '院区表'",
    "COMMENT ON COLUMN SYS_CAMPUS.ID IS '主键'",
    "COMMENT ON COLUMN SYS_CAMPUS.HOSP_ID IS '所属医院ID'",
    "COMMENT ON COLUMN SYS_CAMPUS.CODE IS '院区代码'",
    "COMMENT ON COLUMN SYS_CAMPUS.NAME IS '院区名称'",
    "COMMENT ON COLUMN SYS_CAMPUS.ADDRESS IS '院区地址'",
    "COMMENT ON COLUMN SYS_CAMPUS.TEL IS '联系电话'",
    "COMMENT ON COLUMN SYS_CAMPUS.CREATE_TIME IS '创建时间'",
    "COMMENT ON COLUMN SYS_CAMPUS.UPDATE_TIME IS '修改时间'",
  ],
  sqlite: [
    '''
CREATE TABLE IF NOT EXISTS SYS_CAMPUS (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
  HOSP_ID INTEGER NOT NULL, -- 所属医院ID
  CODE TEXT, -- 院区代码
  NAME TEXT NOT NULL, -- 院区名称
  ADDRESS TEXT, -- 院区地址
  TEL TEXT, -- 联系电话
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 修改时间
)''',
  ],
);
