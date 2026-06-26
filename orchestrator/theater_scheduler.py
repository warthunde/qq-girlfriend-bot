"""
Theater Scheduler — 小剧场定时调度器
- 随机间隔（30-60 分钟）自动触发
- 从场景池随机选择话题
- 生成 4-8 轮四人对话
- 逐条发送，模拟真人聊天节奏
- 人类活跃时自动延后
"""

import asyncio
import logging
import random
import time

from config import BandConfig
from napcat_client import NapcatClient
from dialogue_engine import DialogueEngine
from message_handler import MessageHandler

logger = logging.getLogger(__name__)

# ─── 场景池 ──────────────────────────────────────────────
# 涵盖乐队日常、生活话题、音乐相关，保持多样性

SCENE_POOL: list[str] = [
    "现在是放学后，纽带乐队刚结束排练。大家在收拾乐器准备回家。",
    "虹夏提议周末一起去逛街买东西，大家在讨论去哪里。",
    "波奇酱今天特别紧张，因为老师让她在班上做自我介绍。大家纷纷鼓励她。",
    "山田凉又在网上买了奇怪的乐器配件，包裹刚送到排练室，大家围观开箱。",
    "喜多郁代兴奋地在群里分享她最近发现的一家超好吃的甜品店。",
    "大家正在紧张地讨论下一场 Live 的演出曲目顺序。",
    "虹夏姐姐在 STARRY 发消息说明天有个临时演出机会，问大家要不要参加。",
    "波奇酱在群里发了自己新录的吉他 demo，求大家给意见（内心极度忐忑）。",
    "山田凉今天一整天没吃东西，在群里发出了「饿」的悲鸣。",
    "喜多郁代被班上的男生告白了，在群里向大家求助该怎么办。",
    "虹夏在整理排练室的储物柜，发现了一年前乐队的合照，开始怀旧。",
    "外边下大雨了，大家都被困在排练室出不去，开始在群里闲聊天。",
    "波奇酱的爸爸说想来看下一场 Live，波奇酱羞耻到想钻垃圾桶。",
    "山田凉突然在群里发了一张杂草的照片问「这个品种好吃吗」。",
    "喜多郁代在练习新歌的高音部分，怎么都唱不上去，向大家请教技巧。",
    "虹夏发现了一个新的音乐节报名通知，问大家要不要一起去试试。",
    "今天排练时波奇酱的吉他solo特别出色，喜多郁代感动到哭了。",
    "山田凉说要把自己的旧贝斯卖掉，结果说出价格后发现根本没人买得起。",
    "大家在群里讨论如果有一天乐队解散了会做什么，气氛有点伤感。",
    "喜多郁代提议给乐队设计一个吉祥物形象，在群里发了一堆草图。",
    "今天是纽带乐队成立一周年的日子，大家在群里回忆过去的一年。",
    "虹夏不小心在群里发了一条本来要私发给姐姐的消息，引发了误会。",
    "波奇酱第一次用手机成功在群里发了一条完整的消息没有结巴（但她打字的时候手在抖）。",
    "山田凉在某二手网站上发现了一把超稀有的贝斯，正在思考要不要卖掉肾。",
    "明天就是期待已久的 Live，大家在群里互相加油打气。",
]


class TheaterScheduler:
    """小剧场调度器"""

    def __init__(
        self,
        clients: dict[str, NapcatClient],
        config: BandConfig,
        engine: DialogueEngine,
        handler: MessageHandler,
    ):
        self.clients = clients
        self.config = config
        self.engine = engine
        self.handler = handler

        self._task: asyncio.Task | None = None
        self._running = False

        # 已使用的场景追踪（避免短期内重复）
        self._recent_scenes: list[str] = []
        self._scene_memory = 5  # 记住最近5个场景

        logger.info(
            f"TheaterScheduler: interval={config.theater_interval_min//60}-"
            f"{config.theater_interval_max//60}min, "
            f"message_gap={config.message_interval_min}-"
            f"{config.message_interval_max}s"
        )

    async def start(self):
        """启动调度器"""
        self._running = True
        self._task = asyncio.create_task(self._loop())
        logger.info("TheaterScheduler started")

    async def stop(self):
        """停止调度器"""
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        logger.info("TheaterScheduler stopped")

    async def _loop(self):
        """主循环"""
        # 首次启动等待 30 秒，让所有 bot 先连上
        await asyncio.sleep(30)
        logger.info("TheaterScheduler entering main loop")

        while self._running:
            try:
                # 随机间隔
                interval = random.uniform(
                    self.config.theater_interval_min,
                    self.config.theater_interval_max,
                )
                logger.info(f"Next theater in {interval/60:.0f} minutes")
                await asyncio.sleep(interval)

                if not self._running:
                    break

                # 检查是否有活跃的 jam session
                if self.handler.is_session_active:
                    logger.info("Jam session active, deferring theater by 5 minutes")
                    await asyncio.sleep(300)
                    continue

                # 检查人类活动
                time_since_human = time.time() - self.handler.last_human_activity
                if time_since_human < self.config.human_active_window:
                    logger.info(
                        f"Human active {time_since_human:.0f}s ago, "
                        f"deferring theater by 2 minutes"
                    )
                    await asyncio.sleep(120)
                    continue

                # 执行小剧场
                await self._run_theater()

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Theater loop error: {e}", exc_info=True)
                await asyncio.sleep(60)

    async def _run_theater(self):
        """执行一次小剧场"""
        logger.info("=" * 40)
        logger.info("🎭 BAND THEATER START")
        logger.info("=" * 40)

        self.handler.theater_active = True

        try:
            # 1. 选场景
            scene = self._pick_scene()
            logger.info(f"Scene: {scene}")

            # 2. 选轮数
            num_turns = random.randint(
                self.config.theater_min_turns,
                self.config.theater_max_turns,
            )
            logger.info(f"Target turns: {num_turns}")

            # 3. 生成对话
            script = await self.engine.generate_theater_script(scene, num_turns)
            if not script:
                logger.warning("Theater generation failed, using fallback")
                script = self.engine.get_fallback_dialogue()

            logger.info(f"Theater script: {len(script)} turns")

            # 4. 逐条发送
            for i, turn in enumerate(script):
                if not self._running:
                    break

                speaker_id = turn["speaker_id"]
                text = turn["text"]

                client = self.clients.get(speaker_id)
                if not client or not client.connected:
                    logger.warning(
                        f"Skipping turn {i+1}: [{speaker_id}] offline"
                    )
                    continue

                # 发送
                logger.info(
                    f"  [{speaker_id}] {turn['speaker_name']}: {text[:80]}"
                )
                await client.send_group_text(self.config.target_group_id, text)

                # 更新上下文（让 message_handler 知道乐队成员说了什么）
                self.handler._add_context(turn["speaker_name"], text)

                # 间隔（最后一条不用等）
                if i < len(script) - 1:
                    gap = random.uniform(
                        self.config.message_interval_min,
                        self.config.message_interval_max,
                    )
                    await asyncio.sleep(gap)

            logger.info("🎭 BAND THEATER END")

        except Exception as e:
            logger.error(f"Theater execution error: {e}", exc_info=True)
        finally:
            self.handler.theater_active = False

    def _pick_scene(self) -> str:
        """选择一个场景，尽量避免短期内重复"""
        available = [
            s for s in SCENE_POOL
            if s not in self._recent_scenes
        ]
        if not available:
            available = SCENE_POOL[:]  # 全部可用

        scene = random.choice(available)

        # 更新最近场景记录
        self._recent_scenes.append(scene)
        if len(self._recent_scenes) > self._scene_memory:
            self._recent_scenes.pop(0)

        return scene
