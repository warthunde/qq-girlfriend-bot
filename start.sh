#!/bin/bash
# =============================================================
# QQ 赛博女友 - 一键启动脚本
# =============================================================

cd ~/qq_bot_deploy

# 检查 .env 是否存在
if [ ! -f .env ]; then
    echo "⚠ 未找到 .env 文件，正在从模板创建..."
    cp .env.example .env
    echo "✔ 已创建 .env，请编辑此文件填入你的 QQ 号和 API Key："
    echo "   nano ~/qq_bot_deploy/.env"
    echo ""
    read -p "按 Enter 继续编辑配置，或 Ctrl+C 取消..."
    ${EDITOR:-nano} .env
fi

# 读取 QQ 账号生成 OneBot 配置文件名
source .env
ONEBOT_CONFIG="napcat/config/onebot11_${QQ_ACCOUNT}.json"
if [ ! -f "$ONEBOT_CONFIG" ]; then
    cp napcat/config/onebot11_YOUR_QQ.json "$ONEBOT_CONFIG"
    echo "✔ 已生成 $ONEBOT_CONFIG"
fi

# 启动
docker compose up -d

echo ""
echo "⏳ 机器人在启动中，稍等一会儿..."
sleep 10
docker ps --filter "name=qq_bot" --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "================================================"
echo "  ✔ 机器人已上线！"
echo "  去手机 QQ 搜索 ${QQ_ACCOUNT} 开始聊天吧！"
echo ""
echo "  首次使用可能需要扫码登录："
echo "    访问 http://localhost:6099/webui 查看二维码"
echo "================================================"
