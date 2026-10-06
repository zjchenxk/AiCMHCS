#!/usr/bin/env bash
# =====================================================================
# AiCMHCS 数据库初始化脚本（Git Bash / bash 运行）
#
# 依次执行 database/ 下的 01/02/03 脚本：
#   01 表空间 + 应用账号 AICMHCS（以 SYSDBA 执行）
#   02 建表、03 演示数据（以 AICMHCS 执行）
#
# 本库为 GB18030 字符集（SF_GET_UNICODE_FLAG()=0），而仓库内 SQL 为
# UTF-8，因此执行前经 iconv 转 GBK 再交给 DIsql。
#
# 可配置环境变量：
#   DM_HOME        达梦安装目录（默认 /c/dmdbms）
#   DM_HOST        数据库主机（默认 LOCALHOST）
#   DM_PORT        数据库端口（默认 5236）
#   DM_SYSDBA_PWD  SYSDBA 口令（默认为开发机口令，生产环境务必覆盖）
#   APP_DB_PWD     应用账号 AICMHCS 口令（默认 Aicmhcs@2026）
# =====================================================================
set -euo pipefail

DM_HOME="${DM_HOME:-/c/dmdbms}"
DM_HOST="${DM_HOST:-LOCALHOST}"
DM_PORT="${DM_PORT:-5236}"
DM_SYSDBA_PWD="${DM_SYSDBA_PWD:-!QAZ2wsx@123321}"
APP_DB_PWD="${APP_DB_PWD:-Aicmhcs@2026}"

DISQL="$DM_HOME/bin/DIsql.exe"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== AiCMHCS 数据库初始化（$DM_HOST:$DM_PORT）=="

# UTF-8 -> GBK，并注入 CONN 连接串
convert() { # $1=源文件 $2=目标文件 $3=连接串
  iconv -f UTF-8 -t GBK "$1" > "$2" || {
    echo "iconv 转码失败：$1（请确认文件为 UTF-8）" >&2
    exit 1
  }
  printf 'WHENEVER SQLERROR EXIT\n%s\n' "$3" | iconv -f UTF-8 -t GBK > "$2.tmp"
  cat "$2.tmp" "$2" > "$2.final" && mv "$2.final" "$2" && rm -f "$2.tmp"
}

run_disql() { # $1=脚本文件
  MSYS_NO_PATHCONV=1 "$DISQL" /NOLOG "\`$1"
}

conn_sysdba="CONN SYSDBA/\"$DM_SYSDBA_PWD\"@$DM_HOST:$DM_PORT;"
conn_app="CONN AICMHCS/\"$APP_DB_PWD\"@$DM_HOST:$DM_PORT;"

convert "$ROOT/database/01_init_schema.sql" "$WORK/01.sql" "$conn_sysdba"
convert "$ROOT/database/02_create_tables.sql" "$WORK/02.sql" "$conn_app"
convert "$ROOT/database/03_demo_data.sql" "$WORK/03.sql" "$conn_app"

for f in 01 02 03; do
  echo "---- 执行 $f ----"
  run_disql "$(cygpath -w "$WORK/$f.sql")"
done

echo "== 初始化完成。演示账号：admin/Admin@123、doctor01/Doctor@123、teacher01/Teacher@123、parent01/Parent@123 =="
