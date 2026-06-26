"""
Band Orchestrator — 配置加载
从环境变量读取所有配置
"""

import os
from dataclasses import dataclass, field


@dataclass
class BotAccount:
    """单个乐队成员的 QQ 机器人配置"""
    id: str              # "nijika", "bocchi", "ryo", "kita"
    name: str            # 中文名：虹夏、波奇酱、山田凉、喜多郁代
    qq_number: str       # QQ 号
    ws_url: str          # WebSocket 地址 (容器内)
    http_url: str        # HTTP API 地址 (容器内)


@dataclass
class BandConfig:
    """乐队全局配置"""
    accounts: list[BotAccount]

    # DeepSeek API
    deepseek_api_key: str
    deepseek_base_url: str
    ai_model: str

    # 目标群
    target_group_id: int

    # 小剧场间隔 (秒)
    theater_interval_min: int
    theater_interval_max: int

    # 小剧场消息间隔 (秒)
    message_interval_min: float
    message_interval_max: float

    # 人类回复延迟 (秒)
    human_reply_delay_min: float
    human_reply_delay_max: float

    # 人类回复冷却 (秒，防止多个 bot 同时回)
    human_reply_cooldown: float

    # 人类活跃检测窗口 (秒) — 如果最近N秒有人发言，延后小剧场
    human_active_window: float

    # 去重缓存 TTL (秒)
    dedup_ttl: int

    # 小剧场最大轮数
    theater_min_turns: int
    theater_max_turns: int


def _require_env(key: str) -> str:
    val = os.getenv(key, "").strip()
    if not val:
        raise ValueError(f"缺少必要的环境变量: {key}")
    return val


def _require_int(key: str) -> int:
    return int(_require_env(key))


def load_config() -> BandConfig:
    """从环境变量加载完整配置"""

    # --- 四个 QQ 号 ---
    nijika_qq = _require_env("NIJIKA_QQ")
    bocchi_qq = _require_env("BOCCHI_QQ")
    ryo_qq   = _require_env("RYO_QQ")
    kita_qq  = _require_env("KITA_QQ")

    # --- DeepSeek ---
    api_key  = _require_env("DEEPSEEK_API_KEY")
    base_url = os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com").strip()
    model    = os.getenv("AI_MODEL", "deepseek-chat").strip()

    # --- 目标群 ---
    group_id = _require_int("TARGET_GROUP_ID")

    # 连接地址：默认用 Docker 容器网络名，可通过环境变量覆盖（宿主机运行时用 localhost）
    accounts = [
        BotAccount(
            id="nijika",
            name="虹夏",
            qq_number=nijika_qq,
            ws_url=os.getenv("NIJIKA_WS_URL", "ws://napcat_nijika:3001"),
            http_url=os.getenv("NIJIKA_HTTP_URL", "http://napcat_nijika:3000"),
        ),
        BotAccount(
            id="bocchi",
            name="波奇酱",
            qq_number=bocchi_qq,
            ws_url=os.getenv("BOCCHI_WS_URL", "ws://napcat_bocchi:3001"),
            http_url=os.getenv("BOCCHI_HTTP_URL", "http://napcat_bocchi:3000"),
        ),
        BotAccount(
            id="ryo",
            name="山田凉",
            qq_number=ryo_qq,
            ws_url=os.getenv("RYO_WS_URL", "ws://napcat_ryo:3001"),
            http_url=os.getenv("RYO_HTTP_URL", "http://napcat_ryo:3000"),
        ),
        BotAccount(
            id="kita",
            name="喜多郁代",
            qq_number=kita_qq,
            ws_url=os.getenv("KITA_WS_URL", "ws://napcat_kita:3001"),
            http_url=os.getenv("KITA_HTTP_URL", "http://napcat_kita:3000"),
        ),
    ]

    return BandConfig(
        accounts=accounts,
        deepseek_api_key=api_key,
        deepseek_base_url=base_url,
        ai_model=model,
        target_group_id=group_id,

        theater_interval_min=int(os.getenv("THEATER_INTERVAL_MIN", "30")) * 60,
        theater_interval_max=int(os.getenv("THEATER_INTERVAL_MAX", "60")) * 60,

        message_interval_min=float(os.getenv("MESSAGE_INTERVAL_MIN", "5")),
        message_interval_max=float(os.getenv("MESSAGE_INTERVAL_MAX", "20")),

        human_reply_delay_min=float(os.getenv("HUMAN_REPLY_DELAY_MIN", "3")),
        human_reply_delay_max=float(os.getenv("HUMAN_REPLY_DELAY_MAX", "8")),

        human_reply_cooldown=float(os.getenv("HUMAN_REPLY_COOLDOWN", "10")),
        human_active_window=float(os.getenv("HUMAN_ACTIVE_WINDOW", "120")),

        dedup_ttl=int(os.getenv("DEDUP_TTL", "30")),
        theater_min_turns=int(os.getenv("THEATER_MIN_TURNS", "4")),
        theater_max_turns=int(os.getenv("THEATER_MAX_TURNS", "8")),
    )
