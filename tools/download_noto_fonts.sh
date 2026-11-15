#!/usr/bin/env bash
# 将 Flutter Web 引擎按需下载的 Noto 回退字体片段（woff2 拆片）镜像到
# client/web/noto/，配合 client/web/flutter_bootstrap.js 的
# fontFallbackBaseUrl: '/noto/' 使用。
#
# 背景：CanvasKit 渲染器遇到内置字体（阿里巴巴普惠体）缺字形时，默认
# 从 https://fonts.gstatic.com/s/ 在线下载对应 Noto 拆片（下载完成前显示
# 缺字形框，离线环境永久卡框）。本脚本一次性把全部拆片下载到本地目录，
# 由 dev server / 构建产物静态托管，彻底消除运行期外网依赖。
#
# 可重复执行：已存在且非空的文件自动跳过。用法：
#   ./tools/download_noto_fonts.sh [flutter-sdk根目录]
# （SDK 根目录也可用环境变量 FLUTTER_ROOT 指定，缺省从 PATH 中的
#   flutter 命令反推）
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/client/web/noto"

FLUTTER_ROOT="${1:-${FLUTTER_ROOT:-}}"
if [ -z "$FLUTTER_ROOT" ]; then
  FLUTTER_BIN="$(command -v flutter)" || {
    echo '未找到 flutter 命令，请传入 Flutter SDK 根目录作为参数'
    exit 1
  }
  FLUTTER_ROOT="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)"
fi

DATA_FILE="$FLUTTER_ROOT/bin/cache/flutter_web_sdk/lib/ui/src/engine/font_fallback_data.dart"
[ -f "$DATA_FILE" ] || {
  echo "未找到回退字体清单：$DATA_FILE"
  exit 1
}

BASE_URL="https://fonts.gstatic.com/s/"
mkdir -p "$OUT_DIR"

# 从引擎源码提取全部拆片相对路径（与引擎 fontFallbackBaseUrl 解析口径一致）；
# Roboto 基础片段声明在引擎 canvaskit/fonts.dart（不在数据清单内），单独补入
URLS="$(
  {
    grep -oE "'[a-zA-Z0-9/_.%-]+\.woff2'" "$DATA_FILE" | tr -d "'"
    echo 'roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2'
  } | sort -u
)"
TOTAL="$(echo "$URLS" | wc -l)"
echo "共 $TOTAL 个字体片段，下载基址 $BASE_URL，输出目录 $OUT_DIR ..."

FAIL_LIST="$OUT_DIR/.download_failed.txt"
: > "$FAIL_LIST"

export OUT_DIR BASE_URL FAIL_LIST
download_one() {
  local rel="$1"
  local out="$OUT_DIR/$rel"
  [ -s "$out" ] && return 0
  mkdir -p "$(dirname "$out")"
  # --globoff：URL 含 [] 等字符时避免 curl 通配展开
  curl -sf --retry 3 --globoff -o "$out" "$BASE_URL$rel" || {
    echo "$rel" >> "$FAIL_LIST"
    rm -f "$out"
  }
}
export -f download_one

echo "$URLS" | xargs -P 8 -I '{}' bash -c 'download_one "$@"' _ '{}'

FAIL_COUNT="$(wc -l < "$FAIL_LIST" | tr -d ' ')"
OK_COUNT=$((TOTAL - FAIL_COUNT))
echo "完成：成功 $OK_COUNT / $TOTAL"
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "以下片段下载失败（网络恢复后重跑本脚本即可补齐）："
  cat "$FAIL_LIST"
  exit 1
fi
rm -f "$FAIL_LIST"
du -sh "$OUT_DIR"
