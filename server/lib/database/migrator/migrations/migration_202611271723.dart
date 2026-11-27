import 'package:server/database/migrator/migrations/base/migration.dart';

/// v33：删除指导建议自定义模板表 ASD_INITIAL_SCREENING_GUIDANCE（v29 建）。
///
/// 需求 2026-11-27：初筛页指导建议选择改从指导建议模板项目表
/// BASE_GUIDANCE_TEMPLATE_ITEM（v32 建）按模板 ID 读取（默认模板
/// 01a21bb5-b4df-7000-bb50-bbb3c24a025d，由运维侧按医院自行录入），
/// v29 表及其服务/路由随之下线。存量自定义模板数据不搬迁——由医院
/// 按新体系重新录入（该表为业务自维护数据，非结构资产）。
const dbMigration_202611271723 = DbMigration(
  version: 33,
  description: '删除 ASD_INITIAL_SCREENING_GUIDANCE 指导建议自定义模板表（功能并入指导建议模板管理项目表）',
  dm: [
    'DROP TABLE ASD_INITIAL_SCREENING_GUIDANCE',
  ],
  // PostgreSQL 方言：与达梦同构。
  postgres: [
    'DROP TABLE ASD_INITIAL_SCREENING_GUIDANCE',
  ],
  sqlite: [
    'DROP TABLE ASD_INITIAL_SCREENING_GUIDANCE',
  ],
);
