"""
Dialogue Engine — DeepSeek API 集成
两种模式：
  1. 人类回复 — 单个乐队成员回复群友
  2. 小剧场 — 生成四人多轮对话
"""

import asyncio
import json
import logging
import random
import re
from openai import AsyncOpenAI

from config import BandConfig
from persona_manager import PersonaManager, Persona

logger = logging.getLogger(__name__)

# 解析小剧场输出: [虹夏]: xxx
THEATER_LINE_RE = re.compile(r"^\[(虹夏|波奇酱|山田凉|喜多郁代)\]:\s*(.+)$")

# 角色名 -> persona ID 映射
NAME_TO_ID = {
    "虹夏": "nijika",
    "波奇酱": "bocchi",
    "山田凉": "ryo",
    "喜多郁代": "kita",
}


class DialogueEngine:
    """对话生成引擎"""

    def __init__(self, config: BandConfig, persona_mgr: PersonaManager):
        self.config = config
        self.persona_mgr = persona_mgr
        self.client = AsyncOpenAI(
            api_key=config.deepseek_api_key,
            base_url=config.deepseek_base_url,
        )
        self.model = config.ai_model
        logger.info(f"DialogueEngine: using model={self.model}, base_url={config.deepseek_base_url}")

    # ─── 模式1：人类回复 ────────────────────────────────────

    async def generate_human_reply(
        self,
        member_id: str,
        sender_name: str,
        message: str,
        recent_context: list[dict] | None = None,
    ) -> str | None:
        """
        生成一个乐队成员对人类的回复

        Args:
            member_id: 选中的成员 ID (nijika/bocchi/ryo/kita)
            sender_name: 消息发送者的 QQ 昵称
            message: 消息内容
            recent_context: 最近群聊上下文

        Returns:
            回复文本，失败返回 None
        """
        persona = self.persona_mgr.get(member_id)
        system_prompt, user_prompt = self.persona_mgr.build_human_reply_prompt(
            member_id, sender_name, message, recent_context
        )

        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                temperature=0.8,
                max_tokens=400,
                top_p=0.95,
                timeout=30.0,
            )
            reply = response.choices[0].message.content
            if reply:
                reply = reply.strip()
                # 清除可能的前缀标签（有些模型会加 "虹夏:" 前缀）
                reply = re.sub(r"^[［\[]?\w+[］\]]?[：:]\s*", "", reply)
                # 清除引号包裹
                reply = reply.strip('"\'「」')
                logger.debug(
                    f"Human reply [{member_id}]: {reply[:80]}..."
                )
                return reply
        except Exception as e:
            logger.error(f"Human reply generation failed [{member_id}]: {e}")

        return None

    # ─── 模式2：Jam Session 即兴回复 ──────────────────────────

    async def generate_jam_reply(
        self,
        member_id: str,
        members_map: dict[str, str],
        recent_context: list[dict],
        is_first: bool = False,
    ) -> str | None:
        """
        Jam Session 中一个成员的即兴发言

        Args:
            member_id: 发言的成员 ID
            members_map: {id: 中文名} 映射
            recent_context: 完整群聊上下文
            is_first: 是否是本轮 session 第一个发言
        """
        persona = self.persona_mgr.get(member_id)

        system = persona.system_prompt + "\n\n"
        system += "【当前场景】\n"
        system += "你正在纽带乐队的 QQ 粉丝群里。群里正在聊天。\n"
        system += "群里有你的三位队友："
        system += "、".join(name for pid, name in members_map.items() if pid != member_id)
        system += "，还有一些粉丝群友。\n\n"
        system += "【回复要求】\n"
        system += "- 回复要简短自然，1-2 句话，像真正的 QQ 群聊\n"
        system += "- 你可以：接别人的话、吐槽队友、开启新话题、回应粉丝\n"
        system += "- 用你独特的说话风格（参照人格设定）\n"
        system += "- 如果群里沉默了，你可以主动说点什么\n"
        system += "- 不要重复别人刚说过的话\n"
        system += "- 不要写小作文，不要暴露自己是 AI\n"
        system += "- 绝对不要用括号加动作描述，如（笑）、（叹气）、（小声）、(内心)、(*´▽`*) 等\n"
        system += "- 直接说话，不要描述自己的表情或动作\n"
        if is_first:
            system += "- 你是第一个说话的，自然地开启话题\n"

        user = ""
        if recent_context:
            user += "【最近的群聊记录】\n"
            for ctx in recent_context[-10:]:
                user += f"{ctx['name']}: {ctx['text']}\n"
            user += "\n"

        user += f"请以 {persona.name}（{persona.nickname}）的身份，自然地说一句话："

        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
                temperature=0.85,
                max_tokens=200,
                top_p=0.95,
                timeout=25.0,
            )
            reply = response.choices[0].message.content
            if reply:
                reply = reply.strip()
                reply = re.sub(r"^[［\[]?\w+[］\]]?[：:]\s*", "", reply)
                reply = reply.strip('"\'「」')
                logger.debug(f"Jam reply [{member_id}]: {reply[:60]}...")
                return reply
        except Exception as e:
            logger.error(f"Jam reply generation failed [{member_id}]: {e}")

        return None

    # ─── 模式3：小剧场生成 ──────────────────────────────────

    async def generate_chain_reaction(
        self,
        member_id: str,
        reacting_to_member: str,
        recent_context: list[dict],
    ) -> str | None:
        """
        生成一个成员对另一个成员发言的接话/反应

        Args:
            member_id: 接话的成员 ID
            reacting_to_member: 上一个发言的成员中文名
            recent_context: 最近群聊上下文（含上一条）

        Returns:
            回复文本，失败返回 None
        """
        persona = self.persona_mgr.get(member_id)

        system = persona.system_prompt + "\n\n"
        system += "【当前场景】\n"
        system += f"你在纽带乐队的 QQ 粉丝群里。你的队友「{reacting_to_member}」刚在群里说了一句话。\n"
        system += "你自然地接一句——可以是吐槽、赞同、接梗、或者一句简短的反应。\n\n"
        system += "【回复要求】\n"
        system += "- 极其简短，1 句话即可（你在对队友说话，不是对群友）\n"
        system += "- 自然随意，像朋友之间的日常对话\n"
        system += "- 不要长篇大论，不要重复队友刚说的话\n"
        system += "- 绝不暴露自己是 AI"

        user = ""
        if recent_context:
            user += "【最近群聊】\n"
            for ctx in recent_context[-4:]:
                user += f"{ctx['name']}: {ctx['text']}\n"
            user += "\n"

        user += f"请以 {persona.name} 的身份，简短地接一句话："

        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
                temperature=0.85,
                max_tokens=120,
                top_p=0.95,
                timeout=20.0,
            )
            reply = response.choices[0].message.content
            if reply:
                reply = reply.strip()
                reply = re.sub(r"^[［\[]?\w+[］\]]?[：:]\s*", "", reply)
                reply = reply.strip('"\'「」')
                logger.debug(f"Chain reaction [{member_id}]: {reply[:60]}...")
                return reply
        except Exception as e:
            logger.error(f"Chain reaction generation failed [{member_id}]: {e}")

        return None

    # ─── 模式3：小剧场生成 ──────────────────────────────────

    async def generate_theater_script(
        self, scene: str, num_turns: int | None = None
    ) -> list[dict] | None:
        """
        生成一段四人乐队群聊对话

        Args:
            scene: 场景描述
            num_turns: 期望的对话轮数 (None = 随机 4-8)

        Returns:
            [{speaker_id: str, speaker_name: str, text: str}, ...]
            失败返回 None
        """
        all_personas = [self.persona_mgr.get(pid) for pid in self.persona_mgr.get_all_ids()]
        system_prompt, user_prompt = self.persona_mgr.build_theater_prompt(
            scene, all_personas
        )

        if num_turns:
            user_prompt += f"\n\n请写 {num_turns} 轮对话。"

        for attempt in range(3):
            try:
                response = await self.client.chat.completions.create(
                    model=self.model,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                    ],
                    temperature=0.9,
                    max_tokens=1500,
                    top_p=0.95,
                    timeout=60.0,
                )
                raw = response.choices[0].message.content
                if not raw:
                    logger.warning("Theater: empty response")
                    continue

                script = self._parse_theater_output(raw)
                if script and len(script) >= 3:
                    logger.info(
                        f"Theater script generated: {len(script)} turns: "
                        f"{script[0]['speaker_name']} → {script[-1]['speaker_name']}"
                    )
                    return script
                else:
                    logger.warning(
                        f"Theater: parse failed (attempt {attempt+1}/3). "
                        f"Got {len(script)} turns. Raw: {raw[:200]}"
                    )

            except Exception as e:
                logger.error(f"Theater generation failed (attempt {attempt+1}/3): {e}")

            if attempt < 2:
                await asyncio.sleep(2.0)

        logger.error("Theater: all 3 attempts failed")
        return None

    def _parse_theater_output(self, raw: str) -> list[dict]:
        """
        解析小剧场的输出文本

        输入格式：
            [虹夏]: 大家！今天排练辛苦了！
            [波奇酱]: 啊…好…的……
            [山田凉]: 饿了。借我钱。
            [喜多郁代]: 大家今天状态好好！

        返回：
            [{speaker_id, speaker_name, text}, ...]
        """
        result = []
        for line in raw.strip().split("\n"):
            line = line.strip()
            if not line:
                continue

            match = THEATER_LINE_RE.match(line)
            if match:
                name = match.group(1)
                text = match.group(2).strip()
                if name in NAME_TO_ID and text:
                    result.append({
                        "speaker_id": NAME_TO_ID[name],
                        "speaker_name": name,
                        "text": text,
                    })

        return result

    # ─── 备用：简单回退对话 ─────────────────────────────────

    def get_fallback_dialogue(self) -> list[dict]:
        """
        当 DeepSeek API 调用失败时，使用预设的简单对话
        """
        fallbacks = [
            [
                {"speaker_id": "nijika", "speaker_name": "虹夏", "text": "大家～今天排练辛苦了！周末要不要一起去吃点好的？"},
                {"speaker_id": "kita", "speaker_name": "喜多郁代", "text": "好呀好呀！我知道学校附近新开了一家拉面店！"},
                {"speaker_id": "ryo", "speaker_name": "山田凉", "text": "拉面。想吃。虹夏请客。"},
                {"speaker_id": "nijika", "speaker_name": "虹夏", "text": "喂喂凉，上次借你的500日元还没还呢！"},
                {"speaker_id": "bocchi", "speaker_name": "波奇酱", "text": "啊…那个…我、我也想去…（人太多了会不会死掉…）"},
                {"speaker_id": "kita", "speaker_name": "喜多郁代", "text": "波奇前辈当然要来啦！少了谁都不行！"},
            ],
            [
                {"speaker_id": "nijika", "speaker_name": "虹夏", "text": "说起来，下周的Live大家准备得怎么样了？"},
                {"speaker_id": "bocchi", "speaker_name": "波奇酱", "text": "啊…我、我练了…每天练了8小时………（但还是好紧张怎么办）"},
                {"speaker_id": "kita", "speaker_name": "喜多郁代", "text": "波奇前辈好厉害！8小时？！我才练了3小时…要加油了！"},
                {"speaker_id": "ryo", "speaker_name": "山田凉", "text": "我买了新的效果器。声音很好。但是没钱吃饭了。"},
                {"speaker_id": "nijika", "speaker_name": "虹夏", "text": "凉！！你又乱花钱了！算了…今天来我家吃吧…"},
                {"speaker_id": "ryo", "speaker_name": "山田凉", "text": "太好了。虹夏做的饭最好吃。"},
            ],
            [
                {"speaker_id": "kita", "speaker_name": "喜多郁代", "text": "今天天气好好！这种日子最适合练团了！"},
                {"speaker_id": "ryo", "speaker_name": "山田凉", "text": "天气好的日子适合睡觉。"},
                {"speaker_id": "nijika", "speaker_name": "虹夏", "text": "凉你又来了～不过今天真的要好好练习，新歌的编曲还没定呢"},
                {"speaker_id": "bocchi", "speaker_name": "波奇酱", "text": "那、那个…我写了一段新的riff…可、可以给大家听听看吗…？"},
                {"speaker_id": "kita", "speaker_name": "喜多郁代", "text": "哇！！波奇前辈的新曲！超级期待！"},
                {"speaker_id": "nijika", "speaker_name": "虹夏", "text": "当然要听啦！波奇酱的曲子每次都超棒的～"},
            ],
        ]
        return random.choice(fallbacks)
