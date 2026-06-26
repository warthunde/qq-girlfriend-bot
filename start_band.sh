#!/usr/bin/env bash
# ===================================================================
# 纽带乐队四人组 — 一键启动
#   bash start_band.sh          # 启动 NapCat + Orchestrator
#   bash start_band.sh logs     # 查看实时日志
#   bash start_band.sh stop     # 停止
# ===================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'
pc() { echo -e "${2}${1}${NC}"; }

# ── Sub-commands ───────────────────────────────────────────

CMD="${1:-start}"

case "$CMD" in
  stop)
    pc "Stopping Band..." "$CYAN"
    pkill -f "orchestrator/main.py" 2>/dev/null || true
    docker compose down 2>/dev/null || true
    pc "Done." "$GREEN"
    exit 0
    ;;

  logs)
    if [ -f /tmp/orchestrator.log ]; then
      tail -f /tmp/orchestrator.log
    else
      pc "No log file found. Start the band first." "$RED"
    fi
    exit 0
    ;;

  status)
    pc "NapCat containers:" "$CYAN"
    docker compose ps 2>/dev/null || echo "  docker not available"
    echo ""
    if pgrep -f "orchestrator/main.py" > /dev/null; then
      pc "Orchestrator: RUNNING (PID $(pgrep -f 'orchestrator/main.py' | head -1))" "$GREEN"
    else
      pc "Orchestrator: STOPPED" "$YELLOW"
    fi
    exit 0
    ;;

  restart)
    pc "Restarting..." "$CYAN"
    pkill -f "orchestrator/main.py" 2>/dev/null || true
    sleep 2
    exec bash "$0" start
    ;;

  start) ;;
  *)
    pc "Usage: bash start_band.sh [start|stop|logs|status|restart]" "$YELLOW"
    exit 1
    ;;
esac

# ── Banner ──────────────────────────────────────────────────

clear 2>/dev/null || true
echo ""
pc "╔══════════════════════════════════════════════════════╗" "$MAGENTA"
pc "║   🎸  纽带乐队四人组                                 ║" "$MAGENTA"
pc "║   虹夏 🥁  |  波奇酱 🎸  |  山田凉 🎸  |  喜多 🎤    ║" "$MAGENTA"
pc "╚══════════════════════════════════════════════════════╝" "$MAGENTA"
echo ""

# ── Check .env ──────────────────────────────────────────────

if [ ! -f ".env" ]; then
  pc "[!] .env not found. Copy and edit:" "$RED"
  echo "    cp .env.example .env && nano .env"
  exit 1
fi

set -a; source .env; set +a

missing=""
for var in NIJIKA_QQ BOCCHI_QQ RYO_QQ KITA_QQ DEEPSEEK_API_KEY TARGET_GROUP_ID; do
  val="${!var:-}"
  if [ -z "$val" ] || [[ "$val" == 填* ]] || [[ "$val" == "sk-your"* ]]; then
    missing="$missing  - $var"$'\n'
  fi
done
if [ -n "$missing" ]; then
  pc "[!] Missing config:" "$RED"
  echo -e "$missing"
  echo "  Edit .env and fill in all values."
  exit 1
fi

# ── Find Docker ──────────────────────────────────────────────

dcmd=""
for d in docker.exe docker; do
  command -v "$d" &>/dev/null && { dcmd="$d"; break; }
done
if [ -z "$dcmd" ]; then
  pc "[!] Docker not found. Install Docker first." "$RED"
  exit 1
fi

# ── Generate OneBot configs ──────────────────────────────────

gen_cfg() {
  local name="$1" qq="$2" dir="$3"
  local tmpl="${dir}/onebot11_template.json"
  local cfg="${dir}/onebot11_${qq}.json"
  if [ -f "$tmpl" ] && [ ! -f "$cfg" ]; then
    cp "$tmpl" "$cfg"
    pc "  [+] $name config created" "$GREEN"
  fi
  local nap="${dir}/napcat_${qq}.json"
  if [ -f "${dir}/napcat.json" ] && [ ! -f "$nap" ]; then
    cp "${dir}/napcat.json" "$nap"
  fi
}

gen_cfg "虹夏"   "$NIJIKA_QQ" "napcat_nijika/config"
gen_cfg "波奇酱" "$BOCCHI_QQ"  "napcat_bocchi/config"
gen_cfg "山田凉" "$RYO_QQ"     "napcat_ryo/config"
gen_cfg "喜多"   "$KITA_QQ"    "napcat_kita/config"

# ── Start NapCat ─────────────────────────────────────────────

pc ""; pc "[1/3] Starting NapCat containers..." "$CYAN"
$dcmd compose down --remove-orphans 2>/dev/null || true
$dcmd compose up -d napcat_nijika napcat_bocchi napcat_ryo napcat_kita

sleep 5
pc ""; pc "[2/3] NapCat WebUI — 扫码登录:" "$CYAN"
nw="${NIJIKA_WEBUI_PORT:-6100}"; bw="${BOCCHI_WEBUI_PORT:-6101}"
rw="${RYO_WEBUI_PORT:-6102}"; kw="${KITA_WEBUI_PORT:-6103}"

echo "  🥁 虹夏:   http://localhost:${nw}/webui?token=nijika_band_token_2024"
echo "  🎸 波奇酱: http://localhost:${bw}/webui?token=bocchi_band_token_2024"
echo "  🎸 山田凉: http://localhost:${rw}/webui?token=ryo_band_token_2024"
echo "  🎤 喜多:   http://localhost:${kw}/webui?token=kita_band_token_2024"
echo ""
pc "  在浏览器打开以上链接，用对应 QQ 号扫码" "$YELLOW"

# ── Wait and start Orchestrator ──────────────────────────────

read -p "  全部扫完后按 Enter 启动编排器..." </dev/tty || true

pc ""; pc "[3/3] Starting Band Orchestrator..." "$CYAN"

pkill -f "orchestrator/main.py" 2>/dev/null || true
sleep 1
nohup bash "$SCRIPT_DIR/run_orchestrator.sh" > /tmp/orchestrator.log 2>&1 &
pid=$!

sleep 6
pc ""; pc "════════════════════════════════════════════" "$GREEN"
pc "  🎸 纽带乐队 RUNNING!" "$GREEN"
pc "  群号: $TARGET_GROUP_ID" "$CYAN"
pc "  日志: tail -f /tmp/orchestrator.log" "$CYAN"
pc "  停止: bash start_band.sh stop" "$CYAN"
pc "════════════════════════════════════════════" "$GREEN"
echo ""
pc "  用 Bot 号在群里发一条消息，Jam Session 自动开始!" "$MAGENTA"
