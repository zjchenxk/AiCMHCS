import 'package:server/database/migrator/migrations/base/migration.dart';

/// v28：孤独症初筛记录表 ASD_INITIAL_SCREENING 补指导建议与下次检查日期。
///
/// GUIDANCE 指导建议（VARCHAR(1000) 可空多行文本；界面支持自由输入、
/// 自定义模板选入与 AI 生成，按 UTF-8 字节数限长）；NEXT_CHECK_DATE
/// 下次检查日期（DATE 可空；初筛未见异常时客户端按出生日期推下一年龄
/// 段自动计算，周末与法定节假日顺延到工作日，手动选择不受限；初筛
/// 异常时清空）。两列均为可空列、不做存量回填。
const dbMigration_202611251000 = DbMigration(
  version: 28,
  description: '孤独症初筛：ASD_INITIAL_SCREENING 补 GUIDANCE 指导建议与 NEXT_CHECK_DATE 下次检查日期',
  dm: [
    'ALTER TABLE ASD_INITIAL_SCREENING ADD GUIDANCE VARCHAR(1000)',
    'ALTER TABLE ASD_INITIAL_SCREENING ADD NEXT_CHECK_DATE DATE',
    "COMMENT ON COLUMN ASD_INITIAL_SCREENING.GUIDANCE IS '指导建议（可空多行文本）'",
    "COMMENT ON COLUMN ASD_INITIAL_SCREENING.NEXT_CHECK_DATE IS '下次检查日期（可空；未见异常时按出生日期推下一年龄段自动计算，周末/法定节假日顺延到工作日）'",
  ],
  // PostgreSQL 方言：与达梦同构，逐句对应（差异句已注释标注）。
  postgres: [
    // 差异句：PG 加列须带 COLUMN 关键字
    'ALTER TABLE ASD_INITIAL_SCREENING ADD COLUMN GUIDANCE VARCHAR(1000)',
    'ALTER TABLE ASD_INITIAL_SCREENING ADD COLUMN NEXT_CHECK_DATE DATE',
    "COMMENT ON COLUMN ASD_INITIAL_SCREENING.GUIDANCE IS '指导建议（可空多行文本）'",
    "COMMENT ON COLUMN ASD_INITIAL_SCREENING.NEXT_CHECK_DATE IS '下次检查日期（可空；未见异常时按出生日期推下一年龄段自动计算，周末/法定节假日顺延到工作日）'",
  ],
  sqlite: [
    '''
-- 指导建议（可空多行文本）
ALTER TABLE ASD_INITIAL_SCREENING ADD COLUMN GUIDANCE TEXT''',
    '''
-- 下次检查日期（可空；未见异常时按出生日期推下一年龄段自动计算，周末/法定节假日顺延到工作日）
ALTER TABLE ASD_INITIAL_SCREENING ADD COLUMN NEXT_CHECK_DATE TEXT''',
  ],
);
