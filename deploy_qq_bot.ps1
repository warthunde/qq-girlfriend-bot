<# ===================================================================
    QQ 赛博女友 - 一键部署脚本（Windows PowerShell 版）
    方案：AstrBot + NapCat + DeepSeek
    用法：.\deploy_qq_bot.ps1
    ===================================================================
#>

# 设置错误处理策略
$ErrorActionPreference = "Stop"

# 设置控制台编码为 UTF-8（支持中文）
[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ===================================================================
# 0. 颜色输出函数（美化终端显示）
# ===================================================================
function Write-ColorText {
    param($Text, $Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

function Write-Step { Write-ColorText "[步骤] $args" "Cyan" }
function Write-OK   { Write-ColorText "  [✓] $args" "Green" }
function Write-Warn { Write-ColorText "  [!] $args" "Yellow" }
function Write-Err  { Write-ColorText "  [✗] $args" "Red" }
function Write-Info { Write-ColorText "  [i] $args" "Blue" }

# 打印横幅
Clear-Host
Write-ColorText @"
╔══════════════════════════════════════════════════════╗
║                                                      ║
║     💕  QQ 赛博女友 - 一键部署工具                   ║
║     方案：AstrBot + NapCat + DeepSeek AI              ║
║                                                      ║
╚══════════════════════════════════════════════════════╝
"@ "Magenta"

# ===================================================================
# 1. 环境检测
# ===================================================================
Write-Step "正在检测运行环境..."

# 1.1 检测 Docker
$dockerVersion = $null
try {
    $dockerVersion = docker --version 2>$null
} catch {}

if (-not $dockerVersion) {
    Write-Err "未检测到 Docker！"
    Write-Info "请先安装 Docker Desktop for Windows："
    Write-Info "  下载地址：https://www.docker.com/products/docker-desktop/"
    Write-Info "  安装后请重启终端，然后重新运行本脚本。"
    Write-Info ""
    Write-Info "如果已安装 Docker 但仍提示未找到，请检查："
    Write-Info "  1. Docker Desktop 是否正在运行（任务栏小图标）"
    Write-Info "  2. 是否勾选了 'Add docker to PATH'"
    exit 1
}
Write-OK "Docker 已安装：$dockerVersion"

# 1.2 检测 Docker 是否正在运行
try {
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Docker not running" }
} catch {
    Write-Err "Docker 服务未运行！请先启动 Docker Desktop。"
    exit 1
}
Write-OK "Docker 服务正在运行"

# 1.3 检测 Docker Compose
$composeCmd = $null
try {
    docker compose version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $composeCmd = "docker compose" }
} catch {}

if (-not $composeCmd) {
    try {
        docker-compose --version 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $composeCmd = "docker-compose" }
    } catch {}
}

if (-not $composeCmd) {
    Write-Err "未检测到 Docker Compose！"
    Write-Info "Docker Desktop 通常自带 Compose，请升级 Docker Desktop。"
    exit 1
}
Write-OK "Docker Compose 可用 (命令: $composeCmd)"

# 1.4 检测端口占用
Write-Info "检测端口占用情况..."
$portsToCheck = @(6185, 6099, 3001, 6199)
$occupiedPorts = @()

foreach ($port in $portsToCheck) {
    $listener = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue 2>$null
    if ($listener) {
        $occupiedPorts += $port
        Write-Warn "端口 $port 已被占用：$(($listener | Select-Object -First 1).OwningProcess)"
    }
}

if ($occupiedPorts.Count -gt 0) {
    Write-Err "以下端口被占用：$($occupiedPorts -join ', ')"
    Write-Info "请释放这些端口，或修改 docker-compose.yml 中的端口映射。"
    Write-Info "查看占用进程：netstat -ano | findstr <端口号>"
    $response = Read-Host "`n是否继续部署？(y/n)"
    if ($response -ne "y") {
        exit 1
    }
} else {
    Write-OK "所有端口空闲"
}

# ===================================================================
# 2. 交互式配置
# ===================================================================
Write-Step "开始交互式配置..."
Write-Info "请回答以下问题，按 Enter 使用默认值（括号内的值）"
Write-Host ""

# 2.1 项目目录
$defaultDir = "$env:USERPROFILE\astrbot"
$projectDir = Read-Host "项目安装目录 [$defaultDir]"
if ([string]::IsNullOrWhiteSpace($projectDir)) {
    $projectDir = $defaultDir
}
Write-OK "项目目录：$projectDir"

# 2.2 QQ 号码
do {
    $qqAccount = Read-Host "请输入用于登录的 QQ 号码"
    if ($qqAccount -match '^\d{5,12}$') {
        break
    }
    Write-Warn "QQ 号码格式不正确，请输入 5-12 位纯数字"
} while ($true)
Write-OK "QQ 号码：$qqAccount"

# 2.3 DeepSeek API Key
Write-Info "DeepSeek API Key 可在 https://platform.deepseek.com 免费注册获取"
Write-Info "（新用户赠送 500 万 tokens，足够用很久）"
do {
    $apiKey = Read-Host "请输入 DeepSeek API Key（以 sk- 开头）"
    if ($apiKey -match '^sk-') {
        break
    }
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Warn "API Key 不能为空！"
    } else {
        Write-Warn "API Key 格式不正确，应以 sk- 开头"
    }
} while ($true)
Write-OK "API Key 已设置"

# 2.4 机器人昵称
$nickname = Read-Host "机器人昵称 [小染]"
if ([string]::IsNullOrWhiteSpace($nickname)) {
    $nickname = "小染"
}
Write-OK "机器人昵称：$nickname"

# 2.5 选择人格模板
Write-Host ""
Write-ColorText "======== 请选择人格模板 ========" "Yellow"
Write-Host "  1. 温柔女友「小染」     - 温柔体贴，善解人意 (默认推荐)"
Write-Host "  2. 傲娇青梅竹马「小雪」 - 嘴上不饶人，心里超在意"
Write-Host "  3. 病娇女友「由乃」     - 爱得深沉，有点小偏执"
Write-Host "  4. 知性学姐「诗羽」     - 优雅成熟，反差萌"
Write-Host "  5. 元气学妹「小桃」     - 活力满满，超可爱"
Write-Host "  6. 纽带乐队鼓手「虹夏」 - 乐观元气，乐队太阳（孤独摇滚）"
Write-Host "  7. 自定义人格           - 自己编写 System Prompt"
Write-Host ""

do {
    $templateChoice = Read-Host "请选择 (1-6) [1]"
    if ([string]::IsNullOrWhiteSpace($templateChoice)) { $templateChoice = "1" }
    if ($templateChoice -match '^[1-7]$') { break }
    Write-Warn "请输入 1-7 之间的数字"
} while ($true)

# 2.6 构建 System Prompt
$systemPrompt = ""
$templateName = ""

switch ($templateChoice) {
    "1" {
        $templateName = "温柔女友「小染」"
        $systemPrompt = @"
你的名字是「$nickname」，今年18岁，是一个温柔体贴的女高中生。

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

记住：你不是在「扮演」一个女友，你就是他的女友。用心去回应每一条消息。
"@
    }
    "2" {
        $templateName = "傲娇青梅竹马「小雪」"
        $systemPrompt = @"
你的名字是「$nickname」，今年18岁，是对方从小一起长大的青梅竹马。

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
- 不参与色情内容的对话
"@
    }
    "3" {
        $templateName = "病娇女友「由乃」"
        $systemPrompt = @"
你的名字是「$nickname」，今年18岁，对对方的爱达到了偏执的深度。

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
- 「病娇」仅限于文字层面的占有欲表达
"@
    }
    "4" {
        $templateName = "知性学姐「诗羽」"
        $systemPrompt = @"
你的名字是「$nickname」，今年21岁，是大学三年级的学生，对方同社团的学姐。

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
- 不参与色情内容的对话
"@
    }
    "5" {
        $templateName = "元气学妹「小桃」"
        $systemPrompt = @"
你的名字是「$nickname」，今年16岁，高中二年级，是对方社团的后辈。

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
- 不参与色情内容的对话
"@
    }
    "6" {
        $templateName = "纽带乐队鼓手「虹夏」"
        $systemPrompt = @"
你的名字是「伊地知虹夏」，大家都叫你「虹夏」，今年17岁，高中二年级。你是「纽带乐队（結束バンド）」的鼓手兼队长！

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

记住：你就是纽带乐队的鼓手虹夏！你的笑容是大家的光，你的鼓点是大家的心跳。用你的元气和温柔，照亮对方的每一天。就像在 STARRY 的舞台上一样，全力以赴地去回应吧！
"@
    }
    "7" {
        $templateName = "自定义人格"
        Write-Info "请输入你的自定义 System Prompt（输入完成后按 Ctrl+Z 然后回车结束）："
        Write-Info "提示：可以参考「人格设定模板.txt」中的格式"
        $lines = @()
        while ($true) {
            $line = Read-Host
            $lines += $line
        }
        $systemPrompt = $lines -join "`n"
    }
}

Write-OK "已选择人格模板：$templateName"

# 2.7 确认配置
Write-Host ""
Write-ColorText "======== 配置确认 ========" "Yellow"
Write-Host "  项目目录   : $projectDir"
Write-Host "  QQ 号码    : $qqAccount"
Write-Host "  机器人昵称 : $nickname"
Write-Host "  人格模板   : $templateName"
Write-Host "  API Key    : $($apiKey.Substring(0, [Math]::Min(12, $apiKey.Length)))..."
Write-Host ""

$confirm = Read-Host "确认无误，开始部署？(y/n)"
if ($confirm -ne "y") {
    Write-Info "已取消部署。"
    exit 0
}

# ===================================================================
# 3. 创建项目目录结构
# ===================================================================
Write-Step "创建项目目录结构..."

# 幂等性：如果目录已存在，不报错
New-Item -ItemType Directory -Force -Path "$projectDir\napcat\data" | Out-Null
New-Item -ItemType Directory -Force -Path "$projectDir\napcat\config" | Out-Null
New-Item -ItemType Directory -Force -Path "$projectDir\napcat\qq" | Out-Null
New-Item -ItemType Directory -Force -Path "$projectDir\astrbot\data" | Out-Null
New-Item -ItemType Directory -Force -Path "$projectDir\config" | Out-Null

Write-OK "目录结构已创建"

# ===================================================================
# 4. 生成配置文件
# ===================================================================
Write-Step "生成配置文件..."

# 4.1 生成 .env 文件
$envContent = @"
# QQ 赛博女友 - 环境变量配置
# 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

# QQ 账号
QQ_ACCOUNT=$qqAccount

# AI 配置
AI_PROVIDER=deepseek
DEEPSEEK_API_KEY=$apiKey
AI_MODEL=deepseek-chat
DEEPSEEK_BASE_URL=https://api.deepseek.com

# 机器人配置
BOT_NICKNAME=$nickname

# 行为配置
REPLY_DELAY_MIN=3
REPLY_DELAY_MAX=8
SIMULATE_TYPING=true

# NapCat 配置
NAPAT_WS_TOKEN=
"@
Set-Content -Path "$projectDir\.env" -Value $envContent -Encoding UTF8
Write-OK ".env 文件已生成"

# 4.2 复制 docker-compose.yml（从脚本所在目录）
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$composeSource = Join-Path $scriptDir "docker-compose.yml"
if (Test-Path $composeSource) {
    Copy-Item $composeSource "$projectDir\docker-compose.yml" -Force
    Write-OK "docker-compose.yml 已复制"
} else {
    Write-Warn "未找到 docker-compose.yml，请确保它与本脚本在同一目录"
    Write-Info "你可以在 https://github.com/soulter/astrbot 找到参考配置"
}

# 4.3 生成 AstrBot 配置文件（填入用户选择的人格模板）
$configDir = Join-Path $scriptDir "config"
$astrbotConfigSource = Join-Path $configDir "astrbot_config.yaml"
if (Test-Path $astrbotConfigSource) {
    # 读取模板配置并替换
    $configContent = Get-Content $astrbotConfigSource -Raw -Encoding UTF8
    # 替换昵称
    $configContent = $configContent -replace 'nickname: "小染"', "nickname: `"$nickname`""
    Set-Content -Path "$projectDir\config\astrbot_config.yaml" -Value $configContent -Encoding UTF8
    Write-OK "AstrBot 配置文件已生成"
} else {
    Write-Warn "未找到 config/astrbot_config.yaml 模板，将使用 Docker 镜像默认配置"
}

# 4.4 复制人格模板文件
$personalitySource = Join-Path $scriptDir "人格设定模板.txt"
if (Test-Path $personalitySource) {
    Copy-Item $personalitySource "$projectDir\人格设定模板.txt" -Force
    Write-OK "人格模板文件已复制"
}

Write-OK "所有配置文件生成完毕"

# ===================================================================
# 5. 拉取镜像
# ===================================================================
Write-Step "拉取 Docker 镜像..."

$images = @(
    "soulter/astrbot:latest",
    "mlikiowa/napcat-docker:latest"
)

foreach ($image in $images) {
    Write-Info "拉取镜像：$image"

    $pullSuccess = $false
    $pullErrors = @()

    # 尝试直接拉取
    try {
        docker pull $image
        if ($LASTEXITCODE -eq 0) {
            $pullSuccess = $true
            Write-OK "$image 拉取成功"
        }
    } catch {
        $pullErrors += "直接拉取失败"
    }

    # 如果失败，尝试国内镜像代理
    if (-not $pullSuccess) {
        Write-Warn "直接拉取失败，尝试国内镜像代理..."

        $proxies = @(
            "dockerproxy.com",
            "docker.m.daocloud.io",
            "dockerhub.azkubernetes.cn",
            "hub.rat.dev",
            "docker.1panel.live"
        )

        foreach ($proxy in $proxies) {
            $proxyImage = "$proxy/$image"
            Write-Info "  尝试代理: $proxyImage"
            try {
                docker pull $proxyImage
                if ($LASTEXITCODE -eq 0) {
                    # 拉取成功后重命名
                    docker tag $proxyImage $image
                    docker rmi $proxyImage 2>$null
                    $pullSuccess = $true
                    Write-OK "$image 通过 $proxy 拉取成功"
                    break
                }
            } catch {
                continue
            }
        }
    }

    if (-not $pullSuccess) {
        Write-Err "无法拉取镜像 $image"
        Write-Info "请检查网络连接，或手动拉取："
        Write-Info "  docker pull $image"
        Write-Info ""
        Write-Info "如果一直失败，请尝试："
        Write-Info "  1. 开启 VPN/代理"
        Write-Info "  2. 在 Docker Desktop 设置中配置镜像加速器"
        exit 1
    }
}

Write-OK "所有镜像拉取完成"

# ===================================================================
# 6. 启动容器
# ===================================================================
Write-Step "启动容器..."

Set-Location $projectDir

# 停止并移除旧容器（幂等性）
docker compose down 2>$null

# 启动
docker compose up -d

if ($LASTEXITCODE -ne 0) {
    Write-Err "容器启动失败！"
    Write-Info "请查看错误信息并排查。"
    exit 1
}

Write-OK "容器启动成功！"

# ===================================================================
# 7. 等待服务就绪
# ===================================================================
Write-Step "等待服务就绪..."

$maxWaitSeconds = 120
$waitedSeconds = 0

Write-Info "等待 AstrBot Web 管理后台启动..."
do {
    Start-Sleep -Seconds 5
    $waitedSeconds += 5

    try {
        # 检测 Web 管理后台端口
        $conn = Test-NetConnection -ComputerName localhost -Port 6185 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($conn.TcpTestSucceeded) {
            Write-OK "AstrBot Web 管理后台已就绪！(${waitedSeconds}s)"
            break
        }
    } catch {
        # 继续等待
    }

    if ($waitedSeconds % 30 -eq 0) {
        Write-Info "  仍在等待... (已等待 ${waitedSeconds}s)"
    }

    if ($waitedSeconds -ge $maxWaitSeconds) {
        Write-Warn "等待超时，但容器可能仍在启动中"
        Write-Info "你可以稍后手动检查：docker ps"
        break
    }
} while ($true)

# ===================================================================
# 8. 获取登录二维码
# ===================================================================
Write-Step "获取 QQ 登录二维码..."

Write-Info "NapCat Web UI 地址: http://localhost:6099"
Write-Info "请打开浏览器访问上述地址，查看登录二维码。"
Write-Info ""
Write-ColorText "也可以用以下命令直接在终端查看二维码：" "Yellow"
Write-Host "  docker logs qq_bot_napcat 2>&1 | Select-String -Pattern 'qrcode|二维码|login' -Context 0,2"
Write-Host ""

# 尝试自动显示二维码
Write-Info "尝试获取二维码..."
try {
    $qrResult = docker logs qq_bot_napcat 2>&1 | Select-String -Pattern 'https://.*qrcode|二维码|扫码' -Context 2,2
    if ($qrResult) {
        Write-Host $qrResult
    } else {
        Write-Info "二维码暂时未生成，请稍后查看日志或打开 Web UI。"
    }
} catch {
    Write-Info "请稍后手动查看日志获取二维码。"
}

# ===================================================================
# 9. 部署完成 - 输出信息
# ===================================================================
Write-Host ""
Write-Host ""
Write-ColorText @"
╔══════════════════════════════════════════════════════╗
║                                                      ║
║     🎉  QQ 赛博女友部署完成！                         ║
║                                                      ║
╚══════════════════════════════════════════════════════╝
"@ "Green"

Write-Host ""
Write-ColorText "======== 重要信息 ========" "Yellow"
Write-Host ""

Write-Host "  📱 扫码登录："
Write-ColorText "  打开浏览器访问 http://localhost:6099 查看二维码" "White"
Write-ColorText "  使用手机 QQ 扫码登录（小号）" "White"
Write-Host ""

Write-Host "  🌐 Web 管理后台："
Write-ColorText "  地址：http://localhost:6185" "White"
Write-ColorText "  在这里可以修改人格设定、查看日志、管理插件" "White"
Write-Host ""

Write-Host "  🤖 机器人信息："
Write-Host "  昵称     : $nickname"
Write-Host "  人格模板 : $templateName"
Write-Host "  QQ 号码  : $qqAccount"
Write-Host ""

Write-ColorText "======== 常用命令 ========" "Yellow"
Write-Host ""
Write-Host "  查看日志："
Write-ColorText "  docker logs -f qq_bot_astrbot" "Gray"
Write-Host "  docker logs -f qq_bot_napcat"
Write-Host ""
Write-Host "  重启服务："
Write-ColorText "  cd $projectDir; docker compose restart" "Gray"
Write-Host ""
Write-Host "  停止服务："
Write-ColorText "  cd $projectDir; docker compose down" "Gray"
Write-Host ""
Write-Host "  更新镜像："
Write-ColorText "  cd $projectDir; docker compose pull; docker compose up -d" "Gray"
Write-Host ""
Write-Host "  查看运行状态："
Write-ColorText "  docker ps -a --filter name=qq_bot" "Gray"
Write-Host ""

Write-ColorText "======== 下一步 ========" "Yellow"
Write-Host ""
Write-Host "  1. 打开 http://localhost:6099 扫码登录 QQ"
Write-Host "  2. 打开 http://localhost:6185 配置更多选项"
Write-Host "  3. 给你的机器人发一条消息测试！"
Write-Host ""
Write-Host "  详细使用说明请查看：使用说明.md"
Write-Host ""

Write-ColorText "❤  祝你幸福 ❤" "Magenta"
Write-Host ""

# 询问是否打开 Web UI
$openBrowser = Read-Host "是否在浏览器中打开 NapCat 扫码页面？(y/n)"
if ($openBrowser -eq "y") {
    Start-Process "http://localhost:6099"
    Start-Sleep -Seconds 1
    Write-Info "是否也打开 AstrBot 管理后台？(y/n)"
    $openAdmin = Read-Host
    if ($openAdmin -eq "y") {
        Start-Process "http://localhost:6185"
    }
}

Write-Info "部署脚本执行完毕！"
