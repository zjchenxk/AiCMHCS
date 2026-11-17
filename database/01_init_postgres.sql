-- =====================================================================
-- AiCMHCS 智慧儿童心理保健系统 —— PostgreSQL 初始化库与应用角色
-- 以超级用户（postgres）经 psql 执行（可重复执行，整库重建）：
--   psql -U postgres -f database/01_init_postgres.sql
-- 结构迁移由后端启动时自动完成；演示账号：
--   cd server && AICMHCS_DB_DRIVER=postgres dart run tool/seed_demo_data.dart
-- =====================================================================

-- 重建应用数据库（DROP 会删除库内全部旧对象）
DROP DATABASE IF EXISTS aicmhcs;

-- 应用角色（DROP 防残留口令/权限漂移；角色被库对象依赖时会因
-- DROP DATABASE 已清空对象而成功）
DROP ROLE IF EXISTS aicmhcs;

CREATE ROLE aicmhcs LOGIN PASSWORD 'Aicmhcs@2026';

CREATE DATABASE aicmhcs
  ENCODING 'UTF8'
  TEMPLATE template0
  OWNER aicmhcs;

-- 进入应用库，授权 public 模式建表（PostgreSQL 15+ 默认收回该权限；
-- 结构迁移的建表/COMMENT ON 等语句均由应用账号执行）
\c aicmhcs
GRANT ALL ON SCHEMA public TO aicmhcs;
