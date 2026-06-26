#!/usr/bin/env bash
# Orchestrator 启动脚本（宿主机直接运行模式）
# 用法: bash run_orchestrator.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

set -a
source .env
set +a

export NIJIKA_WS_URL="${NIJIKA_WS_URL:-ws://localhost:3001}"
export NIJIKA_HTTP_URL="${NIJIKA_HTTP_URL:-http://localhost:3010}"
export BOCCHI_WS_URL="${BOCCHI_WS_URL:-ws://localhost:3002}"
export BOCCHI_HTTP_URL="${BOCCHI_HTTP_URL:-http://localhost:3020}"
export RYO_WS_URL="${RYO_WS_URL:-ws://localhost:3003}"
export RYO_HTTP_URL="${RYO_HTTP_URL:-http://localhost:3030}"
export KITA_WS_URL="${KITA_WS_URL:-ws://localhost:3004}"
export KITA_HTTP_URL="${KITA_HTTP_URL:-http://localhost:3040}"
export STICKER_DIR="$SCRIPT_DIR/stickers"
export LOG_LEVEL="${LOG_LEVEL:-INFO}"

exec python3 "$SCRIPT_DIR/orchestrator/main.py"
