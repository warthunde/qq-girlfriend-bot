#!/usr/bin/env python3
"""
Band Orchestrator — 纽带乐队四人组 QQ 群聊调度器
=================================================
入口：连接 4 个 NapCat 实例，管理消息分发和小剧场调度。

用法：
    python main.py

环境变量（必需）：
    NIJIKA_QQ, BOCCHI_QQ, RYO_QQ, KITA_QQ  — 四个 QQ 号
    DEEPSEEK_API_KEY                        — DeepSeek API Key
    TARGET_GROUP_ID                         — 目标 QQ 群号

    (完整列表见 .env.example)
"""

import asyncio
import logging
import os
import signal
import sys

from config import load_config, BandConfig
from napcat_client import NapcatClient
from persona_manager import PersonaManager
from dialogue_engine import DialogueEngine
from message_handler import MessageHandler
from theater_scheduler import TheaterScheduler

# ─── 日志配置 ────────────────────────────────────────────────

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
LOG_FORMAT = "%(asctime)s | %(levelname)-7s | %(name)-20s | %(message)s"

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format=LOG_FORMAT,
    datefmt="%Y-%m-%d %H:%M:%S",
)

# 降低第三方库的日志级别
logging.getLogger("aiohttp").setLevel(logging.WARNING)
logging.getLogger("openai").setLevel(logging.WARNING)
logging.getLogger("httpx").setLevel(logging.WARNING)

logger = logging.getLogger("orchestrator")


# ─── 主程序 ──────────────────────────────────────────────────

class BandOrchestrator:
    """纽带乐队调度器主控"""

    def __init__(self):
        self.config: BandConfig | None = None
        self.persona_mgr: PersonaManager | None = None
        self.engine: DialogueEngine | None = None
        self.clients: dict[str, NapcatClient] = {}
        self.handler: MessageHandler | None = None
        self.theater: TheaterScheduler | None = None
        self._shutdown_event = asyncio.Event()

    async def setup(self):
        """初始化所有组件"""
        logger.info("=" * 60)
        logger.info("🎸 Band Orchestrator — 纽带乐队四人组")
        logger.info("=" * 60)

        # 1. 加载配置
        logger.info("Loading configuration...")
        self.config = load_config()

        logger.info(f"Target group: {self.config.target_group_id}")
        logger.info(f"AI Model: {self.config.ai_model}")
        for acc in self.config.accounts:
            logger.info(f"  Bot [{acc.id}]: QQ={acc.qq_number}, "
                        f"WS={acc.ws_url}, HTTP={acc.http_url}")

        # 2. 加载人格
        self.persona_mgr = PersonaManager()

        # 3. 初始化对话引擎
        self.engine = DialogueEngine(self.config, self.persona_mgr)

        # 4. 创建 NapCat 客户端
        for acc in self.config.accounts:
            client = NapcatClient(
                bot_id=acc.id,
                qq_number=acc.qq_number,
                ws_url=acc.ws_url,
                http_url=acc.http_url,
            )
            self.clients[acc.id] = client
            logger.info(f"Created NapcatClient [{acc.id}] -> {acc.ws_url}")

        # 5. 创建消息处理器
        self.handler = MessageHandler(
            self.clients, self.config, self.engine
        )

        # 6. 注册消息回调
        for client in self.clients.values():
            client.on_message(self.handler.handle_message)

        # 7. 创建小剧场调度器
        self.theater = TheaterScheduler(
            self.clients, self.config, self.engine, self.handler
        )

        logger.info("All components initialized ✅")

    async def start(self):
        """启动所有服务"""
        logger.info("Starting services...")

        # 1. 连接所有 NapCat WebSocket
        connect_tasks = [
            client.connect() for client in self.clients.values()
        ]
        await asyncio.gather(*connect_tasks)
        logger.info(f"All {len(self.clients)} WS connections initiated")

        # 2. 等待 WebSocket 全部上线（最多等 2 分钟）
        await self._wait_for_connections(timeout=120)

        # 3. 启动小剧场
        await self.theater.start()

        logger.info("=" * 60)
        logger.info("🎸 Band Orchestrator RUNNING")
        logger.info(f"   群号: {self.config.target_group_id}")
        logger.info(f"   成员: {', '.join(self.persona_mgr.get_all_names().values())}")
        logger.info(f"   小剧场间隔: {self.config.theater_interval_min//60}-"
                    f"{self.config.theater_interval_max//60} 分钟")
        logger.info("=" * 60)

        # 4. 等待 shutdown 信号
        await self._shutdown_event.wait()

    async def shutdown(self):
        """优雅关闭"""
        logger.info("Shutting down...")

        if self.theater:
            await self.theater.stop()

        disconnect_tasks = [
            client.disconnect() for client in self.clients.values()
        ]
        await asyncio.gather(*disconnect_tasks, return_exceptions=True)

        logger.info("Band Orchestrator stopped 👋")

    async def _wait_for_connections(self, timeout: float):
        """等待所有 WS 连接就绪"""
        deadline = asyncio.get_event_loop().time() + timeout

        while asyncio.get_event_loop().time() < deadline:
            connected = sum(1 for c in self.clients.values() if c.connected)
            total = len(self.clients)
            if connected == total:
                logger.info(f"All {total} bots connected ✅")
                return

            logger.info(
                f"Waiting for connections: {connected}/{total} online..."
            )
            await asyncio.sleep(5)

        # 超时报告
        connected = sum(1 for c in self.clients.values() if c.connected)
        total = len(self.clients)
        logger.warning(
            f"Connection timeout: {connected}/{total} bots online. "
            f"Continuing anyway..."
        )


async def main():
    """入口函数"""
    orchestrator = BandOrchestrator()

    # 注册信号处理
    loop = asyncio.get_running_loop()

    def _signal_handler():
        logger.info("Received shutdown signal")
        orchestrator._shutdown_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _signal_handler)
        except NotImplementedError:
            # Windows 不支持 add_signal_handler
            pass

    try:
        await orchestrator.setup()
        await orchestrator.start()
    except Exception as e:
        logger.critical(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)
    finally:
        await orchestrator.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
