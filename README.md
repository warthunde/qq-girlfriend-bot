# QQ 赛博女友 — 基于 AstrBot + NapCat 的 AI QQ 机器人

一键部署属于你的 AI 女友，拥有自定义人格、温柔的聊天风格，24 小时待命的 QQ 赛博伴侣。

## ✨ 特性

- **真实 QQ 在线** — 使用 NapCat 协议，像真人一样收发 QQ 消息
- **DeepSeek 驱动** — 接入 DeepSeek API，回复自然流畅
- **虹夏人格** — 内置伊地知虹夏人格设定（纽带乐队鼓手），说话像真正的 JK 女友
- **网络热梗识别** — 接入 Tavily 搜索引擎，遇到新梗自动搜索后用虹夏风格回复
- **关键词表情包** — 说「原神」「贴贴」「晚安」等关键词自动发送孤独摇滚表情包
- **Docker 一键部署** — 两条命令搞定，开箱即用
- **持久化登录** — 扫码一次，后续重启无需再扫

## 🏗️ 架构

```
手机QQ ←→ 腾讯 ←→ NapCat ←──ws──→ AstrBot ←─HTTP─→ DeepSeek API
                    :6099 WebUI     :6185 管理后台    Tavily 搜索
                    :3001 WS        :6199 OneBot WS
                                     └── keyword_reply 插件
                                          └── 120张孤独摇滚表情包
```

## 📋 前置要求

- Docker & Docker Compose
- 一个 QQ 小号（建议用新注册的号）
- DeepSeek API Key（[免费申请](https://platform.deepseek.com)）

## 🚀 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/YOUR_USERNAME/qq-girlfriend-bot.git
cd qq-girlfriend-bot
```

### 2. 配置环境变量

```bash
cp .env.example .env
nano .env  # 填入你的 QQ 号和 DeepSeek API Key
```

需要填写的关键配置：

```bash
QQ_ACCOUNT=你的QQ号
DEEPSEEK_API_KEY=sk-xxxxxxxx
BOT_NICKNAME=小染    # 机器人的昵称
```

### 3. 启动

```bash
./start.sh
```

或手动启动：

```bash
docker compose up -d
```

### 4. 扫码登录（仅首次）

首次启动后，打开浏览器访问 `http://localhost:6099/webui`，用手机 QQ 扫描二维码授权登录。

> 登录状态会持久化保存，后续重启无需再次扫码。

### 5. 开始聊天

在手机 QQ 上搜索你设置的 QQ 号，加为好友后即可开始聊天！

## 📂 项目结构

```
.
├── docker-compose.yml           # Docker Compose 编排配置
├── .env.example                 # 环境变量模板
├── start.sh                     # 一键启动脚本
├── config/
│   └── astrbot_config.yaml      # AstrBot 配置文件
├── plugins/
│   └── keyword_reply/           # 关键词表情包插件
│       ├── metadata.yaml
│       └── main.py              # 18条关键词规则 + 120张BTR表情包
├── napcat/
│   └── config/
│       ├── onebot11_YOUR_QQ.json  # OneBot WS 配置模板
│       └── napcat.json            # NapCat 基础配置
└── stickers/                    # 表情包图片目录（运行时挂载）
```

## 🎛️ 管理后台

启动后可访问 AstrBot 管理后台进行更多配置：

- **地址**: `http://localhost:6185`
- **默认账号**: `astrbot`
- **默认密码**: 启动时在日志中随机生成（注意查看 `docker compose logs astrbot`）

在管理后台可以：
- 修改 AI 模型配置
- 调整人格设定（System Prompt）
- 添加/管理插件
- 查看对话日志

## 🧑‍🎤 自定义人格

机器人的人格设定存储在 AstrBot 数据库中。你可以通过管理后台或直接修改数据库来更换人格。

默认内置的「伊地知虹夏」人格特点：
- 元气满满，偶尔吐槽和捉弄人
- 说话像真正的JK女友，自然不做作
- 会提到乐队日常（波奇酱钻垃圾桶、凉前辈乱买东西）
- 不暴露自己是 AI

参考 `人格设定模板.txt` 了解更多提示词写法。

## 🎭 关键词表情包

机器人内置了关键词触发系统，在对话中提到特定词语会自动发送孤独摇滚（Bocchi the Rock!）表情包 + QQ 原生表情。

### 支持的关键词

| 关键词 | 效果 |
|--------|------|
| 原神 / 启动 | 随机 Bocchi 贴纸 + 😮 |
| 抽卡 / 保底 / 歪了 | 贴纸 + 💀 |
| 晚安 / 睡了 | 贴纸 + ☀️ |
| 早安 / 起床 | 贴纸 |
| 贴贴 / 抱抱 / 亲亲 | 贴纸 + ❤️ |
| 哈哈 / 笑死 | 贴纸 + 😂 |
| 呜呜 / QAQ / emo | 贴纸 |
| 摆烂 / 摸鱼 | 贴纸 + 🤔 |
| 好可爱 / 卡哇伊 | 贴纸 + 🥰 |
| 打鼓 / 乐队 / Live | 从120张中随机选 |
| 波奇 / 孤独摇滚 | 从120张中随机选 |
| 吃瓜 | QQ吃瓜表情 |
| 好耶 / 太棒了 | 贴纸 + 嘿嘿 |

> 表情包来自 Telegram 公开贴纸包，存放在 `stickers/` 目录。你可以随时替换为自己的图片。

### 如何添加更多关键词

编辑 `plugins/keyword_reply/main.py` 中的 `RULES` 列表即可。

## 🌐 网络热梗搜索

虹夏可以搜索最新的网络热梗并用她的风格回复。

1. 注册 [Tavily](https://tavily.com) 获取免费 API Key（1000次/月）
2. 在 `.env` 中添加：
```bash
TAVILY_API_KEY=你的Key
```
3. 重启：`docker compose restart astrbot`

她会在遇到不确定的热梗时自动搜索，然后用自己的话说出来（不会说"我搜了一下"）。

## 🛑 停止/关闭

```bash
docker compose down
```

聊天聊完了关掉就行，下次想聊再 `./start.sh`。

## ❓ 常见问题

### Q: 机器人没反应？

检查容器状态：`docker ps`，确认两个容器都在运行。查看日志：`docker compose logs astrbot`

### Q: 需要重新扫码？

登录态保存在 `napcat/qq_data/`，除非清了容器数据或腾讯要求重新验证，否则不需要重扫。

### Q: 能用其他 AI 模型吗？

支持所有 OpenAI 兼容的 API（DeepSeek、通义千问、智谱等），在管理后台修改提供商配置即可。

### Q: 需要一直开着电脑吗？

是的，机器人程序运行在你的电脑上。关掉电脑后机器人就下线了。

## 📄 License

MIT
