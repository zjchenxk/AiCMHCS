import 'package:server/database/migrator/migrations/base/migration.dart';

/// v10：系统表 SYS_MENU 菜单表（系统菜单权限管理的项目清单：上级项目
/// 经 PARENT_ID 自关联构成「模块→菜单→操作」树，ITEM_TYPE 区分项目
/// 类型 1-模块/2-菜单/3-操作，不建物理外键——下级项目存在时禁止删除
/// 上级项目，由服务层校验控制；ID 自增；ITEM_CODE 全表唯一；按需求
/// 设计不设时间列）。
const dbMigration_202611081600 = DbMigration(
  version: 10,
  description: '系统表：SYS_MENU 菜单表',
  dm: [
    '''
CREATE TABLE IF NOT EXISTS SYS_MENU(
    ID BIGINT NOT NULL IDENTITY(1,1),
    PARENT_ID BIGINT,
    ITEM_CODE VARCHAR(10) NOT NULL,
    ITEM_NAME VARCHAR(50) NOT NULL,
    ITEM_TYPE CHAR(1) NOT NULL,
    MENU_ROUTE VARCHAR(100),
    MENU_ICON VARCHAR(100),
    PRIMARY KEY (ID)
)''',
    "COMMENT ON TABLE SYS_MENU IS '菜单表'",
    "COMMENT ON COLUMN SYS_MENU.ID IS '主键'",
    "COMMENT ON COLUMN SYS_MENU.PARENT_ID IS '上级项目ID'",
    "COMMENT ON COLUMN SYS_MENU.ITEM_CODE IS '项目编码'",
    "COMMENT ON COLUMN SYS_MENU.ITEM_NAME IS '项目名称'",
    "COMMENT ON COLUMN SYS_MENU.ITEM_TYPE IS '项目类型：1-模块，2-菜单，3-操作'",
    "COMMENT ON COLUMN SYS_MENU.MENU_ROUTE IS '菜单路由'",
    "COMMENT ON COLUMN SYS_MENU.MENU_ICON IS '菜单图标'",
  ],
  sqlite: [
    '''
CREATE TABLE IF NOT EXISTS SYS_MENU (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
  PARENT_ID INTEGER, -- 上级项目ID
  ITEM_CODE TEXT NOT NULL, -- 项目编码
  ITEM_NAME TEXT NOT NULL, -- 项目名称
  ITEM_TYPE TEXT NOT NULL, -- 项目类型：1-模块，2-菜单，3-操作
  MENU_ROUTE TEXT, -- 菜单路由
  MENU_ICON TEXT -- 菜单图标
)''',
  ],
);
