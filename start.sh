#!/bin/bash
# =============================================================
# QQ 赛博女友 - 一键启动脚本
# =============================================================

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
NC='\033[0m'

print_ok()   { echo -e "${GREEN}[✓] $*${NC}"; }
print_warn() { echo -e "${YELLOW}[!] $*${NC}"; }
print_info() { echo -e "${CYAN}[i] $*${NC}"; }
print_err()  { echo -e "${RED}[✗] $*${NC}"; }

echo ""
echo -e "${MAGENTA}╔══════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║     💕 QQ 赛博女友 · 启动中...       ║${NC}"
echo -e "${MAGENTA}╚══════════════════════════════════════╝${NC}"
echo ""

cd ~/qq_bot_deploy

# 检查 .env 是否存在
if [ ! -f .env ]; then
    print_warn "未找到 .env 配置文件"
    print_info "正在从模板创建..."
    if [ -f .env.example ]; then
        cp .env.example .env
        print_ok ".env 文件已从模板创建"
    else
        print_err "也未找到 .env.example 模板文件"
        print_info "请先运行 deploy_qq_bot.sh 进行部署"
        exit 1
    fi
    echo ""
    print_warn "请编辑 .env 文件，填入你的 QQ 号和 API Key"
    print_info "使用命令: nano ~/qq_bot_deploy/.env"
    echo ""
    read -p "按 Enter 键打开编辑器进行配置，或按 Ctrl+C 取消..."
    ${EDITOR:-nano} .env
else
    print_ok "已找到 .env 配置文件"
fi

# 读取 QQ 账号生成 OneBot 配置文件名
source .env
if [ -z "${QQ_ACCOUNT:-}" ]; then
    print_err "QQ_ACCOUNT 未设置，请在 .env 中配置"
    exit 1
fi

ONEBOT_CONFIG="napcat/config/onebot11_${QQ_ACCOUNT}.json"
if [ ! -f "$ONEBOT_CONFIG" ]; then
    print_info "生成 OneBot 配置文件: $ONEBOT_CONFIG"
    if [ -f napcat/config/onebot11_YOUR_QQ.json ]; then
        cp napcat/config/onebot11_YOUR_QQ.json "$ONEBOT_CONFIG"
        print_ok "OneBot 配置文件已生成"
    else
        print_warn "未找到 OneBot 配置模板，将使用默认配置"
    fi
else
    print_ok "OneBot 配置文件已存在"
fi

# 启动
echo ""
print_info "正在启动 Docker 容器..."
docker compose up -d

if [ $? -ne 0 ]; then
    print_err "容器启动失败！请检查 Docker 是否正在运行。"
    print_info "Windows/Mac: 请打开 Docker Desktop 应用"
    print_info "Linux: sudo systemctl start docker"
    exit 1
fi

print_ok "容器启动成功！"
echo ""
print_info "等待服务初始化中..."

sleep 10

# 检查容器状态
echo ""
print_info "当前容器运行状态："
docker ps --filter "name=qq_bot" --format "table {{.Names}}\t{{.Status}}"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         ✨ 机器人已上线！                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  🤖 机器人 QQ: ${YELLOW}${QQ_ACCOUNT}${NC}"
echo -e "  📱 去手机 QQ 搜索 ${YELLOW}${QQ_ACCOUNT}${NC} 开始聊天吧！"
echo ""
# 从 webui.json 读取实际 Token
WEBUI_TOKEN=$(grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' napcat/config/webui.json 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/')
WEBUI_TOKEN="${WEBUI_TOKEN:-eaf564183254}"

echo -e "${YELLOW}  ⚠ 首次使用需要扫码登录：${NC}"
echo -e "    访问 ${CYAN}http://localhost:6099/webui/web_login?token=$WEBUI_TOKEN${NC} 免输入 Token 登录"
echo -e "    Token 值: ${GRAY}${WEBUI_TOKEN}${NC}"
echo ""
echo -e "${YELLOW}  🌐 Web 管理后台：${NC}"
echo -e "    ${CYAN}http://localhost:6185${NC}"
echo ""
echo -e "${GRAY}  查看日志: docker logs -f qq_bot_astrbot${NC}"
echo -e "${GRAY}  停止服务: cd ~/qq_bot_deploy && docker compose down${NC}"
echo ""
