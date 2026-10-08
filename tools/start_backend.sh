#!/usr/bin/env bash
# 启动 AiCMHCS 后端（生产模式：dart_frog build + dart run）。
# 说明：dart_frog dev 需要交互终端，在无终端环境（后台/CI）会因 stdin 报错，
# 因此这里统一使用构建产物运行；在真实终端开发时可自行运行 dart_frog dev。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/server"

PORT="${AICMHCS_PORT:-8080}"

# 清理旧实例，避免端口占用
PID=$(netstat -ano | grep "0.0.0.0:$PORT" | grep LISTENING | awk '{print $NF}' | head -1 || true)
if [ -n "${PID:-}" ]; then
  echo "停止旧后端进程 PID=$PID"
  taskkill //F //PID "$PID" >/dev/null 2>&1 || true
  sleep 1
fi

echo "== 构建后端 =="
FROG="$LOCALAPPDATA/Pub/Cache/bin/dart_frog.bat"
if [ ! -f "$FROG" ]; then FROG="dart_frog"; fi
"$FROG" build

echo "== 启动后端 http://localhost:$PORT =="
exec dart run "build/bin/server.dart"
