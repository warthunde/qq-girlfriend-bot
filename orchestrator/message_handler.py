"""
Message Handler — 即兴 Jam Session 模式

触发：任意人在群里发消息（人类或 Bot 均可）
行为：Bot 们自然接话聊天，每人根据完整上下文即兴回复
限制：每轮会话 20-50 条消息，结束后冷却 15-30 分钟
人类消息无缝融入，Bot 也会回应人类
"""

import asyncio
import logging
import random
import time
from collections import deque

from config import BandConfig
from napcat_client import NapcatClient
from dialogue_engine import DialogueEngine
from keyword_reply import get_keyword_reply

logger = logging.getLogger(__name__)


class MessageDeduplicator:
    def __init__(self, ttl_seconds: int = 30):
        self.ttl = ttl_seconds
        self._seen: dict[str, float] = {}

    def is_duplicate(self, key: str) -> bool:
        now = time.time()
        self._seen = {k: v for k, v in self._seen.items() if now - v < self.ttl}
        if key in self._seen:
            return True
        self._seen[key] = now
        return False


class MessageHandler:

    def __init__(
        self,
        clients: dict[str, NapcatClient],
        config: BandConfig,
        engine: DialogueEngine,
    ):
        self.clients = clients
        self.config = config
        self.engine = engine

        # 账户映射
        self._band_qq_to_id: dict[str, str] = {}
        for acc in config.accounts:
            self._band_qq_to_id[acc.qq_number] = acc.id
        self._accounts_map: dict[str, str] = {acc.id: acc.name for acc in config.accounts}

        # 去重
        self._dedup = MessageDeduplicator(config.dedup_ttl)

        # 群聊上下文
        self._recent_messages: list[dict] = []
        self._max_context = 50

        # Jam Session 状态
        self._session_active = False
        self._session_task: asyncio.Task | None = None
        self._session_msg_count = 0
        self._session_max = 0
        self._session_cooldown_until: float = 0
        self._last_speaker: str | None = None  # 上一轮发言的 bot id

        # 小剧场（保留，但 jam session 期间不触发）
        self._theater_active = False
        self._last_human_activity: float = 0

        # 关键词表情
        self._keyword_reply = get_keyword_reply()

    @property
    def theater_active(self) -> bool:
        return self._theater_active

    @theater_active.setter
    def theater_active(self, value: bool):
        self._theater_active = value

    @property
    def last_human_activity(self) -> float:
        return self._last_human_activity

    @property
    def is_session_active(self) -> bool:
        return self._session_active

    # ─── 消息入口 ────────────────────────────────────────────

    async def handle_message(self, bot_id: str, event: dict):
        try:
            group_id = event.get("group_id", 0)
            message_id = event.get("message_id", 0)
            sender = event.get("sender", {})
            sender_qq = str(sender.get("user_id", ""))
            sender_name = sender.get("card") or sender.get("nickname", "未知")
            raw_text = str(event.get("raw_message", ""))

            # 过滤非目标群
            if group_id != self.config.target_group_id:
                return

            # 去重：用 (group_id, message_id)
            # 注意：不同 NapCat 可能给同一消息不同的 message_id
            # 所以额外用 (group_id, sender_qq, raw_text[:30]) 做二次去重
            key1 = f"{group_id}:{message_id}"
            key2 = f"{group_id}:{sender_qq}:{raw_text[:40]}"
            if self._dedup.is_duplicate(key1) or self._dedup.is_duplicate(key2):
                return

            # 记录到上下文
            is_band = sender_qq in self._band_qq_to_id
            # Clean CQ codes from context
            clean_text = self._clean_cq(raw_text)
            self._add_context(sender_name, clean_text)

            if not is_band:
                logger.info(f"[MSG] HUMAN {sender_name}({sender_qq}): {raw_text[:100]}")
                self._last_human_activity = time.time()
            else:
                logger.debug(f"[MSG] BAND[{self._band_qq_to_id[sender_qq]}] {sender_name}: {raw_text[:60]}")

            # 如果 session 已激活，消息被 session 循环感知（通过上下文）
            if self._session_active:
                return  # session 循环会自动看到新消息并决定是否回应

            # 如果 session 未激活且冷却已过 → 启动新 session
            if time.time() > self._session_cooldown_until:
                self._session_task = asyncio.create_task(self._run_jam_session())

        except Exception as e:
            logger.error(f"handle_message error [{bot_id}]: {e}", exc_info=True)

    # ─── Jam Session 核心 ─────────────────────────────────────

    async def _run_jam_session(self):
        """即兴 Jam Session：Bot 们围绕群聊内容自然接话"""
        self._session_active = True
        self._session_msg_count = 0
        self._session_max = random.randint(30, 50)
        self._last_speaker = None

        logger.info(f"🎵 JAM SESSION START (budget: {self._session_max} msgs)")

        try:
            # 先等 1-3 秒，收集上下文
            await asyncio.sleep(random.uniform(1, 3))

            while self._session_msg_count < self._session_max:
                # 选下一个发言者：优先选最近没说过话的
                speaker = self._pick_next_speaker()

                # 生成回复
                reply = await self.engine.generate_jam_reply(
                    member_id=speaker,
                    members_map=self._accounts_map,
                    recent_context=list(self._recent_messages),
                    is_first=(self._session_msg_count == 0),
                )

                if not reply:
                    # 生成失败，换个人试试
                    continue

                # 延迟发送
                delay = random.uniform(2, 6)
                await asyncio.sleep(delay)

                # 发送
                client = self.clients[speaker]
                ok = await client.send_group_text(self.config.target_group_id, reply)
                if not ok:
                    continue

                self._add_context(self._accounts_map[speaker], reply)
                self._session_msg_count += 1
                self._last_speaker = speaker

                logger.info(
                    f"  JAM [{self._session_msg_count}/{self._session_max}] "
                    f"{self._accounts_map[speaker]}: {reply[:60]}"
                )

                # 检查是否应该自然停止
                if self._should_end_early():
                    logger.info("JAM: natural ending (conversation fading)")
                    break

            logger.info(f"🎵 JAM SESSION END ({self._session_msg_count} msgs)")

        except asyncio.CancelledError:
            logger.info("JAM: cancelled")
        except Exception as e:
            logger.error(f"JAM session error: {e}", exc_info=True)
        finally:
            self._session_active = False
            # 冷却
            cooldown = random.randint(15, 30) * 60
            self._session_cooldown_until = time.time() + cooldown
            logger.info(f"JAM cooldown: {cooldown//60} minutes")

    def _pick_next_speaker(self) -> str:
        """选下一个发言者，尽量避免同一人连续说话太多次"""
        candidates = [mid for mid, c in self.clients.items() if c.connected]
        if not candidates:
            return "nijika"

        # 排除刚说过的人（除非只有一个人）
        if self._last_speaker and len(candidates) > 1:
            filtered = [m for m in candidates if m != self._last_speaker]
            if filtered:
                candidates = filtered

        # 加权随机：优先选 bot，最近没说过话的权重大
        return random.choice(candidates)

    def _should_end_early(self) -> bool:
        """自然结束判断"""
        if self._session_msg_count < 10:
            return False  # 至少聊 10 条
        # 15 条后 5% 概率自然结束
        if self._session_msg_count < 15:
            return random.random() < 0.03
        return random.random() < 0.06

    @staticmethod
    def _clean_cq(text: str) -> str:
        """清理 CQ 码（@、图片、表情等），保留纯文本"""
        import re as _re
        return _re.sub(r'\[CQ:[^\]]+\]', '', text).strip()

    # ─── 上下文管理 ──────────────────────────────────────────

    def _add_context(self, name: str, text: str):
        self._recent_messages.append({"name": name, "text": text})
        if len(self._recent_messages) > self._max_context:
            self._recent_messages = self._recent_messages[-self._max_context:]
