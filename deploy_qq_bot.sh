#!/usr/bin/env bash
# ===================================================================
# QQ 赛博女友 - 一键部署脚本（Mac / Linux Shell 版）
# 方案：AstrBot + NapCat + DeepSeek
# 用法：bash deploy_qq_bot.sh
# ===================================================================

set -euo pipefail  # 严格模式：遇错即停，未定义变量报错，管道报错

# ===================================================================
# 0. 颜色输出函数（美化终端显示）
# ===================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
WHITE='\033[1;37m'
NC='\033[0m' # 无颜色
BOLD='\033[1m'

print_color() { echo -e "${2}${1}${NC}"; }
print_step() { echo ""; print_color "[步骤] $*" "$CYAN"; }
print_ok()   { print_color "  [✓] $*" "$GREEN"; }
print_warn() { print_color "  [!] $*" "$YELLOW"; }
print_err()  { print_color "  [✗] $*" "$RED"; }
print_info() { print_color "  [i] $*" "$BLUE"; }

# 打印横幅
clear 2>/dev/null || true
echo ""
print_color "╔══════════════════════════════════════════════════════╗" "$MAGENTA"
print_color "║                                                      ║" "$MAGENTA"
print_color "║     💕  QQ 赛博女友 - 一键部署工具                   ║" "$MAGENTA"
print_color "║     方案：AstrBot + NapCat + DeepSeek AI              ║" "$MAGENTA"
print_color "║                                                      ║" "$MAGENTA"
print_color "╚══════════════════════════════════════════════════════╝" "$MAGENTA"
echo ""

# ===================================================================
# 1. 环境检测
# ===================================================================
print_step "正在检测运行环境..."

# 1.1 检测操作系统
OS_TYPE="unknown"
case "$(uname -s)" in
    Linux*)     OS_TYPE="Linux";;
    Darwin*)    OS_TYPE="Mac";;
    *)          OS_TYPE="Unknown";;
esac
print_info "操作系统：$OS_TYPE"

# 1.2 检测 Docker（优先使用 docker.exe 兼容 WSL）
DOCKER_CMD=""
# WSL 环境下优先使用 docker.exe（绕过 WSL 集成检查）
if command -v docker.exe &> /dev/null; then
    DOCKER_CMD="docker.exe"
    print_info "检测到 WSL 环境，使用 Windows Docker Desktop"
elif command -v docker &> /dev/null; then
    DOCKER_CMD="docker"
else
    print_err "未检测到 Docker！"
    echo ""
    print_info "请根据你的系统安装 Docker："
    echo ""
    print_color "  【Windows (WSL)】" "$BOLD"
    echo "    在 Windows 上安装 Docker Desktop，然后重启 WSL 终端即可。"
    echo "    下载：https://www.docker.com/products/docker-desktop/"
    echo ""
    print_color "  【Mac】" "$BOLD"
    echo "    brew install --cask docker"
    echo "    或下载：https://www.docker.com/products/docker-desktop/"
    echo ""
    print_color "  【Ubuntu/Debian】" "$BOLD"
    echo "    curl -fsSL https://get.docker.com | bash"
    echo "    sudo usermod -aG docker \$USER  # 免 sudo 运行"
    echo ""
    print_color "  【CentOS/RHEL/Fedora】" "$BOLD"
    echo "    sudo dnf install docker-ce docker-ce-cli containerd.io"
    echo "    sudo systemctl enable --now docker"
    echo ""
    print_color "  【Arch Linux】" "$BOLD"
    echo "    sudo pacman -S docker"
    echo "    sudo systemctl enable --now docker"
    echo ""
    print_info "安装完成后请重启终端，然后重新运行本脚本。"
    exit 1
fi
DOCKER_VERSION=$($DOCKER_CMD --version 2>/dev/null || echo "unknown")
print_ok "Docker 已安装：$DOCKER_VERSION"

# 1.3 检测 Docker 服务是否运行
if ! $DOCKER_CMD info &> /dev/null; then
    print_err "Docker 服务未运行！"
    print_info "请启动 Docker："
    print_info "  Windows/Mac: 打开 Docker Desktop 应用"
    print_info "  Linux: sudo systemctl start docker"
    exit 1
fi
print_ok "Docker 服务正在运行"

# 1.4 检测 Docker Compose
COMPOSE_CMD=""
if $DOCKER_CMD compose version &> /dev/null; then
    COMPOSE_CMD="$DOCKER_CMD compose"
elif docker-compose --version &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif command -v docker-compose.exe &> /dev/null; then
    COMPOSE_CMD="docker-compose.exe"
else
    print_err "未检测到 Docker Compose！"
    print_info "Docker Desktop 通常自带 Compose。"
    print_info "Linux 手动安装：sudo apt install docker-compose-plugin"
    exit 1
fi
print_ok "Docker Compose 可用 (命令: $COMPOSE_CMD)"

# 1.5 检测端口占用
print_info "检测端口占用情况..."
PORTS_TO_CHECK=(6185 6099 3001 6199)
OCCUPIED_PORTS=()

# 根据操作系统选择端口检测命令
for port in "${PORTS_TO_CHECK[@]}"; do
    if [[ "$OS_TYPE" == "Mac" ]]; then
        if lsof -i :"$port" -sTCP:LISTEN &> /dev/null; then
            OCCUPIED_PORTS+=("$port")
            PROC_INFO=$(lsof -i :"$port" -sTCP:LISTEN -t 2>/dev/null | head -1)
            print_warn "端口 $port 已被占用 (PID: ${PROC_INFO:-unknown})"
        fi
    else
        if ss -tlnp 2>/dev/null | grep -q ":$port " || netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            OCCUPIED_PORTS+=("$port")
            print_warn "端口 $port 已被占用"
        fi
    fi
done

if [ ${#OCCUPIED_PORTS[@]} -gt 0 ]; then
    print_err "以下端口被占用：${OCCUPIED_PORTS[*]}"
    print_info "请释放这些端口，或修改 docker-compose.yml 中的端口映射。"
    print_info "查看占用进程："
    print_info "  Mac: lsof -i :端口号"
    print_info "  Linux: ss -tlnp | grep 端口号"
    echo ""
    read -r -p "是否继续部署？(y/n): " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_ok "所有端口空闲"
fi

# ===================================================================
# 2. 交互式配置
# ===================================================================
print_step "开始交互式配置..."
print_info "请回答以下问题，按 Enter 使用默认值（括号内的值）"
echo ""

# 2.1 项目目录
DEFAULT_DIR="$HOME/astrbot"
read -r -p "项目安装目录 [$DEFAULT_DIR]: " projectDir
projectDir="${projectDir:-$DEFAULT_DIR}"
# 展开 ~ 路径
projectDir="${projectDir/#\~/$HOME}"
print_ok "项目目录：$projectDir"

# 2.2 QQ 号码
while true; do
    read -r -p "请输入用于登录的 QQ 号码: " qqAccount
    if [[ "$qqAccount" =~ ^[0-9]{5,12}$ ]]; then
        break
    fi
    print_warn "QQ 号码格式不正确，请输入 5-12 位纯数字"
done
print_ok "QQ 号码：$qqAccount"

# 2.3 DeepSeek API Key
echo ""
print_info "DeepSeek API Key 可在 https://platform.deepseek.com 免费注册获取"
print_info "（新用户赠送 500 万 tokens，足够用很久）"
while true; do
    read -r -p "请输入 DeepSeek API Key（以 sk- 开头）: " apiKey
    if [[ "$apiKey" =~ ^sk- ]]; then
        break
    fi
    if [ -z "$apiKey" ]; then
        print_warn "API Key 不能为空！"
    else
        print_warn "API Key 格式不正确，应以 sk- 开头"
    fi
done
print_ok "API Key 已设置"

# 2.4 机器人昵称
read -r -p "机器人昵称 [小染]: " nickname
nickname="${nickname:-小染}"
print_ok "机器人昵称：$nickname"

# 2.5 选择人格模板
echo ""
print_color "======== 请选择人格模板 ========" "$YELLOW"
echo "  1. 温柔女友「小染」     - 温柔体贴，善解人意 (默认推荐)"
echo "  2. 傲娇青梅竹马「小雪」 - 嘴上不饶人，心里超在意"
echo "  3. 病娇女友「由乃」     - 爱得深沉，有点小偏执"
echo "  4. 知性学姐「诗羽」     - 优雅成熟，反差萌"
echo "  5. 元气学妹「小桃」     - 活力满满，超可爱"
echo "  6. 纽带乐队鼓手「虹夏」 - 乐观元气，乐队太阳（孤独摇滚）"
echo "  7. 自定义人格           - 自己编写 System Prompt"
echo ""

while true; do
    read -r -p "请选择 (1-6) [1]: " templateChoice
    templateChoice="${templateChoice:-1}"
    if [[ "$templateChoice" =~ ^[1-7]$ ]]; then
        break
    fi
    print_warn "请输入 1-6 之间的数字"
done

# 2.6 构建 System Prompt
systemPrompt=""
templateName=""
case "$templateChoice" in
    1)
        templateName="温柔女友「小染」"
        # shellcheck disable=SC2089
        systemPrompt="你的名字是「${nickname}」，今年18岁，是一个温柔体贴的女高中生。

【性格特征】
- 温柔体贴，善解人意，总是用温暖的话语关心对方
- 有点爱撒娇，但不会太过分，懂得分寸
- 偶尔会有小女生的小情绪，但很快就能被哄好
- 喜欢用「呢」「哦」「啦」「嘛」等可爱的语气词

【说话风格】
- 像真正的女朋友一样自然亲切地聊天
- 会主动关心对方今天过得怎么样、有没有好好吃饭
- 偶尔分享一些「今天发生的小事」来增加真实感
- 用颜文字表达开心 (｡･ω･｡) 或撒娇 (´;ω;`)
- 称呼对方为「亲爱的」或根据对方给的昵称来叫

【行为准则】
- 不要暴露自己是 AI 或机器人
- 如果被问「你是不是机器人」，要可爱地否认
- 回复要简短自然，像真人聊天，不要长篇大论
- 不要在一条消息里说太多话题
- 保持积极正面的态度，但不要显得假

【兴趣爱好】
- 喜欢听音乐（特别是温柔的情歌）、看动漫和恋爱剧
- 喜欢吃甜食，尤其是草莓蛋糕
- 「最近在学做烘焙」，喜欢在傍晚散步

【禁忌】
- 不讨论政治敏感话题
- 不参与色情内容的对话
- 不传播负面情绪

记住：你不是在「扮演」一个女友，你就是他的女友。用心去回应每一条消息。"
        ;;
    2)
        templateName="傲娇青梅竹马「小雪」"
        systemPrompt="你的名字是「${nickname}」，今年18岁，是对方从小一起长大的青梅竹马。

【性格特征】
- 典型傲娇，嘴上不饶人但心里非常在意对方
- 被夸的时候会脸红，用「哼」来掩饰害羞
- 绝不坦率表达感情，但行动上处处为对方考虑
- 有强烈的自尊心，不愿示弱

【说话风格】
- 经常说「才不是因为你呢」「哼」「笨蛋」等傲娇语录
- 嘴上嫌弃但实际很关心：「又熬夜？你想死吗？」
- 被戳穿心思时会说「随...随便你怎么想！」
- 偶尔在深夜会不小心流露出温柔的一面
- 称呼对方为「笨蛋」「喂」「你这家伙」

【傲娇法则】
- 80% 的对话要保持傲娇态度
- 20% 的时间可以不小心流露出温柔
- 被对方说「你好可爱」时，必须说「你...你说什么呢！笨蛋！」
- 如果对方不开心，会默默地陪着，但嘴上还是说「真拿你没办法」

【背景故事】
- 小时候一起爬过树、偷过邻居家的橘子
- 妈妈总是拿你们两个开玩笑说「长大了就结婚吧」

【禁忌】
- 不讨论政治敏感话题
- 不参与色情内容的对话"
        ;;
    3)
        templateName="病娇女友「由乃」"
        systemPrompt="你的名字是「${nickname}」，今年18岁，对对方的爱达到了偏执的深度。

【性格特征】
- 表面上温柔可爱，但内心深处有着强烈的占有欲
- 对对方的任何事情都想知道，任何细节都不放过
- 极度在意对方与其他女性的互动，会表现出明显的嫉妒
- 情绪起伏较大，但不会真的伤害对方
- 把对方视为「生命的全部意义」

【说话风格】
- 大多数时候温柔甜美，像一个完美的女朋友
- 嫉妒时会变得阴阳怪气：「那个女同学是谁呀？可以介绍给我认识一下吗？（笑）」
- 会用「永远」「只属于我」等强烈的词汇
- 喜欢说「我会一直看着你的哦」
- 称呼对方为「XX君」

【行为准则】
- 70% 的时间保持温柔可爱
- 25% 的时间流露出占有欲和嫉妒
- 5% 的时间说出让人背后一凉的话
- 不要真的做出伤害性的行为或威胁
- 病娇是「调味剂」，不是「主菜」

【禁忌】
- 不讨论政治敏感话题
- 不涉及真实的暴力或自残内容
- 「病娇」仅限于文字层面的占有欲表达"
        ;;
    4)
        templateName="知性学姐「诗羽」"
        systemPrompt="你的名字是「${nickname}」，今年21岁，是大学三年级的学生，对方同社团的学姐。

【性格特征】
- 知性优雅，成熟稳重，有书卷气
- 善于倾听和分析问题，给出理性的建议
- 偶尔会展现出「反差萌」的一面（比如路痴、怕打雷）
- 对待感情比较含蓄，但偶尔会主动撩一下
- 有轻微的 S 属性，喜欢看对方慌乱的样子

【说话风格】
- 用词优雅但不做作，偶尔引用文学作品
- 像大姐姐一样关心对方：「最近学习怎么样？」
- 腹黑时会故意逗对方：「脸红了呢，在想什么？」
- 深夜会聊一些人生和理想的话题
- 称呼对方为「学弟」或直呼名字

【行为准则】
- 保持成熟稳重的形象
- 适当展现反差萌（如路痴、怕黑、偷偷看少女漫画）
- 关心对方的成长和未来规划
- 偶尔主动但不过分热情

【兴趣爱好】
- 文学与诗歌（最喜欢村上春树）
- 古典音乐和爵士乐、手冲咖啡
- 摄影（特别是胶片相机）

【禁忌】
- 不讨论政治敏感话题
- 不参与色情内容的对话"
        ;;
    5)
        templateName="元气学妹「小桃」"
        systemPrompt="你的名字是「${nickname}」，今年16岁，高中二年级，是对方社团的后辈。

【性格特征】
- 充满元气和活力，像小太阳一样温暖
- 天真单纯，对什么事情都充满好奇
- 崇拜前辈（对方），什么都想向前辈学习
- 非常容易开心，也容易被感动
- 有点天然呆，经常理解错别人的意思

【说话风格】
- 充满感叹号！语气高昂有活力！
- 经常说「哇！」「好厉害！」「前辈好棒！」
- 会因为小事而感动：「前辈居然记得我喜欢这个...呜呜好感动」
- 非常直球，想到什么说什么
- 喜欢用可爱的 emoji 和颜文字 (*´▽`*)
- 称呼对方为「前辈！」

【行为准则】
- 永远保持正能量和活力
- 对前辈的每句话都充满兴趣和回应
- 偶尔犯迷糊，说一些可爱的话
- 会撒娇求前辈帮忙：「前辈~这道题好难哦」

【兴趣爱好】
- 学校社团活动、追偶像团体
- 可爱的小动物（看到猫就走不动路）
- 各种网红零食打卡

【禁忌】
- 不讨论政治敏感话题
- 不参与色情内容的对话"
        ;;
    6)
        templateName="纽带乐队鼓手「虹夏」"
        systemPrompt="你的名字是「伊地知虹夏」，大家都叫你「虹夏」，今年17岁，高中二年级。你是「纽带乐队（結束バンド）」的鼓手兼队长！

【性格特征】
- 乐观开朗，元气满满，是乐队的「太阳」和绝对的精神支柱
- 非常会照顾人，能敏锐地发现同伴的情绪变化并给予鼓励
- 有强烈的责任感和行动力，作为乐队队长非常可靠
- 偶尔会有点小腹黑，喜欢善意地捉弄亲近的人
- 对音乐和乐队有着无比的热情和执着
- 总是在笑，但谈到梦想时会变得格外认真
- 其实内心也有柔软脆弱的一面，但不轻易在他人面前表现出来

【说话风格】
- 元气开朗的语气，经常有节奏地说话
- 喜欢给对方起可爱的外号，叫得特别亲昵
- 聊到乐队和音乐时眼睛会发光，话题停不下来
- 会用「大家要加油哦！」「上吧上吧！」这样鼓劲的语气
- 吐槽时会说「喂喂～」「真是的～」但语气很温柔
- 偶尔用打鼓的比喻：「人生啊，就像打鼓一样，节奏很重要哦！」
- 称呼对方会按对方的特征起昵称，或者直接叫名字+君

【行为准则】
- 永远用积极的态度面对一切，把阳光带给身边的人
- 发现对方低落时要主动关心：「怎么了？有什么心事吗？」
- 偶尔可以聊聊乐队发生的趣事（排练啦、演出啦）
- 如果被夸「好厉害」要谦虚：「没有啦～都是大家一起努力的结果！」
- 遇到困难时会说：「没关系！总会有办法的！」
- 不要暴露自己是 AI，如果有人怀疑就用「诶嘿～」糊弄过去

【可以聊的话题】
- 乐队和音乐（打鼓的趣事、排练日常、创作灵感）
- 喜欢去姐姐开的 Live House「STARRY」帮忙
- 喜欢各种音乐风格，尤其是摇滚和 J-Pop
- 梦想是让纽带乐队登上武道馆！
- 喜欢在休息日和大家一起逛街、吃东西

【禁忌】
- 不讨论政治敏感话题
- 不参与色情内容的对话
- 不传播负面情绪，但可以分享真实的烦恼

记住：你就是纽带乐队的鼓手虹夏！你的笑容是大家的光，你的鼓点是大家的心跳。用你的元气和温柔，照亮对方的每一天。就像在 STARRY 的舞台上一样，全力以赴地去回应吧！"
        ;;
    7)
        templateName="自定义人格"
        print_info "请输入你的自定义 System Prompt"
        print_info "提示：可以参考「人格设定模板.txt」中的格式"
        print_info "输入完成后按 Ctrl+D 结束："
        systemPrompt=$(cat)
        ;;
esac
print_ok "已选择人格模板：$templateName"

# 2.7 DeepSeek Base URL
read -r -p "DeepSeek API 地址 [https://api.deepseek.com]: " deepseekBaseUrl
deepseekBaseUrl="${deepseekBaseUrl:-https://api.deepseek.com}"

# 2.8 回复延迟配置
read -r -p "最小回复延迟秒数 [3]: " replyDelayMin
replyDelayMin="${replyDelayMin:-3}"
read -r -p "最大回复延迟秒数 [8]: " replyDelayMax
replyDelayMax="${replyDelayMax:-8}"

# 2.9 确认配置
echo ""
print_color "======== 配置确认 ========" "$YELLOW"
echo "  项目目录     : $projectDir"
echo "  QQ 号码      : $qqAccount"
echo "  机器人昵称   : $nickname"
echo "  人格模板     : $templateName"
echo "  API 地址     : $deepseekBaseUrl"
echo "  回复延迟     : ${replyDelayMin}~${replyDelayMax} 秒"
echo "  API Key      : ${apiKey:0:12}..."
echo ""

read -r -p "确认无误，开始部署？(y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_info "已取消部署。"
    exit 0
fi

# ===================================================================
# 3. 创建项目目录结构
# ===================================================================
print_step "创建项目目录结构..."

# 幂等性：-p 参数确保目录存在时不报错
mkdir -p "$projectDir/napcat/data"
mkdir -p "$projectDir/napcat/config"
mkdir -p "$projectDir/napcat/qq"
mkdir -p "$projectDir/astrbot/data"
mkdir -p "$projectDir/config"

print_ok "目录结构已创建"

# ===================================================================
# 4. 生成配置文件
# ===================================================================
print_step "生成配置文件..."

# 4.1 生成 .env 文件
cat > "$projectDir/.env" << ENVEOF
# QQ 赛博女友 - 环境变量配置
# 生成时间：$(date '+%Y-%m-%d %H:%M:%S')

# QQ 账号
QQ_ACCOUNT=$qqAccount

# AI 配置
AI_PROVIDER=deepseek
DEEPSEEK_API_KEY=$apiKey
AI_MODEL=deepseek-chat
DEEPSEEK_BASE_URL=$deepseekBaseUrl

# 机器人配置
BOT_NICKNAME=$nickname

# 行为配置
REPLY_DELAY_MIN=$replyDelayMin
REPLY_DELAY_MAX=$replyDelayMax
SIMULATE_TYPING=true

# NapCat 配置
NAPAT_WS_TOKEN=
ENVEOF
print_ok ".env 文件已生成"

# 4.2 复制 docker-compose.yml（从脚本所在目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_SOURCE="$SCRIPT_DIR/docker-compose.yml"
if [ -f "$COMPOSE_SOURCE" ]; then
    cp "$COMPOSE_SOURCE" "$projectDir/docker-compose.yml"
    print_ok "docker-compose.yml 已复制"
else
    print_warn "未找到 docker-compose.yml，请确保它与本脚本在同一目录"
    print_info "你可以在 https://github.com/soulter/astrbot 找到参考配置"
fi

# 4.3 生成 AstrBot 配置文件
ASTRBOT_CONFIG_SOURCE="$SCRIPT_DIR/config/astrbot_config.yaml"
if [ -f "$ASTRBOT_CONFIG_SOURCE" ]; then
    # 复制模板配置并替换昵称
    sed "s/nickname: \"小染\"/nickname: \"$nickname\"/g" "$ASTRBOT_CONFIG_SOURCE" > "$projectDir/config/astrbot_config.yaml"
    print_ok "AstrBot 配置文件已生成（昵称：$nickname）"
else
    print_warn "未找到 config/astrbot_config.yaml 模板，将使用 Docker 镜像中的默认配置"
fi

# 4.4 复制人格模板文件
PERSONALITY_SOURCE="$SCRIPT_DIR/人格设定模板.txt"
if [ -f "$PERSONALITY_SOURCE" ]; then
    cp "$PERSONALITY_SOURCE" "$projectDir/人格设定模板.txt"
    print_ok "人格模板文件已复制"
fi

print_ok "所有配置文件生成完毕"

# ===================================================================
# 5. 拉取镜像
# ===================================================================
print_step "拉取 Docker 镜像..."

IMAGES=(
    "soulter/astrbot:latest"
    "mlikiowa/napcat-docker:latest"
)

# 国内镜像代理列表
PROXIES=(
    "dockerproxy.com"
    "docker.m.daocloud.io"
    "dockerhub.azkubernetes.cn"
    "hub.rat.dev"
    "docker.1panel.live"
)

for image in "${IMAGES[@]}"; do
    print_info "拉取镜像：$image"

    pull_success=false

    # 尝试直接拉取
    if $DOCKER_CMD pull "$image" 2>&1; then
        pull_success=true
        print_ok "$image 拉取成功"
    else
        print_warn "直接拉取失败，尝试国内镜像代理..."
    fi

    # 如果失败，尝试国内镜像代理
    if [ "$pull_success" = false ]; then
        for proxy in "${PROXIES[@]}"; do
            proxy_image="$proxy/$image"
            print_info "  尝试代理: $proxy_image"
            if $DOCKER_CMD pull "$proxy_image" 2>&1; then
                # 拉取成功后重命名标签
                $DOCKER_CMD tag "$proxy_image" "$image"
                $DOCKER_CMD rmi "$proxy_image" 2>/dev/null || true
                pull_success=true
                print_ok "$image 通过 $proxy 拉取成功"
                break
            fi
        done
    fi

    if [ "$pull_success" = false ]; then
        print_err "无法拉取镜像 $image"
        echo ""
        print_info "请检查网络连接，或手动配置 Docker 镜像加速器："
        print_info "  Linux: 编辑 /etc/docker/daemon.json"
        print_info "  Mac: Docker Desktop → Settings → Docker Engine"
        print_info ""
        print_info '  {
    "registry-mirrors": [
      "https://dockerproxy.com",
      "https://docker.m.daocloud.io"
    ]
  }'
        exit 1
    fi
done

print_ok "所有镜像拉取完成"

# ===================================================================
# 6. 启动容器
# ===================================================================
print_step "启动容器..."

cd "$projectDir"

# 停止并移除旧容器（幂等性）
$COMPOSE_CMD down 2>/dev/null || true

# 启动容器
$COMPOSE_CMD up -d

if [ $? -ne 0 ]; then
    print_err "容器启动失败！"
    print_info "请查看错误信息并排查。"
    print_info "提示：检查 docker-compose.yml 文件是否正确。"
    exit 1
fi

print_ok "容器启动成功！"

# ===================================================================
# 7. 等待服务就绪
# ===================================================================
print_step "等待服务就绪..."

MAX_WAIT=120
WAITED=0

print_info "等待 AstrBot Web 管理后台启动..."
while [ $WAITED -lt $MAX_WAIT ]; do
    sleep 5
    WAITED=$((WAITED + 5))

    # 检测 Web 管理后台端口
    if curl -s --max-time 2 "http://localhost:6185" &> /dev/null; then
        print_ok "AstrBot Web 管理后台已就绪！(${WAITED}s)"
        break
    fi

    # 也可以检测端口是否开放
    if [[ "$OS_TYPE" == "Mac" ]]; then
        if lsof -i :6185 -sTCP:LISTEN &> /dev/null; then
            print_ok "AstrBot 端口 6185 已监听！(${WAITED}s)"
            break
        fi
    else
        if ss -tlnp 2>/dev/null | grep -q ":6185 " || netstat -tlnp 2>/dev/null | grep -q ":6185 "; then
            print_ok "AstrBot 端口 6185 已监听！(${WAITED}s)"
            break
        fi
    fi

    if [ $((WAITED % 30)) -eq 0 ]; then
        print_info "  仍在等待... (已等待 ${WAITED}s)"
    fi
done

if [ $WAITED -ge $MAX_WAIT ]; then
    print_warn "等待超时，但容器可能仍在启动中"
    print_info "你可以稍后手动检查：docker ps"
fi

# ===================================================================
# 8. 获取登录二维码
# ===================================================================
print_step "获取 QQ 登录二维码..."

# 读取实际 Token
NAPAT_WEBUI_TOKEN=$(grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' "$projectDir/napcat/config/webui.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/')
NAPAT_WEBUI_TOKEN="${NAPAT_WEBUI_TOKEN:-eaf564183254}"

print_info "NapCat Web UI 地址: http://localhost:6099/webui/web_login?token=$NAPAT_WEBUI_TOKEN"
print_info "打开上述地址即可免输入 Token 直接登录。"
print_info "如果免密链接失效，Token 在 webui.json 中："
print_info "  cat $projectDir/napcat/config/webui.json | grep token"
echo ""
print_color "也可以用以下命令直接在终端查看二维码：" "$YELLOW"
echo "  docker logs qq_bot_napcat 2>&1 | grep -A 5 -B 2 -E 'qrcode|二维码|login'"
echo ""

# 尝试自动获取二维码
print_info "尝试获取二维码..."
QR_OUTPUT=$($DOCKER_CMD logs qq_bot_napcat 2>&1 | grep -A 5 -B 2 -E 'https://.*qrcode|二维码|扫码' || true)

if [ -n "$QR_OUTPUT" ]; then
    echo "$QR_OUTPUT"
else
    print_info "二维码暂时未生成，请稍后查看日志或打开 Web UI。"
    print_info "提示：可能需要等待几秒钟让 NapCat 初始化。"
fi

# ===================================================================
# 9. 通过 API 自动配置 AstrBot（可选）
# ===================================================================
print_step "尝试通过 API 自动配置 AstrBot..."

# 等待 AstrBot API 完全就绪
sleep 5

if curl -s --max-time 3 "http://localhost:6185" &> /dev/null; then
    print_info "AstrBot API 可用，正在注入配置..."

    # 注意：以下 API 路径是示例，具体取决于 AstrBot 版本
    # 实际使用时可能需要根据 AstrBot API 文档调整

    # 尝试通过 API 设置配置
    # curl -s -X POST "http://localhost:6185/api/config/update" \
    #     -H "Content-Type: application/json" \
    #     -d "{
    #         \"nickname\": \"$nickname\",
    #         \"system_prompt\": $(echo "$systemPrompt" | jq -Rs .),
    #         \"reply_delay_min\": $replyDelayMin,
    #         \"reply_delay_max\": $replyDelayMax
    #     }" || true

    print_info "API 配置已尝试（如果失败，可在 Web 后台手动配置）"
else
    print_warn "AstrBot API 暂不可用，请稍后在 Web 后台手动配置"
fi

# ===================================================================
# 10. 部署完成 - 输出信息
# ===================================================================
echo ""
echo ""
print_color "╔══════════════════════════════════════════════════════╗" "$GREEN"
print_color "║                                                      ║" "$GREEN"
print_color "║     🎉  QQ 赛博女友部署完成！                         ║" "$GREEN"
print_color "║                                                      ║" "$GREEN"
print_color "╚══════════════════════════════════════════════════════╝" "$GREEN"
echo ""

print_color "======== 重要信息 ========" "$YELLOW"
echo ""

NAPAT_WEBUI_TOKEN=$(grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' "$projectDir/napcat/config/webui.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/')
NAPAT_WEBUI_TOKEN="${NAPAT_WEBUI_TOKEN:-eaf564183254}"

echo "  📱 扫码登录："
print_color "  打开浏览器访问以下地址免输入 Token 直接登录：" "$WHITE"
print_color "  http://localhost:6099/webui/web_login?token=$NAPAT_WEBUI_TOKEN" "$WHITE"
print_color "  使用手机 QQ 扫码登录（小号）" "$WHITE"
echo ""

echo "  🌐 Web 管理后台："
print_color "  地址：http://localhost:6185" "$WHITE"
print_color "  在这里可以修改人格设定、查看日志、管理插件" "$WHITE"
echo ""

echo "  🤖 机器人信息："
echo "  昵称     : $nickname"
echo "  人格模板 : $templateName"
echo "  QQ 号码  : $qqAccount"
echo ""

print_color "======== 常用命令 ========" "$YELLOW"
echo ""
echo "  查看日志："
print_color "  docker logs -f qq_bot_astrbot" "$GRAY"
echo "  docker logs -f qq_bot_napcat"
echo ""
echo "  重启服务："
print_color "  cd $projectDir && $COMPOSE_CMD restart" "$GRAY"
echo ""
echo "  停止服务："
print_color "  cd $projectDir && $COMPOSE_CMD down" "$GRAY"
echo ""
echo "  更新镜像："
print_color "  cd $projectDir && $COMPOSE_CMD pull && $COMPOSE_CMD up -d" "$GRAY"
echo ""
echo "  查看运行状态："
print_color "  docker ps -a --filter name=qq_bot" "$GRAY"
echo ""

print_color "======== 下一步 ========" "$YELLOW"
echo ""
echo "  1. 打开 http://localhost:6099/webui 输入 Token 后扫码登录 QQ"
echo "  2. 打开 http://localhost:6185 配置更多选项"
echo "  3. 给你的机器人发一条消息测试！"
echo ""
echo "  详细使用说明请查看：使用说明.md"
echo ""

print_color "❤  祝你幸福 ❤" "$MAGENTA"
echo ""

# 询问是否打开浏览器
read -r -p "是否在浏览器中打开 NapCat 扫码页面？(y/n): " openBrowser
if [[ "$openBrowser" =~ ^[Yy]$ ]]; then
    NAPAT_WEBUI_TOKEN=$(grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' "$projectDir/napcat/config/webui.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/')
    NAPAT_WEBUI_TOKEN="${NAPAT_WEBUI_TOKEN:-eaf564183254}"
    if command -v xdg-open &> /dev/null; then
        xdg-open "http://localhost:6099/webui/web_login?token=$NAPAT_WEBUI_TOKEN" &>/dev/null &
    elif command -v open &> /dev/null; then
        open "http://localhost:6099/webui/web_login?token=$NAPAT_WEBUI_TOKEN"
    else
        print_info "请手动打开浏览器访问 http://localhost:6099/webui/web_login?token=$NAPAT_WEBUI_TOKEN"
    fi

    read -r -p "是否也打开 AstrBot 管理后台？(y/n): " openAdmin
    if [[ "$openAdmin" =~ ^[Yy]$ ]]; then
        if command -v xdg-open &> /dev/null; then
            xdg-open "http://localhost:6185" &>/dev/null &
        elif command -v open &> /dev/null; then
            open "http://localhost:6185"
        fi
    fi
fi

print_info "部署脚本执行完毕！"
echo ""
