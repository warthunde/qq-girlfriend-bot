"""
NapCat Client — 单个 QQ 机器人的 OneBot v11 客户端
- WebSocket 连接接收事件
- HTTP POST 发送群消息
- 自动重连
"""

import asyncio
import json
import logging
import time
from typing import Callable, Awaitable

import aiohttp

logger = logging.getLogger(__name__)

# OneBot v11 消息段类型
MessageSegment = dict  # {"type": "text", "data": {"text": "..."}}


class NapcatClient:
    """管理单个 NapCat 实例的 WebSocket + HTTP 连接"""

    def __init__(self, bot_id: str, qq_number: str, ws_url: str, http_url: str):
        self.bot_id = bot_id
        self.qq_number = qq_number
        self.ws_url = ws_url
        self.http_url = http_url

        self._ws: aiohttp.ClientWebSocketResponse | None = None
        self._session: aiohttp.ClientSession | None = None
        self._connected = False
        self._running = False

        # 消息回调: async func(bot_id: str, event: dict)
        self._message_callback: Callable[[str, dict], Awaitable[None]] | None = None

        # 重连参数
        self._reconnect_delay = 1.0
        self._max_reconnect_delay = 60.0
        self._reconnect_task: asyncio.Task | None = None

    @property
    def connected(self) -> bool:
        return self._connected

    def on_message(self, callback: Callable[[str, dict], Awaitable[None]]):
        """注册消息事件回调"""
        self._message_callback = callback

    async def connect(self):
        """建立 WebSocket 连接，并启动自动重连"""
        self._running = True
        self._session = aiohttp.ClientSession()
        self._reconnect_task = asyncio.create_task(self._reconnect_loop())

    async def disconnect(self):
        """断开连接"""
        self._running = False
        if self._reconnect_task:
            self._reconnect_task.cancel()
            self._reconnect_task = None
        await self._close_ws()
        if self._session:
            await self._session.close()
            self._session = None
        logger.info(f"[{self.bot_id}] Disconnected")

    async def _reconnect_loop(self):
        """自动重连循环"""
        while self._running:
            try:
                await self._connect_ws()
                self._reconnect_delay = 1.0  # 连接成功后重置

                # 开始接收消息
                await self._ws_listen()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.warning(
                    f"[{self.bot_id}] WS disconnected: {e}. "
                    f"Reconnecting in {self._reconnect_delay}s..."
                )

            if not self._running:
                break

            await asyncio.sleep(self._reconnect_delay)
            self._reconnect_delay = min(
                self._reconnect_delay * 2, self._max_reconnect_delay
            )

    async def _connect_ws(self):
        """建立单次 WebSocket 连接"""
        logger.info(f"[{self.bot_id}] Connecting to {self.ws_url}...")
        self._ws = await self._session.ws_connect(
            self.ws_url,
            heartbeat=30.0,
            timeout=30.0,
        )
        self._connected = True
        logger.info(f"[{self.bot_id}] ✅ WebSocket connected")

    async def _close_ws(self):
        self._connected = False
        if self._ws and not self._ws.closed:
            await self._ws.close()
        self._ws = None

    async def _ws_listen(self):
        """WebSocket 消息接收循环"""
        if not self._ws:
            return

        async for msg in self._ws:
            if not self._running:
                break

            if msg.type == aiohttp.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    await self._handle_event(data)
                except json.JSONDecodeError:
                    logger.debug(f"[{self.bot_id}] Non-JSON WS message: {msg.data[:200]}")
                except Exception as e:
                    logger.error(f"[{self.bot_id}] Error handling WS event: {e}")

            elif msg.type == aiohttp.WSMsgType.CLOSED:
                logger.info(f"[{self.bot_id}] WS closed by server")
                break
            elif msg.type == aiohttp.WSMsgType.ERROR:
                logger.error(f"[{self.bot_id}] WS error")
                break

    async def _handle_event(self, data: dict):
        """处理收到的 OneBot v11 事件"""
        post_type = data.get("post_type", "")
        message_type = data.get("message_type", "")
        sub_type = data.get("sub_type", "")
        group_id = data.get("group_id", 0)
        sender = data.get("sender", {})
        sender_qq = str(sender.get("user_id", ""))

        # DEBUG ONLY: 记录所有非心跳事件
        if data.get("meta_event_type") != "heartbeat":
            logger.debug(
                f"[{self.bot_id}] WS event: post_type={post_type}, "
                f"message_type={message_type}, group_id={group_id}, sender={sender_qq}, "
                f"raw_text={str(data.get('raw_message', ''))[:60]}"
            )

        # 处理消息事件
        if post_type in ("message", "message_sent"):
            if message_type == "group":
                # 忽略 Bot 自己发出的消息的 echo
                # (NapCat 会把所有 bot 自己发的消息也回传给 WS)
                if sender_qq == self.qq_number:
                    logger.debug(f"[{self.bot_id}] Ignoring self-sent echo (QQ={sender_qq})")
                    return
                if self._message_callback:
                    await self._message_callback(self.bot_id, data)

        elif post_type == "meta_event":
            meta_type = data.get("meta_event_type", "")
            if meta_type == "lifecycle":
                logger.info(f"[{self.bot_id}] Lifecycle: {data.get('sub_type', '')}")

        elif post_type == "notice":
            logger.info(f"[{self.bot_id}] Notice: {data.get('notice_type', '')}")

    # ─── HTTP API ────────────────────────────────────────────

    async def send_group_msg(
        self, group_id: int, message: list[MessageSegment]
    ) -> dict | None:
        """
        通过 HTTP API 发送群消息

        Args:
            group_id: QQ 群号
            message: OneBot v11 消息段列表
                     e.g. [{"type":"text","data":{"text":"hello"}}]

        Returns:
            API 响应 JSON，失败返回 None
        """
        url = f"{self.http_url}/send_group_msg"
        payload = {
            "group_id": group_id,
            "message": message,
        }

        for attempt in range(1):  # 不重试，1 次失败就返回
            try:
                async with self._session.post(
                    url, json=payload, timeout=aiohttp.ClientTimeout(total=10)
                ) as resp:
                    data = await resp.json()
                    if data.get("status") == "ok":
                        logger.debug(
                            f"[{self.bot_id}] Sent group msg: "
                            f"{json.dumps(message, ensure_ascii=False)[:80]}"
                        )
                        return data
                    else:
                        logger.warning(
                            f"[{self.bot_id}] send_group_msg failed: {data}"
                        )
            except asyncio.TimeoutError:
                logger.warning(
                    f"[{self.bot_id}] send_group_msg timeout (attempt {attempt+1}/3)"
                )
            except Exception as e:
                logger.error(
                    f"[{self.bot_id}] send_group_msg error (attempt {attempt+1}/3): {e}"
                )

            if attempt < 2:
                await asyncio.sleep(1.0 * (attempt + 1))

        logger.error(f"[{self.bot_id}] send_group_msg failed after 3 attempts")
        return None

    async def send_group_text(
        self, group_id: int, text: str
    ) -> dict | None:
        """发送纯文本群消息的便捷方法"""
        return await self.send_group_msg(group_id, [
            {"type": "text", "data": {"text": text}}
        ])

    async def get_login_info(self) -> dict | None:
        """获取登录信息（用于测试连接）"""
        url = f"{self.http_url}/get_login_info"
        try:
            async with self._session.post(
                url, json={}, timeout=aiohttp.ClientTimeout(total=5)
            ) as resp:
                return await resp.json()
        except Exception:
            return None
