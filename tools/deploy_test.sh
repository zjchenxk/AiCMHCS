#!/usr/bin/env bash
# =====================================================================
# 一键发布测试版：构建后端生产产物 + 构建前端 Web 产物并部署到独立目录。
#
# 测试环境与开发环境共用开发库（DM8 AICMHCS 模式），仅以端口与部署目录
# 隔离（数据库初始化见 init_db.sh；结构迁移由后端启动时自动执行）：
#   后端 http://localhost:8090 —— start_backend_test.sh 从 server/build 运行
#   前端 http://localhost:5273 —— 静态托管 <部署根>/frontend
#
# 可配置环境变量：
#   AICMHCS_TEST_ROOT  测试环境部署根目录（默认 /d/AiCMHCS-Test）
#   AICMHCS_TEST_API   写入部署前端的测试后端地址（默认 http://localhost:8090）
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="${AICMHCS_TEST_ROOT:-/d/AiCMHCS-Test}"
TEST_API="${AICMHCS_TEST_API:-http://localhost:8090}"

# 开发生产模式后端（start_backend.sh）正是从 server/build 运行的，
# 运行中的进程会锁住产物文件，先提醒避免构建中途失败。
DEV_PID=$(netstat -ano | grep "0.0.0.0:8080" | grep LISTENING | awk '{print $NF}' | head -1 || true)
if [ -n "${DEV_PID:-}" ]; then
  echo "警告：8080 端口有服务在运行（PID=$DEV_PID）。若为生产模式后端" \
    "（start_backend.sh 启动），请先停止再重新执行本脚本，否则重建" \
    "server/build 可能因文件锁失败。" >&2
  sleep 2
fi

echo "== 1/4 构建后端（dart_frog build + 修复脚本）=="
cd "$ROOT/server"
FROG="$LOCALAPPDATA/Pub/Cache/bin/dart_frog.bat"
if [ ! -f "$FROG" ]; then FROG="dart_frog"; fi
"$FROG" build
# 修复 dart_frog 对 pub workspace 共享包生成的坏 path（见脚本头注释）
dart run tool/fix_build_overrides.dart

echo "== 2/4 构建前端（flutter build web）=="
cd "$ROOT/client"
flutter build web

echo "== 3/4 部署前端到 $TEST_ROOT/frontend =="
rm -rf "$TEST_ROOT/frontend"
mkdir -p "$TEST_ROOT/frontend"
cp -r build/web/. "$TEST_ROOT/frontend/"
# 覆写部署副本的后端地址（rootBundle 运行时读取 assets/assets/config.json，
# 改文件即生效，无需重新构建；仓库内 assets/config.json 保持指向开发后端 8080）
sed -i -E "s#\"apiUrl\"[[:space:]]*:[[:space:]]*\"[^\"]*\"#\"apiUrl\": \"$TEST_API\"#" \
  "$TEST_ROOT/frontend/assets/assets/config.json"
echo "已写入部署前端 apiUrl = $TEST_API"

echo "== 4/4 部署完成 =="
echo "启动测试后端：./tools/start_backend_test.sh"
echo "托管测试前端：./tools/serve_frontend_test.sh"
