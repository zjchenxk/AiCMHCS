import 'package:server/database/migrator/migrations/base/migration.dart';

/// v8：SYS_USER 清理旧列——ROLE_CODE（角色已由 v7 搬迁至 USER_TYPE +
/// PERMISSION_LEVEL）与 LAST_LOGIN_AT（登录时间已由 SYS_LOGIN_LOG 审计覆盖）。
/// 双方言语法一致放 common；SQLite DROP COLUMN 需 3.35+（Windows 系统
/// winsqlite3.dll 与单机版随包分发的官方库均满足）。
const dbMigration_202611071501 = DbMigration(
  version: 8,
  description: 'SYS_USER 清理旧列：ROLE_CODE、LAST_LOGIN_AT',
  common: [
    'ALTER TABLE SYS_USER DROP COLUMN ROLE_CODE',
    'ALTER TABLE SYS_USER DROP COLUMN LAST_LOGIN_AT',
  ],
);
