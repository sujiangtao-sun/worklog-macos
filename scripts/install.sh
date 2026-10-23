#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/dist/WorkLog.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/WorkLog.app"

if [[ ! -d "$SOURCE" ]]; then
    echo "未找到 $SOURCE，请先运行 scripts/build_app.sh" >&2
    exit 1
fi

mkdir -p "$DEST_DIR"
rm -rf "$DEST"
ditto "$SOURCE" "$DEST"

echo "已安装: $DEST"
echo "启动命令: open \"$DEST\""
