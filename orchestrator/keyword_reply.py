"""
Keyword Reply — 关键词触发表情包回复
从 AstrBot 插件移植，适配 OneBot v11 消息格式

检测消息中的关键词，返回对应的 QQ 表情 + 图片消息段。
图片需要 NapCat 能访问到（通过文件路径）。
"""

import os
import re
import random
import logging

logger = logging.getLogger(__name__)

# ─── QQ 表情 Face ID ─────────────────────────────────────
# 0=惊讶 12=汗 14=吐血 21=坏笑 39=哭笑不得
# 66=爱心 74=太阳 76=玫瑰 109=可爱 111=嘿嘿
# 170=偷笑 176=大笑 178=憨笑 182=笑哭 183=破涕为笑
# 201=点赞 212=托腮 263=吃瓜 311=头秃 325=哇

# ─── 贴纸图片目录 ──────────────────────────────────────
# DOCKER_STICKER_DIR: NapCat 容器内路径（OneBot file:// URI 使用）
# HOST_STICKER_DIR:  宿主机路径（列表图片用）
DOCKER_STICKER_DIR = "/app/stickers"
HOST_STICKER_DIR = os.getenv("STICKER_DIR", os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "stickers"
))
HOST_BOCCHI_DIR = os.path.join(HOST_STICKER_DIR, "bocchi")
DOCKER_BOCCHI_DIR = os.path.join(DOCKER_STICKER_DIR, "bocchi")


def _list_images(directory: str) -> list[str]:
    """列出目录下所有图片文件"""
    if not os.path.isdir(directory):
        return []
    return sorted([
        f for f in os.listdir(directory)
        if f.endswith(('.png', '.jpg', '.jpeg', '.webp', '.gif'))
    ])


# ─── 关键词规则 ──────────────────────────────────────────

RULES: list[dict] = [
    # 原神
    {
        "pattern": r"原神|genshin|Genshin|启动",
        "faces": [325],
        "bocchi_range": (80, 120),
        "use_all": True,
    },
    # 抽卡
    {
        "pattern": r"抽卡|十连|保底|歪了|沉了|欧皇|非酋",
        "faces": [14, 311],
        "bocchi_range": (10, 30),
    },
    # 星穹铁道
    {
        "pattern": r"星穹铁道|星铁|崩坏.*铁道|崩铁",
        "faces": [311],
        "bocchi_range": (80, 120),
        "use_all": True,
    },
    # 晚安
    {
        "pattern": r"晚安|睡了|困了.*[睡觉]|先睡了|去睡|睡觉",
        "faces": [74],
        "bocchi_range": (30, 50),
    },
    # 早安
    {
        "pattern": r"早安|早上好|起床|早啊|哦哈哟|おはよう",
        "faces": [74],
        "bocchi_range": (30, 50),
    },
    # 吃饭
    {
        "pattern": r"饿了|干饭|吃饭|[好想].*吃|外卖|夜宵|零食",
        "faces": [],
        "bocchi_range": (30, 50),
    },
    # 贴贴
    {
        "pattern": r"贴贴|抱抱|亲亲|mua|[么啵]一个|好き|suki",
        "faces": [66, 109],
        "bocchi_range": (50, 70),
    },
    # 哭/emo
    {
        "pattern": r"哭|emo|难过|伤心|呜呜|QAQ|TAT|[Tt][Tt]$|[Tt][Oo][Tt]",
        "faces": [],
        "bocchi_range": (0, 20),
    },
    # 大笑
    {
        "pattern": r"哈哈{2,}|笑死|草$|草草|wwww|乐死|[笑哈]{3,}|www{2,}",
        "faces": [176, 182],
        "bocchi_range": (50, 80),
    },
    # 摸鱼
    {
        "pattern": r"摸鱼|摆烂|开摆|不想.*[上班学]|[躺瘫][平着]|懶|摆",
        "faces": [212],
        "bocchi_range": (0, 30),
    },
    # 可爱
    {
        "pattern": r"好可爱|好萌|卡哇伊|kawaii|aw+[w]*$|可愛",
        "faces": [109, 66],
        "bocchi_range": (70, 100),
    },
    # 乐队
    {
        "pattern": r"打鼓|架子鼓|鼓手|乐队|Live|演出|排练|STARRY|音樂|音乐|演奏",
        "faces": [201],
        "bocchi_range": (0, 120),
        "use_all": True,
    },
    # 吃瓜
    {
        "pattern": r"吃瓜|八卦|瓜$|围观|什麼瓜|什么瓜",
        "faces": [263],
        "bocchi_range": (40, 70),
    },
    # 点赞
    {
        "pattern": r"厉害|牛[逼掰]|6{2,}$|太强|NB|nb$|牛逼|牛啊",
        "faces": [201],
        "bocchi_range": (60, 90),
    },
    # 疑惑
    {
        "pattern": r"^\?{2,}$|什么.*[意思鬼]|没懂|不懂|啥意思|什麼.*意思|[？?]{2,}",
        "faces": [0],
        "bocchi_range": (0, 20),
    },
    # 好耶
    {
        "pattern": r"好耶|太好了|nice|Nice|NICE|太棒|開心|YAY|yay",
        "faces": [111, 176],
        "bocchi_range": (60, 90),
    },
    # 生气
    {
        "pattern": r"生气|氣死|怒|不爽|讨厌|討厭|可惡|可恶|哼",
        "faces": [12],
        "bocchi_range": (20, 40),
    },
    # 波奇/孤独摇滚
    {
        "pattern": r"波奇|孤独摇滚|孤獨搖滾|BTR|btr|bocchi|Bocchi|小孤独|後藤|后藤",
        "faces": [109, 111],
        "bocchi_range": (0, 120),
        "use_all": True,
    },
]


class KeywordReply:
    """关键词表情包回复引擎"""

    def __init__(self):
        self.available_bocchi = _list_images(HOST_BOCCHI_DIR)
        self.compiled_rules = []
        for rule in RULES:
            self.compiled_rules.append({
                "regex": re.compile(rule["pattern"], re.IGNORECASE),
                "faces": rule["faces"],
                "bocchi_range": rule.get("bocchi_range", (0, len(self.available_bocchi))),
                "use_all": rule.get("use_all", False),
            })
        logger.info(
            f"KeywordReply: {len(self.compiled_rules)} rules, "
            f"{len(self.available_bocchi)} bocchi stickers"
        )

    def _pick_image(self, rule: dict) -> str | None:
        """从贴纸范围中选一张"""
        if not self.available_bocchi:
            return None

        if rule.get("use_all"):
            return random.choice(self.available_bocchi)

        start, end = rule.get("bocchi_range", (0, len(self.available_bocchi)))
        start = max(0, min(start, len(self.available_bocchi) - 1))
        end = max(start + 1, min(end, len(self.available_bocchi)))

        pool = self.available_bocchi[start:end]
        if not pool:
            pool = self.available_bocchi
        return random.choice(pool)

    def match(self, text: str) -> list[dict] | None:
        """
        检查消息是否匹配关键词规则

        Args:
            text: 消息文本

        Returns:
            OneBot v11 消息段列表，无匹配返回 None
            e.g. [{"type":"face","data":{"id":"74"}},
                  {"type":"image","data":{"file":"file:///app/stickers/bocchi/BTR_042.png"}}]
        """
        if not text:
            return None

        for rule in self.compiled_rules:
            if rule["regex"].search(text):
                segments = []

                # QQ 原生表情
                if rule["faces"]:
                    face_id = random.choice(rule["faces"])
                    segments.append({
                        "type": "face",
                        "data": {"id": str(face_id)},
                    })

                # Bocchi 贴纸
                img_name = self._pick_image(rule)
                if img_name:
                    # NapCat 容器内路径（file:// URI 使用 Docker 路径）
                    img_path = os.path.join(DOCKER_BOCCHI_DIR, img_name)
                    segments.append({
                        "type": "image",
                        "data": {"file": f"file://{img_path}"},
                    })

                if segments:
                    logger.debug(
                        f"KeywordReply matched: {rule['regex'].pattern[:40]}"
                    )
                    return segments

        return None


# 全局单例
_keyword_reply: KeywordReply | None = None


def get_keyword_reply() -> KeywordReply:
    """获取全局 KeywordReply 单例"""
    global _keyword_reply
    if _keyword_reply is None:
        _keyword_reply = KeywordReply()
    return _keyword_reply
