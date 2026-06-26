#!/usr/bin/env bash
# 停止纽带乐队
set -euo pipefail

echo "Stopping Band Orchestrator..."
pkill -f "orchestrator/main.py" 2>/dev/null || true

echo "Stopping NapCat containers..."
docker compose down 2>/dev/null || true

echo "Band stopped."
