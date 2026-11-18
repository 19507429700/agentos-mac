"""开发模式：主人在手机飞书发「开发：…」，在这台 Mac 上用他本人的 Claude Code、最高权限干活。

和平时的助理不一样：
- 平时的助理在 agentos 账号里，只能查资料、出文件；开发模式以你本人账号运行，跳过所有权限确认
  （--dangerously-skip-permissions），能改代码、执行任何命令、读写你能读写的所有文件。
- 能接着电脑上的 Claude 会话干活（包括桌面版里开的），也能新开。
只认主人本人的私聊消息（桥接服务已经保证）。配置在 ~/.agentos/bridge.env：
  DEV_MODE=0         关掉开发模式（默认开）
  DEV_DIR=~/AgentOS  新任务在哪个文件夹里开始
  DEV_CLAUDE=~/.local/bin/claude
  DEV_PROXY=http://127.0.0.1:12450   国内连 Claude 要走的代理（只给开发模式用）
说法：
  开发：会话             列出电脑上最近的 Claude 会话
  开发：接着 2 把剩下的做完  接着列表里第 2 个会话干活（不写后面的话就是「继续」）
  开发：新任务 ……         新开一个会话
  开发：……               接着这个飞书对话上一次的开发会话（没有就新开）
  开发：结束              忘掉当前开发会话，下次「开发：」就新开
"""

from __future__ import annotations

import json
import re
import time
from datetime import datetime
from pathlib import Path

PREFIX_RE = re.compile(r"^\s*(?:开发|/dev)\s*[：:\s]\s*", re.I)
LIST_WORDS = {"会话", "最近", "列表", "最近的会话", "会话列表"}
END_WORDS = {"结束", "退出", "结束开发"}
RESUME_RE = re.compile(r"^(?:接着|继续)\s*第?\s*(\d{1,2})\s*个?\s*[，,。:：]?\s*(.*)$", re.S)
NEW_RE = re.compile(r"^(?:新任务|新开|新会话)\s*[，,。:：]?\s*(.*)$", re.S)
DEFAULT_GO = "继续把之前没做完的做完。先用一两句话说上次做到哪、还差什么，再接着做。"
LIST_LIMIT = 8
OUTBOX_NAME = "AgentOS-发给手机"


def parse(text: str) -> tuple[str, str, int] | None:
    """不是开发模式返回 None；否则 (动作, 要做的事, 第几个会话)。动作：list / end / resume / new / run。"""
    m = PREFIX_RE.match(text or "")
    if not m:
        return None
    rest = text[m.end():].strip()
    if rest in LIST_WORDS or not rest:
        return ("list", "", 0)
    if rest in END_WORDS:
        return ("end", "", 0)
    r = RESUME_RE.match(rest)
    if r:
        return ("resume", r.group(2).strip() or DEFAULT_GO, int(r.group(1)))
    n = NEW_RE.match(rest)
    if n:
        return ("new", n.group(1).strip(), 0)
    return ("run", rest, 0)


# ---------- 电脑上的 Claude 会话 ----------

def _tail(path: Path, size: int = 256 * 1024) -> str:
    with open(path, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - size))
        return f.read().decode("utf-8", "replace")


def session_info(path: Path) -> dict:
    """从会话文件里取：标题（桌面版起的名字，或第一句话）、工作文件夹。"""
    title, cwd, first = "", "", ""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f):
                if i > 200 or (cwd and first):
                    break
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                cwd = cwd or d.get("cwd") or ""
                if not first and d.get("type") == "user":
                    c = (d.get("message") or {}).get("content")
                    if isinstance(c, list):
                        c = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
                    c = re.sub(r"<[^>]+>.*?</[^>]+>", "", str(c or ""), flags=re.S).strip()
                    if c and not c.startswith("Caveat"):
                        first = c
        for line in reversed(_tail(path).splitlines()):
            if '"custom-title"' in line or '"summary"' in line:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                title = d.get("customTitle") or d.get("summary") or ""
                if title:
                    break
    except OSError:
        pass
    title = (title or first or "（没有标题）").replace("\n", " ").strip()
    return {"id": path.stem, "title": title[:40], "cwd": cwd, "mtime": path.stat().st_mtime}


def recent_sessions(projects: Path, limit: int = LIST_LIMIT) -> list[dict]:
    files = [p for p in projects.glob("*/*.jsonl") if re.fullmatch(r"[0-9a-f-]{36}", p.stem)]
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return [session_info(p) for p in files[:limit]]


def find_session(projects: Path, sid: str) -> dict | None:
    for p in projects.glob(f"*/{sid}.jsonl"):
        return session_info(p)
    return None


def list_text(sessions: list[dict], now: float | None = None) -> str:
    if not sessions:
        return "电脑上还没有 Claude 会话。直接发「开发：要做的事」就会新开一个。"
    now = now or time.time()
    lines = ["**电脑上最近的 Claude 会话**"]
    for i, s in enumerate(sessions, 1):
        ago = now - s["mtime"]
        when = "刚刚还在用" if ago < 120 else datetime.fromtimestamp(s["mtime"]).strftime("%m-%d %H:%M")
        folder = Path(s["cwd"]).name if s["cwd"] else "?"
        lines.append(f"{i}. {s['title']}（{folder}，{when}）")
    lines += ["", "发「开发：接着 2」接着第 2 个干活，后面可以加要做的事；发「开发：新任务 ……」新开。",
              "标着「刚刚还在用」的，电脑前可能正开着，同时操作会互相打架。"]
    return "\n".join(lines)


# ---------- 运行 ----------

def build_cmd(claude: str, session_id: str | None) -> list[str]:
    cmd = [claude, "-p", "--output-format", "stream-json", "--verbose", "--dangerously-skip-permissions",
           # 不加载项目里的 .claude/settings.json：那是给 agentos 账号里的助理设的限制，开发模式不受它约束
           "--setting-sources", "user,local"]
    if session_id:
        cmd += ["--resume", session_id]
    return cmd


def outbox(task_id: int, home: Path | None = None) -> Path:
    return (home or Path.home()) / OUTBOX_NAME / str(task_id)


def prompt_for(text: str, task_id: int, home: Path | None = None) -> str:
    return (f"{text}\n\n（系统提示：这条来自主人手机飞书的「开发模式」，任务号 {task_id}。你在他的 Mac 上以他本人身份、"
            f"最高权限工作。你的回复会推到他手机上看：先给结论，尽量短。要把文件发给他，放进 {outbox(task_id, home)}/，"
            "做完会自动发到飞书。要操作电脑上的软件（Word、Excel、PowerPoint、WPS、Keynote、Pages、Numbers、访达、"
            "Safari、邮件等），用 open 打开、osascript（AppleScript / JavaScript for Automation）控制；"
            "要看屏幕上现在是什么，用 screencapture -x 截图再读图片。弹出 macOS 权限提示、或屏幕锁着做不了时，"
            "如实告诉他要在电脑前点一下什么。）")
