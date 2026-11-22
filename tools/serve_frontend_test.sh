#!/usr/bin/env bash
# =====================================================================
# 托管测试环境前端（http://localhost:5273，静态文件来自部署目录）。
# 前端产物由 deploy_test.sh 部署（含本地 canvaskit / noto 镜像，离线可用），
# 后端地址已在部署时改写为测试后端 8090，无需重新构建。
#
# 可配置环境变量：
#   AICMHCS_TEST_ROOT     测试环境部署根目录（默认 /d/AiCMHCS-Test，与 deploy_test.sh 一致）
#   AICMHCS_TEST_WEB_PORT 前端端口（默认 5273）
# =====================================================================
set -euo pipefail

TEST_ROOT="${AICMHCS_TEST_ROOT:-/d/AiCMHCS-Test}"
PORT="${AICMHCS_TEST_WEB_PORT:-5273}"

if [ ! -f "$TEST_ROOT/frontend/index.html" ]; then
  echo "部署目录缺少前端产物（$TEST_ROOT/frontend），请先执行 ./tools/deploy_test.sh" >&2
  exit 1
fi

# 清理旧托管实例，避免端口占用
PID=$(netstat -ano | grep "0.0.0.0:$PORT" | grep LISTENING | awk '{print $NF}' | head -1 || true)
if [ -n "${PID:-}" ]; then
  echo "停止旧前端托管进程 PID=$PID"
  taskkill //F //PID "$PID" >/dev/null 2>&1 || true
  sleep 1
fi

echo "== 托管测试前端 http://localhost:$PORT（部署目录 $TEST_ROOT/frontend）=="
# python 可用则沿用（访问日志格式与历史一致）；不可用（如 Windows Store
# 占位符）回退 Dart 零依赖静态托管 tools/serve_static.dart
if python -c 'print("ok")' 2>/dev/null | grep -q ok; then
  cd "$TEST_ROOT/frontend"
  exec python -m http.server "$PORT"
fi
echo "python 不可用，改用 Dart 静态托管（tools/serve_static.dart）"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec dart tools/serve_static.dart "$(cygpath -w "$TEST_ROOT/frontend")" "$PORT"
