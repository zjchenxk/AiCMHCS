import 'package:server/database/migrator/migrations/base/migration.dart';

/// v23：儿童照片表 CHILD_PHOTO 补 PHOTO_THUMB（照片缩略图）列。
///
/// PHOTO（竖版 720×900）的等比缩小缩略图（180×225，四分之一等比），
/// JPEG base64 文本（与 PHOTO/AVATAR 同范式），供照片管理列表低开销
/// 展示真实照片（AVATAR 为照片中心方阵的 320×320 方图，非等比缩略）。
/// 可空列、不做存量回填：Dart 后端无图像解码能力，信创离线环境不为此
/// 引入图像处理依赖；v23 前的存量行 PHOTO_THUMB 为 NULL，读取侧客户端
/// 对 NULL 缩略图回退显示 AVATAR。
const dbMigration_202611212215 = DbMigration(
  version: 23,
  description: '儿童照片表补 PHOTO_THUMB 照片缩略图列',
  dm: [
    'ALTER TABLE CHILD_PHOTO ADD PHOTO_THUMB TEXT',
    "COMMENT ON COLUMN CHILD_PHOTO.PHOTO_THUMB IS '照片缩略图（PHOTO 等比缩小 180×225，JPEG base64 文本；v23 前的存量行为 NULL）'",
  ],
  // PostgreSQL 方言：与达梦同构，逐句对应（差异句已注释标注）。
  postgres: [
    // 差异句：PG 加列须带 COLUMN 关键字
    'ALTER TABLE CHILD_PHOTO ADD COLUMN PHOTO_THUMB TEXT',
    "COMMENT ON COLUMN CHILD_PHOTO.PHOTO_THUMB IS '照片缩略图（PHOTO 等比缩小 180×225，JPEG base64 文本；v23 前的存量行为 NULL）'",
  ],
  sqlite: [
    // SQLite 无 COMMENT ON：列注释以 `--` 形式附在语句前（须换行分隔，
    // 行尾注释会因语句串末尾无换行被解析为未闭合注释）
    '''
-- 照片缩略图（PHOTO 等比缩小 180×225，JPEG base64 文本；v23 前的存量行为 NULL）
ALTER TABLE CHILD_PHOTO ADD COLUMN PHOTO_THUMB TEXT''',
  ],
);
