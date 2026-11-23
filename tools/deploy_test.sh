#!/usr/bin/env bash
# =====================================================================
# 一键发布测试版：构建后端生产产物 + 构建前端 Web 产物并部署到独立目录。
#
# 测试环境与开发环境共用开发库（DM8 AICMHCS 模式），仅以端口与部署目录
# 隔离（数据库初始化见 init_db.sh；结构迁移由后端启动时自动执行）：
#   后端 http://localhost:8090 —— start_backend_test.sh 从部署副本运行
#   前端 http://localhost:5273 —— 静态托管 <部署根>/frontend
#
# 后端部署副本为 <部署根>/backend/server/build（server/build 产物复制）+
# <部署根>/backend/common（仓库 common 包复制）——镜像开发仓库
# server/build × <仓库根>/common 的相对结构：产物 pubspec_overrides.yaml
# 的共享包 path ..\..\common（相对 build/ 上两级）原样即可解析，产物零改写。
# 测试后端从副本运行后不再锁住开发仓库的 server/build，开发侧
# dart_frog build / F5 与测试环境互不干扰。
#
# 部署结束自动经计划任务 AiCMHCS-TestBackend / AiCMHCS-TestFrontend 重新拉起
# 两个服务（任务不存在或拉起失败时提示手动启动对应脚本）。
#
# 可配置环境变量：
#   AICMHCS_TEST_ROOT  测试环境部署根目录（默认 /d/AiCMHCS-Test）
#   AICMHCS_TEST_API   写入部署前端的测试后端地址（默认 http://localhost:8090）
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="${AICMHCS_TEST_ROOT:-/d/AiCMHCS-Test}"
TEST_API="${AICMHCS_TEST_API:-http://localhost:8090}"

# 旧测试后端/前端进程的工作目录分别在部署副本 backend/build 与 frontend 内，
# 刷新目录（rm -rf）前必须先停掉
for PORT_NO in 8090 5273; do
  OLD_PID=$(netstat -ano | grep "0.0.0.0:$PORT_NO" | grep LISTENING | awk '{print $NF}' | head -1 || true)
  if [ -n "${OLD_PID:-}" ]; then
    echo "停止旧测试服务（端口 $PORT_NO，PID=$OLD_PID）"
    taskkill //F //PID "$OLD_PID" >/dev/null 2>&1 || true
    sleep 1
  fi
done

# 开发生产模式后端（start_backend.sh）正是从 server/build 运行的，
# 运行中的进程会锁住产物文件，先提醒避免构建中途失败。
DEV_PID=$(netstat -ano | grep "0.0.0.0:8080" | grep LISTENING | awk '{print $NF}' | head -1 || true)
if [ -n "${DEV_PID:-}" ]; then
  echo "警告：8080 端口有服务在运行（PID=$DEV_PID）。若为生产模式后端" \
    "（start_backend.sh 启动），请先停止再重新执行本脚本，否则重建" \
    "server/build 可能因文件锁失败。" >&2
  sleep 2
fi

echo "== 1/5 构建后端（dart_frog build + 修复脚本）=="
cd "$ROOT/server"
FROG="$LOCALAPPDATA/Pub/Cache/bin/dart_frog.bat"
if [ ! -f "$FROG" ]; then FROG="dart_frog"; fi
# dart_frog build 在中途失败（如 build 目录被旧进程占用）时会残留
# server/pubspec_overrides.yaml：其中的 resolution: null 会覆盖本包的
# resolution: workspace，使此后所有 pub 操作报「does not have
# resolution: workspace」。负责删除它的 tool/fix_build_overrides.dart
# 在 build 成功后才运行，故构建前先清理，保证失败可自愈。
rm -f pubspec_overrides.yaml
"$FROG" build
# 修复 dart_frog 对 pub workspace 共享包生成的坏 path（见脚本头注释）
dart run tool/fix_build_overrides.dart

echo "== 2/5 部署后端到 $TEST_ROOT/backend（镜像 server/build × common 结构）=="
mkdir -p "$TEST_ROOT"
rm -rf "$TEST_ROOT/backend"
mkdir -p "$TEST_ROOT/backend/server"
cp -r "$ROOT/server/build" "$TEST_ROOT/backend/server/build"
cp -r "$ROOT/common" "$TEST_ROOT/backend/common"
# 产物内共享包 path ..\..\common 相对 build/ 上两级（build → server →
# backend），恰好解析到同在 backend/ 下的 common 副本——相对层级与开发
# 仓库一致，产物零改写；仅需在副本内重新解析依赖，使 package_config.json
# 指向副本自身而非开发仓库（pubspec.lock 与本地 pub 缓存齐全，无需重新下载）
(cd "$TEST_ROOT/backend/server/build" && dart pub get)

echo "== 3/5 构建前端（flutter build web）=="
cd "$ROOT/client"
flutter build web

echo "== 4/5 部署前端到 $TEST_ROOT/frontend =="
rm -rf "$TEST_ROOT/frontend"
mkdir -p "$TEST_ROOT/frontend"
cp -r build/web/. "$TEST_ROOT/frontend/"
# 覆写部署副本的后端地址（rootBundle 运行时读取 assets/assets/config.json，
# 改文件即生效，无需重新构建；仓库内 assets/config.json 保持指向开发后端 8080）
sed -i -E "s#\"apiUrl\"[[:space:]]*:[[:space:]]*\"[^\"]*\"#\"apiUrl\": \"$TEST_API\"#" \
  "$TEST_ROOT/frontend/assets/assets/config.json"
echo "已写入部署前端 apiUrl = $TEST_API"

echo "== 5/5 重新拉起测试服务（计划任务隐藏运行）=="
if schtasks //Run //TN AiCMHCS-TestBackend >/dev/null 2>&1; then
  echo "测试后端已拉起（http://localhost:8090，日志 $TEST_ROOT/logs/backend.log）"
else
  echo "计划任务 AiCMHCS-TestBackend 拉起失败，请手动执行：./tools/start_backend_test.sh"
fi
if schtasks //Run //TN AiCMHCS-TestFrontend >/dev/null 2>&1; then
  echo "测试前端已拉起（http://localhost:5273，日志 $TEST_ROOT/logs/frontend.log）"
else
  echo "计划任务 AiCMHCS-TestFrontend 拉起失败，请手动执行：./tools/serve_frontend_test.sh"
fi
