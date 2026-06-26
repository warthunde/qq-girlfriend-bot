"""
Persona Manager — 加载和管理四个乐队成员的人格设定
从 personas/ 目录读取 YAML 文件，提供 prompt 构建接口
"""

import os
import yaml
import logging

logger = logging.getLogger(__name__)

PERSONAS_DIR = os.path.join(os.path.dirname(__file__), "personas")


class Persona:
    """单个人格"""

    def __init__(self, data: dict):
        self.id: str = data["id"]
        self.name: str = data["name"]
        self.nickname: str = data["nickname"]
        self.age: int = data["age"]
        self.role: str = data["role"]
        self.emoji: str = data.get("emoji", "")
        self.system_prompt: str = data["system_prompt"]
        self.speaking_traits: list[str] = data.get("speaking_traits", [])
        self.catchphrases: list[str] = data.get("catchphrases", [])

    def __repr__(self) -> str:
        return f"Persona({self.id}: {self.name})"


class PersonaManager:
    """管理所有乐队成员的人格"""

    def __init__(self, personas_dir: str = PERSONAS_DIR):
        self.personas: dict[str, Persona] = {}
        self._load_all(personas_dir)
        logger.info(f"PersonaManager: loaded {len(self.personas)} personas")

    def _load_all(self, directory: str):
        """加载目录下所有 YAML 文件"""
        if not os.path.isdir(directory):
            raise FileNotFoundError(f"Personas directory not found: {directory}")

        for filename in sorted(os.listdir(directory)):
            if not filename.endswith((".yaml", ".yml")):
                continue
            filepath = os.path.join(directory, filename)
            try:
                with open(filepath, "r", encoding="utf-8") as f:
                    data = yaml.safe_load(f)
                persona = Persona(data)
                self.personas[persona.id] = persona
                logger.debug(f"  Loaded persona: {persona.id} ({persona.name})")
            except Exception as e:
                logger.error(f"Failed to load persona from {filepath}: {e}")

    def get(self, persona_id: str) -> Persona:
        """获取指定人格"""
        if persona_id not in self.personas:
            raise KeyError(f"Unknown persona: {persona_id}")
        return self.personas[persona_id]

    def get_all_ids(self) -> list[str]:
        """获取所有人格 ID"""
        return list(self.personas.keys())

    def get_all_names(self) -> dict[str, str]:
        """获取所有 ID -> 中文名 映射"""
        return {p.id: p.name for p in self.personas.values()}

    def build_human_reply_prompt(
        self, persona_id: str, sender_name: str,
        message: str, recent_context: list[dict] | None = None
    ) -> tuple[str, str]:
        """
        构建「人类回复」模式的 prompt

        Args:
            persona_id: 选中的成员 ID
            sender_name: 发消息的人的 QQ 昵称
            message: 人类发的消息内容
            recent_context: 最近的群聊上下文 [{name, text}, ...]

        Returns:
            (system_prompt, user_prompt) 元组
        """
        persona = self.get(persona_id)

        system = persona.system_prompt + "\n\n"
        system += "【当前场景】\n"
        system += f"你正在纽带乐队的 QQ 粉丝群里聊天。一位群友「{sender_name}」发了一条消息。\n"
        system += "请用你的角色身份自然地回复他/她。\n\n"
        system += "【回复要求】\n"
        system += "- 回复要简短自然，1-3句话即可，不要写小作文\n"
        system += "- 用你在群聊里的语气说话，不要像在写小说\n"
        system += "- 绝不暴露自己是 AI 或机器人\n"
        system += "- 不要用括号描述动作或表情，如（笑）、（叹气）、(内心)等\n"
        system += "- 直接说话，不写舞台指导"

        user = ""
        if recent_context:
            user += "【最近的群聊记录】\n"
            for ctx in recent_context[-8:]:  # 最近8条
                user += f"{ctx['name']}: {ctx['text']}\n"
            user += "\n"

        user += f"【{sender_name} 刚才说】\n"
        user += f"{message}\n\n"
        user += f"请以 {persona.name}（{persona.nickname}）的身份，用你的说话风格回复："

        return system, user

    def build_theater_prompt(
        self, scene: str, all_personas: list[Persona]
    ) -> tuple[str, str]:
        """
        构建「小剧场」模式的 prompt

        Args:
            scene: 场景描述
            all_personas: 所有参与的人格列表

        Returns:
            (system_prompt, user_prompt) 元组
        """
        # 构建角色描述
        char_descs = []
        for p in all_personas:
            traits = "、".join(p.speaking_traits[:3])
            char_descs.append(
                f"- {p.name}（{p.nickname}）：{p.role}。{traits}。\n"
                f"  代表台词：{p.catchphrases[0] if p.catchphrases else ''}"
            )

        system = (
            "你是《孤独摇滚》（Bocchi the Rock!）的动画编剧。\n"
            "你需要写一段纽带乐队（結束バンド）四位成员在 QQ 群聊里的自然对话。\n\n"
            "【角色设定】\n"
            f"{''.join(char_descs)}\n\n"
            "【写作规则】\n"
            "- 写 4-8 轮对话（每轮一个人说话）\n"
            "- 每条消息必须简短，1-3 句话，像真正的 QQ 群聊\n"
            "- 每个角色必须用自己独特的语气说话：\n"
            "  * 虹夏：元气积极，偶尔吐槽\n"
            "  * 波奇酱：结巴、慌张、自我贬低，用省略号\n"
            "  * 山田凉：话少冷静，突然说怪话，提到钱/食物/设备\n"
            "  * 喜多郁代：开朗活泼，用敬语，充满能量\n"
            "- 对话要有自然的起承转合：有人发起话题 → 各自回应 → 自然结束\n"
            "- 不要让一个角色霸屏，要轮流发言\n"
            "- 绝对不要写叙述性文字或舞台指导\n"
            "- 绝对不要写「（笑）」「（沉默）」等括号描述\n\n"
            "【输出格式 — 必须严格遵守】\n"
            "每条消息一行，格式为：[角色名]: 内容\n"
            "角色名只能是以下四个之一：虹夏、波奇酱、山田凉、喜多郁代\n\n"
            "示例格式：\n"
            "[虹夏]: 大家！今天排练辛苦了！明天也要加油哦！\n"
            "[波奇酱]: 啊…好…好的…今天差点又昏过去了…\n"
            "[山田凉]: 饿了。虹夏，请我吃拉面。\n"
            "[喜多郁代]: 凉前辈又来了www 不过我今天也超开心！和大家一起演奏最棒了！\n\n"
            "绝对不要用括号加任何描述。现在开始写对话，只输出对话。"
        )

        user = f"【场景】\n{scene}\n\n请写一段纽带乐队四人的群聊对话："

        return system, user
