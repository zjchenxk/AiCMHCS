import 'package:server/database/migrator/migrations/base/migration.dart';

/// v13：SYS_USER 新增 AVATAR_IMAGE 用户头像列（base64 图片，与
/// SIGNATURE_IMAGE 手写签名同策略——纯文本列、由服务层限长）。
const dbMigration_202611101030 = DbMigration(
  version: 13,
  description: 'SYS_USER 新增 AVATAR_IMAGE 用户头像列',
  dm: [
    'ALTER TABLE SYS_USER ADD COLUMN AVATAR_IMAGE TEXT',
    "COMMENT ON COLUMN SYS_USER.AVATAR_IMAGE IS '用户头像图片BASE64'",
  ],
  sqlite: [
    '-- 用户头像图片BASE64\nALTER TABLE SYS_USER ADD COLUMN AVATAR_IMAGE TEXT',
  ],
);
