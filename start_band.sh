#!/usr/bin/env bash
# ===================================================================
# 纽带乐队四人组 — 一键启动脚本 v2
#   bash start_band.sh          # 启动 NapCat + Orchestrator
#   bash start_band.sh stop     # 停止所有服务
#   bash start_band.sh restart  # 重启
#   bash start_band.sh status   # 查看状态
#   bash start_band.sh logs     # 查看 orchestrator 日志
#   bash start_band.sh qrcode   # 只打印扫码地址（不重启）
# ===================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ── 颜色 ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'
pc() { echo -e "${2}${1}${NC}"; }

# ── 加载 .env ──
if [ -f ".env" ]; then
  set -a; source .env; set +a
fi

CMD="${1:-start}"

# ===================================================================
# 子命令
# ===================================================================

case "$CMD" in
  stop)
    pc "🛑 Stopping Band..." "$YELLOW"
    pkill -f "orchestrator/main.py" 2>/dev/null || true
    sleep 1
    docker compose down 2>/dev/null || true
    pc "✅ Band stopped." "$GREEN"
    exit 0
    ;;

  restart)
    pc "🔄 Restarting..." "$CYAN"
    pkill -f "orchestrator/main.py" 2>/dev/null || true
    sleep 1
    docker compose down 2>/dev/null || true
    sleep 2
    exec bash "$0" start
    ;;

  status)
    echo ""
    pc "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$MAGENTA"
    pc "  🎸 纽带乐队 — 运行状态" "$BOLD"
    pc "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$MAGENTA"
    echo ""
    pc "NapCat 容器:" "$CYAN"
    docker ps --filter "name=qq_band" --format "  {{.Names}}\t{{.Status}}" 2>/dev/null || \
      pc "  (no containers running)" "$YELLOW"
    echo ""
    if pgrep -f "orchestrator/main.py" > /dev/null 2>&1; then
      pc "Orchestrator: ✅ RUNNING" "$GREEN"
    else
      pc "Orchestrator: ⚠️  STOPPED" "$YELLOW"
    fi
    echo ""
    exit 0
    ;;

  logs)
    if [ -f /tmp/orchestrator.log ]; then
      tail -f /tmp/orchestrator.log
    else
      pc "⚠️  No log file found at /tmp/orchestrator.log" "$YELLOW"
      pc "   Start the band first: bash start_band.sh" "$CYAN"
    fi
    exit 0
    ;;

  qrcode)
    echo ""
    pc "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$MAGENTA"
    pc "  📱 扫码登录地址" "$BOLD"
    pc "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$MAGENTA"
    echo ""
    pc " 🥁 虹夏 (Nijika)   QQ: ${NIJIKA_QQ:-?}" "$YELLOW"
    echo "    http://localhost:${NIJIKA_WEBUI_PORT:-6100}/webui?token=nijika_band_token_2024"
    echo ""
    pc " 🎸 波奇酱 (Bocchi)  QQ: ${BOCCHI_QQ:-?}" "$MAGENTA"
    echo "    http://localhost:${BOCCHI_WEBUI_PORT:-6101}/webui?token=bocchi_band_token_2024"
    echo ""
    pc " 🎸 山田凉 (Ryo)     QQ: ${RYO_QQ:-?}" "$CYAN"
    echo "    http://localhost:${RYO_WEBUI_PORT:-6102}/webui?token=ryo_band_token_2024"
    echo ""
    pc " 🎤 喜多 (Kita)      QQ: ${KITA_QQ:-?}" "$RED"
    echo "    http://localhost:${KITA_WEBUI_PORT:-6103}/webui?token=kita_band_token_2024"
    echo ""
    exit 0
    ;;

  start) ;;
  *)
    pc "Usage: bash start_band.sh [start|stop|restart|status|logs|qrcode]" "$YELLOW"
    exit 1
    ;;
esac

# ===================================================================
# START 模式
# ===================================================================

clear 2>/dev/null || true
echo ""
pc "╔══════════════════════════════════════════════════════╗" "$MAGENTA"
pc "║   🎸  纽带乐队四人组  —  启动中...                    ║" "$MAGENTA"
pc "║   虹夏 🥁  |  波奇酱 🎸  |  山田凉 🎸  |  喜多 🎤     ║" "$MAGENTA"
pc "╚══════════════════════════════════════════════════════╝" "$MAGENTA"
echo ""

# ── 1. 检查 .env ──
if [ ! -f ".env" ]; then
  pc "❌ .env 文件不存在！" "$RED"
  echo "   cp .env.example .env && nano .env"
  exit 1
fi

missing=""
for var in NIJIKA_QQ BOCCHI_QQ RYO_QQ KITA_QQ DEEPSEEK_API_KEY TARGET_GROUP_ID; do
  val="${!var:-}"
  if [ -z "$val" ] || [[ "$val" == 填* ]] || [[ "$val" == "sk-your"* ]]; then
    missing="$missing  - $var"$'\n'
  fi
done
if [ -n "$missing" ]; then
  pc "❌ .env 配置不完整，缺少：" "$RED"
  echo -e "$missing"
  echo "  编辑 .env 填入所有必填项后重试"
  exit 1
fi
pc "✅ .env 配置检查通过" "$GREEN"

# ── 2. 检查 Docker ──
dcmd=""
for d in docker.exe docker; do
  command -v "$d" &>/dev/null && { dcmd="$d"; break; }
done
if [ -z "$dcmd" ]; then
  pc "❌ Docker 未安装，请先安装 Docker" "$RED"
  exit 1
fi
pc "✅ Docker: $dcmd" "$GREEN"

# ── 3. 生成 OneBot 配置 ──
gen_cfg() {
  local name="$1" qq="$2" dir="$3"
  local tmpl="${dir}/onebot11_template.json"
  local cfg="${dir}/onebot11_${qq}.json"
  if [ -f "$tmpl" ] && [ ! -f "$cfg" ]; then
    cp "$tmpl" "$cfg"
    pc "  📝 ${name} 配置已生成" "$GREEN"
  fi
  local nap_tmpl="${dir}/napcat.json"
  local nap_cfg="${dir}/napcat_${qq}.json"
  if [ -f "$nap_tmpl" ] && [ ! -f "$nap_cfg" ]; then
    cp "$nap_tmpl" "$nap_cfg"
  fi
}

echo ""
pc "📋 生成配置文件..." "$CYAN"
gen_cfg "虹夏"   "$NIJIKA_QQ" "napcat_nijika/config"
gen_cfg "波奇酱" "$BOCCHI_QQ"  "napcat_bocchi/config"
gen_cfg "山田凉" "$RYO_QQ"     "napcat_ryo/config"
gen_cfg "喜多"   "$KITA_QQ"    "napcat_kita/config"

# ── 4. 启动 NapCat ──
echo ""
pc "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$CYAN"
pc "  [1/2] 启动 NapCat 容器... " "$BOLD"
pc "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$CYAN"

# 先清理
$dcmd compose down --remove-orphans 2>/dev/null || true

$dcmd compose up -d napcat_nijika napcat_bocchi napcat_ryo napcat_kita

sleep 5

# 检查容器状态
echo ""
running_count=$($dcmd ps --filter "name=qq_band" --filter "status=running" --format "{{.Names}}" 2>/dev/null | wc -l)
if [ "$running_count" -lt 4 ]; then
  pc "⚠️  只有 ${running_count}/4 个容器在运行，请检查：" "$YELLOW"
  $dcmd compose ps
else
  pc "✅ 4/4 NapCat 容器运行中" "$GREEN"
fi

# ── 5. 展示扫码地址 ──
echo ""
pc "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$MAGENTA"
pc "  📱 请用对应 QQ 号扫码登录" "$BOLD"
pc "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$MAGENTA"
echo ""
nw="${NIJIKA_WEBUI_PORT:-6100}"; bw="${BOCCHI_WEBUI_PORT:-6101}"
rw="${RYO_WEBUI_PORT:-6102}"; kw="${KITA_WEBUI_PORT:-6103}"

pc " 🥁 虹夏    QQ: ${NIJIKA_QQ}" "$YELLOW"
echo "    http://localhost:${nw}/webui?token=nijika_band_token_2024"
echo ""
pc " 🎸 波奇酱  QQ: ${BOCCHI_QQ}" "$MAGENTA"
echo "    http://localhost:${bw}/webui?token=bocchi_band_token_2024"
echo ""
pc " 🎸 山田凉  QQ: ${RYO_QQ}" "$CYAN"
echo "    http://localhost:${rw}/webui?token=ryo_band_token_2024"
echo ""
pc " 🎤 喜多    QQ: ${KITA_QQ}" "$RED"
echo "    http://localhost:${kw}/webui?token=kita_band_token_2024"
echo ""

# ── 6. 等待扫码 ──
echo ""
pc "╔══════════════════════════════════════════════════════╗" "$YELLOW"
pc "║  在浏览器中打开上方 4 个链接                            ║" "$YELLOW"
pc "║  用各自对应的 QQ 号手机扫码登录                         ║" "$YELLOW"
pc "║  全部扫完后按 Enter 启动编排器...                       ║" "$YELLOW"
pc "╚══════════════════════════════════════════════════════╝" "$YELLOW"
echo ""
read -p "  👉 全部扫码完成后，按 Enter 继续..." </dev/tty || true

# ── 7. 启动 Orchestrator ──
echo ""
pc "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$CYAN"
pc "  [2/2] 启动 Band Orchestrator..." "$BOLD"
pc "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$CYAN"

# 杀掉旧实例
pkill -f "orchestrator/main.py" 2>/dev/null || true
sleep 1

nohup bash "$SCRIPT_DIR/run_orchestrator.sh" > /tmp/orchestrator.log 2>&1 &

sleep 5

# ── 8. 检查 orchestrator 是否成功启动 ──
if pgrep -f "orchestrator/main.py" > /dev/null 2>&1; then
  pc "✅ Orchestrator 已启动" "$GREEN"
else
  pc "❌ Orchestrator 启动失败！查看日志:" "$RED"
  echo "   tail -50 /tmp/orchestrator.log"
  tail -30 /tmp/orchestrator.log 2>/dev/null || true
  exit 1
fi

# ── 9. 打印日志并完成 ──
echo ""
sleep 3
# 检查 WebSocket 连接状态
ws_connected=$(tail -30 /tmp/orchestrator.log 2>/dev/null | grep -c "WebSocket connected" || true)

echo ""
pc "╔══════════════════════════════════════════════════════╗" "$GREEN"
pc "║   🎸  纽带乐队 RUNNING!                               ║" "$GREEN"
pc "╠══════════════════════════════════════════════════════╣" "$GREEN"
pc "║   群号: ${TARGET_GROUP_ID}                                  ║" "$CYAN"
echo -e "║   WS 连接: ${ws_connected}/4                                    ║"
pc "║   日志: tail -f /tmp/orchestrator.log                 ║" "$CYAN"
pc "║   停止: bash start_band.sh stop                       ║" "$CYAN"
pc "║   状态: bash start_band.sh status                     ║" "$CYAN"
pc "╚══════════════════════════════════════════════════════╝" "$GREEN"
echo ""
pc "  💬 用 Bot 号在群里发一条消息，Jam Session 开始!" "$MAGENTA"
echo ""

# 显示最近几行日志
tail -15 /tmp/orchestrator.log 2>/dev/null | head -10
