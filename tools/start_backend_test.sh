#!/usr/bin/env bash
# =====================================================================
# 启动测试环境后端（http://localhost:8090，从部署副本运行）。
#
# 后端产物由 ./tools/deploy_test.sh 部署到 <部署根>/backend/server/build
# （含镜像的 common 副本 <部署根>/backend/common，相对结构与开发仓库一致），
# 与开发仓库的 server/build 解耦——测试后端运行中不再锁住 server/build，
# 开发侧 dart_frog build / F5 不受影响。
#
# 与开发环境共用开发库（DM8 AICMHCS 模式）；库内敏感字段是开发环境密钥
# 加密的，因此经 AICMHCS_FIELD_KEY_FILE 绝对路径沿用开发仓库同一把字段
# 加密密钥（server/data/aicmhcs.field.key，单一来源不复制副本），
# 否则登录解密会失败。
#
# 可配置环境变量：
#   AICMHCS_TEST_ROOT  测试环境部署根目录（默认 /d/AiCMHCS-Test）
#   AICMHCS_TEST_PORT  监听端口（默认 8090）
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="${AICMHCS_TEST_ROOT:-/d/AiCMHCS-Test}"
PORT="${AICMHCS_TEST_PORT:-8090}"

# 清理旧测试实例，避免端口占用
PID=$(netstat -ano | grep "0.0.0.0:$PORT" | grep LISTENING | awk '{print $NF}' | head -1 || true)
if [ -n "${PID:-}" ]; then
  echo "停止旧测试后端进程 PID=$PID"
  taskkill //F //PID "$PID" >/dev/null 2>&1 || true
  sleep 1
fi

if [ ! -f "$TEST_ROOT/backend/server/build/bin/server.dart" ]; then
  echo "缺少后端部署副本（$TEST_ROOT/backend/server/build/bin/server.dart），请先执行 ./tools/deploy_test.sh" >&2
  exit 1
fi
if [ ! -f "$ROOT/server/data/aicmhcs.field.key" ]; then
  echo "缺少开发字段加密密钥（server/data/aicmhcs.field.key），请先启动一次开发环境后端以生成" >&2
  exit 1
fi

echo "== 启动测试后端 http://localhost:$PORT（部署副本，共用开发库）=="
cd "$TEST_ROOT/backend/server/build"
export PORT
export AICMHCS_DB_DRIVER="${AICMHCS_DB_DRIVER:-dm}"
export AICMHCS_FIELD_KEY_FILE="$ROOT/server/data/aicmhcs.field.key"
export DM_HOME="${DM_HOME:-C:\dmdbms}"
exec dart run bin/server.dart
