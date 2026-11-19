#!/usr/bin/env bash
# =====================================================================
# 启动测试环境后端（http://localhost:8090，从 server/build 生产产物运行）。
#
# 与开发环境共用开发库（DM8 AICMHCS 模式）；工作目录为 server/build，
# 产物自身的数据目录（data/）与开发的 server/data 隔离，但库内敏感字段
# 是开发环境密钥加密的，因此经 AICMHCS_FIELD_KEY_FILE 绝对路径沿用同一
# 把字段加密密钥（server/data/aicmhcs.field.key），否则登录解密会失败。
#
# 可配置环境变量：AICMHCS_TEST_PORT（默认 8090）
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${AICMHCS_TEST_PORT:-8090}"

# 清理旧测试实例，避免端口占用
PID=$(netstat -ano | grep "0.0.0.0:$PORT" | grep LISTENING | awk '{print $NF}' | head -1 || true)
if [ -n "${PID:-}" ]; then
  echo "停止旧测试后端进程 PID=$PID"
  taskkill //F //PID "$PID" >/dev/null 2>&1 || true
  sleep 1
fi

if [ ! -f "$ROOT/server/build/bin/server.dart" ]; then
  echo "缺少后端产物（server/build/bin/server.dart），请先执行 ./tools/deploy_test.sh" >&2
  exit 1
fi
if [ ! -f "$ROOT/server/data/aicmhcs.field.key" ]; then
  echo "缺少开发字段加密密钥（server/data/aicmhcs.field.key），请先启动一次开发环境后端以生成" >&2
  exit 1
fi

echo "== 启动测试后端 http://localhost:$PORT（共用开发库）=="
cd "$ROOT/server/build"
export PORT
export AICMHCS_DB_DRIVER="${AICMHCS_DB_DRIVER:-dm}"
export AICMHCS_FIELD_KEY_FILE="$ROOT/server/data/aicmhcs.field.key"
export DM_HOME="${DM_HOME:-C:\dmdbms}"
exec dart run bin/server.dart
