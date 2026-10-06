-- =====================================================================
-- AiCMHCS 智慧儿童心理保健系统 —— 01 初始化表空间与应用账号
-- 以 SYSDBA 执行（scripts/init_db.sh 会自动完成）
-- =====================================================================
WHENEVER SQLERROR CONTINUE

-- 表空间已存在则跳过（首次初始化时创建，数据文件默认 128MB 自动扩展）
DECLARE
  v_cnt INT;
BEGIN
  SELECT COUNT(*) INTO v_cnt
    FROM DBA_TABLESPACES
   WHERE TABLESPACE_NAME = 'AICMHCS';
  IF v_cnt = 0 THEN
    EXECUTE IMMEDIATE 'CREATE TABLESPACE AICMHCS '
      || 'DATAFILE ''C:\dmdbms\data\DAMENG\AICMHCS.DBF'' '
      || 'SIZE 128 AUTOEXTEND ON NEXT 64';
  END IF;
END;
/

-- 重建应用账号（CASCADE 会删除该用户模式下的全部旧对象，可重复初始化）
DROP USER AICMHCS CASCADE;

CREATE USER AICMHCS IDENTIFIED BY "Aicmhcs@2026"
  DEFAULT TABLESPACE AICMHCS;

-- RESOURCE：允许在自有模式下建表、建索引等
GRANT RESOURCE TO AICMHCS;

EXIT;
