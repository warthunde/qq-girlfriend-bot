# ============================================================
# keyword_reply - 关键词触发图片/表情回复插件
# 使用真實的孤獨搖滾(BTR)表情包 + QQ 表情
# ============================================================

import re
import random
import os
from astrbot.api import star
from astrbot.api.event import AstrMessageEvent, filter
from astrbot.api.message_components import Image, Face
from astrbot.core import logger

# ============================================================
# 表情包目錄
# Bocchi the Rock: 120 stickers from Telegram pack
# ============================================================
BOCCHI_DIR = "/AstrBot/stickers/bocchi"

# 預加載所有可用圖片
def _list_images(directory):
    if not os.path.isdir(directory):
        return []
    return sorted([
        os.path.join(directory, f)
        for f in os.listdir(directory)
        if f.endswith(('.png', '.jpg', '.jpeg', '.webp', '.gif'))
    ])

AVAILABLE_BOCCHI = _list_images(BOCCHI_DIR)

# ============================================================
# 關鍵詞規則
# 每個規則：正則 + QQ Face表情ID + Bocchi圖片索引範圍
# ============================================================

# QQ 表情 Face ID:
# 0=驚訝 12=汗 14=吐血 21=坏笑 39=哭笑不得
# 66=爱心 74=太阳 76=玫瑰 109=可爱 111=嘿嘿
# 170=偷笑 176=大笑 178=憨笑 182=笑哭 183=破涕為笑
# 201=点赞 212=托腮 263=吃瓜 311=头秃 325=哇

RULES = [
    # ── 原神 ──
    {
        "pattern": r"原神|genshin|Genshin|启动",
        "faces": [325],  # 哇
        "bocchi_range": (80, 120),  # random range of bocchi stickers
        "use_all": True,
    },
    # ── 抽卡/保底 ──
    {
        "pattern": r"抽卡|十连|保底|歪了|沉了|欧皇|非酋",
        "faces": [14, 311],  # 吐血 or 头秃
        "bocchi_range": (10, 30),
    },
    # ── 星穹鐵道 ──
    {
        "pattern": r"星穹铁道|星铁|崩坏.*铁道|崩铁",
        "faces": [311],  # 头秃
        "bocchi_range": (80, 120),
        "use_all": True,
    },
    # ── 晚安/睡覺 ──
    {
        "pattern": r"晚安|睡了|困了.*[睡觉]|先睡了|去睡|睡觉",
        "faces": [74],  # 太阳
        "bocchi_range": (30, 50),
    },
    # ── 早安 ──
    {
        "pattern": r"早安|早上好|起床|早啊|哦哈哟|おはよう",
        "faces": [74],  # 太阳
        "bocchi_range": (30, 50),
    },
    # ── 餓了/吃飯 ──
    {
        "pattern": r"饿了|干饭|吃饭|[好想].*吃|外卖|夜宵|零食",
        "faces": [],
        "bocchi_range": (30, 50),
    },
    # ── 貼貼/抱抱 ──
    {
        "pattern": r"贴贴|抱抱|亲亲|mua|[么啵]一个|好き|suki",
        "faces": [66, 109],  # 爱心 + 可爱
        "bocchi_range": (50, 70),
    },
    # ── 哭/emo ──
    {
        "pattern": r"哭|emo|难过|伤心|呜呜|QAQ|TAT|[Tt][Tt]$|[Tt][Oo][Tt]",
        "faces": [],
        "bocchi_range": (0, 20),
    },
    # ── 大笑 ──
    {
        "pattern": r"哈哈{2,}|笑死|草$|草草|wwww|乐死|[笑哈]{3,}|www{2,}",
        "faces": [176, 182],  # 大笑 or 笑哭
        "bocchi_range": (50, 80),
    },
    # ── 摸魚/擺爛 ──
    {
        "pattern": r"摸鱼|摆烂|开摆|不想.*[上班学]|[躺瘫][平着]|懶|摆",
        "faces": [212],  # 托腮
        "bocchi_range": (0, 30),
    },
    # ── 可愛 ──
    {
        "pattern": r"好可爱|好萌|卡哇伊|kawaii|aw+[w]*$|可愛",
        "faces": [109, 66],  # 可爱 + 爱心
        "bocchi_range": (70, 100),
    },
    # ── 打鼓/樂隊/Live ──
    {
        "pattern": r"打鼓|架子鼓|鼓手|乐队|Live|演出|排练|STARRY|音樂|音乐|演奏",
        "faces": [201],  # 点赞
        "bocchi_range": (0, 120),
        "use_all": True,
    },
    # ── 吃瓜 ──
    {
        "pattern": r"吃瓜|八卦|瓜$|围观|什麼瓜|什么瓜",
        "faces": [263],  # 吃瓜
        "bocchi_range": (40, 70),
    },
    # ── 點讚/厲害 ──
    {
        "pattern": r"厉害|牛[逼掰]|6{2,}$|太强|NB|nb$|牛逼|牛啊",
        "faces": [201],  # 点赞
        "bocchi_range": (60, 90),
    },
    # ── 疑惑/問號 ──
    {
        "pattern": r"^\?{2,}$|什么.*[意思鬼]|没懂|不懂|啥意思|什麼.*意思|[？?]{2,}",
        "faces": [0],  # 惊讶
        "bocchi_range": (0, 20),
    },
    # ── 好耶/開心 ──
    {
        "pattern": r"好耶|太好了|nice|Nice|Nice|NICE|太棒|開心|YAY|yay",
        "faces": [111, 176],  # 嘿嘿 + 大笑
        "bocchi_range": (60, 90),
    },
    # ── 生氣/怒 ──
    {
        "pattern": r"生气|氣死|怒|不爽|讨厌|討厭|可惡|可恶|哼",
        "faces": [12],  # 汗
        "bocchi_range": (20, 40),
    },
    # ── 波奇/孤獨搖滾 ──
    {
        "pattern": r"波奇|孤独摇滚|孤獨搖滾|BTR|btr|bocchi|Bocchi|小孤独|後藤|后藤",
        "faces": [109, 111],
        "bocchi_range": (0, 120),
        "use_all": True,
    },
]

abort = False


class Main(star.Star):
    def __init__(self, context: star.Context):
        self.context = context
        self.compiled_rules = []
        for rule in RULES:
            self.compiled_rules.append({
                "regex": re.compile(rule["pattern"], re.IGNORECASE),
                "faces": rule["faces"],
                "bocchi_range": rule.get("bocchi_range", (0, len(AVAILABLE_BOCCHI))),
                "use_all": rule.get("use_all", False),
            })
        logger.info(f"[keyword_reply] Loaded {len(self.compiled_rules)} keyword rules")
        logger.info(f"[keyword_reply] Available Bocchi stickers: {len(AVAILABLE_BOCCHI)}")

    def _pick_image(self, rule):
        """從 Bocchi sticker 範圍中選一張圖片"""
        if not AVAILABLE_BOCCHI:
            return None

        if rule.get("use_all"):
            return random.choice(AVAILABLE_BOCCHI)

        start, end = rule.get("bocchi_range", (0, len(AVAILABLE_BOCCHI)))
        start = max(0, min(start, len(AVAILABLE_BOCCHI) - 1))
        end = max(start + 1, min(end, len(AVAILABLE_BOCCHI)))

        pool = AVAILABLE_BOCCHI[start:end]
        if not pool:
            pool = AVAILABLE_BOCCHI
        return random.choice(pool)

    @filter.event_message_type(filter.EventMessageType.ALL)
    async def on_message(self, event: AstrMessageEvent):
        try:
            msg_text = event.get_message_str()
            if not msg_text:
                return

            for rule in self.compiled_rules:
                if rule["regex"].search(msg_text):
                    chain = []

                    # QQ 表情
                    if rule["faces"]:
                        face_id = random.choice(rule["faces"])
                        chain.append(Face(id=face_id))

                    # Bocchi 圖片
                    img_path = self._pick_image(rule)
                    if img_path and os.path.exists(img_path):
                        chain.append(Image.fromFileSystem(img_path))

                    if chain:
                        yield event.chain_result(chain)
                        logger.info(
                            f"[keyword_reply] Triggered: {rule['regex'].pattern[:40]}"
                        )
                    break
        except Exception as e:
            logger.error(f"[keyword_reply] Error: {e}")
