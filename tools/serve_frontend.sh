#!/usr/bin/env bash
# 构建 Flutter Web 前端并静态托管（http://localhost:5173）。
# 开发调试请直接：cd client && flutter run -d chrome
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/client"

PORT="${AICMHCS_WEB_PORT:-5173}"

echo "== 构建前端 =="
flutter build web

echo "== 托管 http://localhost:$PORT =="
cd build/web
exec python -m http.server "$PORT"
