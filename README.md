# 🎸 纽带乐队 — QQ 群聊 AI Bot

> 孤独摇滚！4 人组入驻你的 QQ 群 — 虹夏、波奇酱、山田凉、喜多郁代，各自独立人格，在群里自然聊天互动。

## ✨ 特性

- **4 人乐队** — 虹夏🥁、波奇酱🎸、山田凉🎸、喜多🎤，每人独立 QQ 号 + 独立人设
- **群聊智能接话** — 群里有人发消息，Bot 们根据上下文自动判断谁该接话，围绕聊天内容自然互动
- **独立人格** — 每人有专属 persona 设定（YAML），虹夏元气、波奇社恐、凉冷淡、喜多阳光
- **反风控设计** — 消息间隔随机化、发送失败自动停、紧急停止命令，降低 QQ 风控风险
- **关键词表情包** — 18 条关键词规则 + 120 张孤独摇滚贴纸，自动触发
- **小剧场模式**（可选）— Bot 们定时自动发起对话，模拟乐队日常
- **Docker 部署** — 一键启动 4 个 NapCat 容器，扫码即用

## 🏗️ 架构

```
手机QQ ←→ 腾讯 ←→ NapCat ×4 ──ws──→ Band Orchestrator ──HTTP──→ DeepSeek API
                      :6100-6103          (Python asyncio)
                      WebUI 扫码
```

| 组件 | 说明 |
|------|------|
| **NapCat** ×4 | QQ 协议层，每个 Bot 一个独立容器 + 独立 QQ 号 |
| **Band Orchestrator** | Python 调度引擎，连接 4 个 NapCat，管理消息分发和对话逻辑 |
| **DeepSeek API** | 大模型驱动，根据 persona 生成符合人设的回复 |

## 📋 前置要求

- Docker & Docker Compose
- 4 个 QQ 小号
- DeepSeek API Key（[免费申请](https://platform.deepseek.com)，4 个 Bot 共用）

## 🚀 快速开始

### 1. 克隆项目

```bash
git clone git@github.com:warthunde/qq-girlfriend-bot.git
cd qq-girlfriend-bot
```

### 2. 配置

```bash
cp .env.example .env
nano .env
```

必填项：

```bash
NIJIKA_QQ=虹夏的QQ号        # 伊地知虹夏，鼓手
BOCCHI_QQ=波奇酱的QQ号       # 后藤一里，吉他手
RYO_QQ=山田凉的QQ号          # 贝斯手
KITA_QQ=喜多郁代的QQ号       # 主唱兼吉他手
DEEPSEEK_API_KEY=sk-xxxx     # DeepSeek API Key
TARGET_GROUP_ID=目标群号      # 4 个 Bot 一起加入的群
```

### 3. 启动

```bash
bash start_band.sh
```

脚本会：
1. 检查配置 → 拉取镜像 → 启动 4 个 NapCat 容器
2. 打印 4 个扫码链接，用对应 QQ 号扫码登录
3. 扫完后按 Enter，自动启动 Orchestrator

### 4. 开始聊天

把 4 个 Bot QQ 号都拉进目标群，发一条消息，Jam Session 自动开始！

## 📂 项目结构

```
.
├── docker-compose.yml            # 4×NapCat + Orchestrator 编排
├── .env.example                  # 环境变量模板
├── .env                          # 你的配置（gitignore）
├── start_band.sh                 # 一键启动/停止/重启/状态
├── stop_band.sh                  # 快速停止
├── run_orchestrator.sh           # 单独启动编排器
├── orchestrator/
│   ├── main.py                   # 入口
│   ├── config.py                 # 配置加载
│   ├── napcat_client.py          # WebSocket 客户端（连 NapCat）
│   ├── message_handler.py        # 消息路由 & Jam Session 控制
│   ├── dialogue_engine.py        # 调 DeepSeek 生成回复
│   ├── persona_manager.py        # 加载人设 YAML
│   ├── theater_scheduler.py      # 小剧场定时器
│   ├── keyword_reply.py          # 关键词→表情包
│   └── personas/
│       ├── nijika.yaml           # 虹夏人设
│       ├── bocchi.yaml           # 波奇酱人设
│       ├── ryo.yaml              # 凉人设
│       └── kita.yaml             # 喜多人设
├── napcat_nijika/config/         # 虹夏 NapCat 配置
├── napcat_bocchi/config/         # 波奇酱 NapCat 配置
├── napcat_ryo/config/            # 凉 NapCat 配置
├── napcat_kita/config/           # 喜多 NapCat 配置
└── stickers/                     # 120 张孤独摇滚表情包
```

## 🎛️ 日常命令

```bash
bash start_band.sh              # 启动
bash start_band.sh stop         # 停止
bash start_band.sh restart      # 重启
bash start_band.sh status       # 查看状态
bash start_band.sh logs         # 实时日志
bash start_band.sh qrcode       # 只看扫码地址
```

## 🧑‍🎤 角色一览

| 角色 | QQ 变量 | WebUI 端口 | 人设 |
|------|---------|-----------|------|
| 🥁 伊地知虹夏 | `NIJIKA_QQ` | 6100 | 乐观元气的鼓手，乐队队长，吐槽担当 |
| 🎸 后藤一里 | `BOCCHI_QQ` | 6101 | 社恐吉他手，说话断断续续，喜欢躲起来 |
| 🎸 山田凉 | `RYO_QQ` | 6102 | 冷淡贝斯手，话少但一针见血，爱乱花钱 |
| 🎤 喜多郁代 | `KITA_QQ` | 6103 | 阳光主唱，活泼开朗，开心果 |

## 🎭 自定义人设

编辑 `orchestrator/personas/*.yaml`，修改对应角色的 system prompt。重启即生效：

```bash
bash start_band.sh restart
```

## 🔧 小剧场模式

Bot 们可以定时在群里自发聊天（模拟乐队日常互动）。在 `.env` 中配置：

```bash
THEATER_INTERVAL_MIN=30   # 最小触发间隔（分钟）
THEATER_INTERVAL_MAX=60   # 最大触发间隔（分钟）
MESSAGE_INTERVAL_MIN=5    # Bot 之间最小发言间隔（秒）
MESSAGE_INTERVAL_MAX=20   # Bot 之间最大发言间隔（秒）
```

## ⚠️ QQ 风控说明

腾讯会对机器人账号进行风控。本项目已内置缓解措施：
- 消息间隔 8-15 秒随机化
- 单次会话消息量限制（15-25 条）
- 连续发送失败自动中止
- 群里发「别聊了」「停一下」可紧急停止

建议使用**新注册且在手机上养过一段时间的 QQ 小号**。

## 🛑 停止

```bash
bash start_band.sh stop
```

## ❓ 常见问题

### Q: Bot 不回复？
1. `bash start_band.sh status` 确认容器和 Orchestrator 都在运行
2. `tail -f /tmp/orchestrator.log` 查看日志
3. 确认 4 个 QQ 号都已扫码登录且在线
4. 确认 DeepSeek API Key 有效且余额充足

### Q: 需要重新扫码？
每个角色的 WebUI 地址见上面的端口表，打开对应地址扫码即可。登录态保存在容器中，重启一般不需要重扫。

### Q: 能用其他 AI 模型？
支持所有 OpenAI 兼容 API（通义千问、智谱等），修改 `.env` 中的 `DEEPSEEK_BASE_URL` 和 `AI_MODEL` 即可。

### Q: 需要一直开着电脑吗？
是的，Docker 容器跑在你的机器上。关机会下线。

## 📄 License

MIT
