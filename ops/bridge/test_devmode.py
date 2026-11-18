"""开发模式离线测试：假 claude、假飞书、假的会话文件，不碰网络。

运行：~/.agentos/venv/bin/python -m unittest ops/bridge/test_devmode.py -v
"""

import json
import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bridge  # noqa: E402
import devmode  # noqa: E402
from test_bridge import FakeFeishu, wait_for  # noqa: E402

SID_A = "aaaaaaaa-0000-0000-0000-000000000001"
SID_B = "bbbbbbbb-0000-0000-0000-000000000002"

# 假的 claude：回显收到的参数、所在文件夹；新会话给一个固定的新会话号；还会往「发给手机」放个文件
FAKE_DEV = r'''#!/usr/bin/env python3
import json, os, re, sys
args = sys.argv[1:]
prompt = sys.stdin.read()
sid = args[args.index("--resume") + 1] if "--resume" in args else "cccccccc-0000-0000-0000-000000000003"
m = re.search(r"放进 (\S+)/，", prompt)
if "发个文件" in prompt and m:
    os.makedirs(m.group(1), exist_ok=True)
    open(os.path.join(m.group(1), "截图.png"), "w").write("png")
emit = lambda e: print(json.dumps(e, ensure_ascii=False), flush=True)
emit({"type": "system", "subtype": "init", "session_id": sid})
skip = "--dangerously-skip-permissions" in args
emit({"type": "result", "subtype": "success", "is_error": False, "session_id": sid,
      "result": f"cwd={os.getcwd()}|resume={'--resume' in args}|sid={sid}|skip={skip}|task={prompt.split(chr(10))[0]}"})
'''


def write_session(projects: Path, sid: str, cwd: str, title: str, first: str, mtime: float):
    d = projects / ("-" + cwd.strip("/").replace("/", "-"))
    d.mkdir(parents=True, exist_ok=True)
    p = d / f"{sid}.jsonl"
    lines = [{"type": "user", "cwd": cwd, "message": {"content": [{"type": "text", "text": first}]}}]
    if title:
        lines.append({"type": "custom-title", "customTitle": title, "sessionId": sid})
    p.write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in lines) + "\n")
    os.utime(p, (mtime, mtime))


class ParseTest(unittest.TestCase):
    def test_parse(self):
        self.assertIsNone(devmode.parse("帮我查一下张总"))
        self.assertEqual(devmode.parse("开发：会话"), ("list", "", 0))
        self.assertEqual(devmode.parse("开发:"), ("list", "", 0))
        self.assertEqual(devmode.parse("开发：结束"), ("end", "", 0))
        self.assertEqual(devmode.parse("开发：接着 2 把测试跑了"), ("resume", "把测试跑了", 2))
        self.assertEqual(devmode.parse("开发：接着第3个"), ("resume", devmode.DEFAULT_GO, 3))
        self.assertEqual(devmode.parse("开发：新任务 写个脚本"), ("new", "写个脚本", 0))
        self.assertEqual(devmode.parse("/dev 修一下 bug"), ("run", "修一下 bug", 0))


class DevBridgeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = Path(self.tmp.name)
        fake = t / "fake_dev.py"
        fake.write_text(FAKE_DEV)
        fake.chmod(0o755)
        self.projects = t / "projects"
        (t / "work").mkdir()
        (t / "proj-a").mkdir()
        now = time.time()
        write_session(self.projects, SID_A, str(t / "proj-a"), "讯飞移植到 Windows", "帮我做讯飞", now - 3600)
        write_session(self.projects, SID_B, str(t / "work"), "", "<system-reminder>x</system-reminder>修个网页", now)
        self.home = t / "home"
        self.cfg = bridge.Config(
            app_id="x", app_secret="y", owner_open_id="ou_owner", runtime_dir=str(t),
            agent_user="agentos", max_concurrency=2, stuck_notice_sec=60, hard_timeout_sec=30,
            claude_cmd=[sys.executable, "-c", "raise SystemExit(9)"],
            dev_mode=True, dev_dir=str(t / "work"), dev_claude=str(fake), claude_projects=str(self.projects))
        self.store = bridge.Store(t / "bridge.db")
        self.fs = FakeFeishu()
        self.b = bridge.Bridge(self.cfg, self.store, self.fs)
        self.orig_outbox = devmode.outbox
        devmode.outbox = lambda task_id, home=None: self.orig_outbox(task_id, self.home)
        threading.Thread(target=self.b.dispatch_forever, daemon=True).start()
        self.n = 0

    def tearDown(self):
        devmode.outbox = self.orig_outbox
        self.tmp.cleanup()

    def send(self, text):
        self.n += 1
        self.b.on_message(f"om_{self.n}", "oc_1", "p2p", "ou_owner", "text", json.dumps({"text": text}))

    def md(self, i):
        self.assertTrue(wait_for(lambda: len(self.fs.of("md")) > i))
        return self.fs.of("md")[i][2]

    def test_list_then_resume(self):
        self.send("开发：会话")
        listing = self.md(0)
        self.assertIn("1. 修个网页（work，刚刚还在用）", listing)  # 没标题用第一句话，去掉系统提示
        self.assertIn("2. 讯飞移植到 Windows（proj-a，", listing)
        self.send("开发：接着 2 把剩下的做完")
        out = self.md(1)
        self.assertIn("proj-a|resume=True", out)  # 在那个会话自己的文件夹里跑
        self.assertIn(f"resume=True|sid={SID_A}|skip=True|task=把剩下的做完", out)
        self.send("开发：再跑一遍测试")  # 接着同一个开发会话
        self.assertIn(f"sid={SID_A}", self.md(2))

    def test_new_task_then_continue_and_end(self):
        self.send("开发：新任务 写个脚本")
        out = self.md(0)
        self.assertIn("resume=False", out)
        self.assertIn("task=写个脚本", out)
        self.assertIn(str(Path(self.tmp.name, "work").name), out)
        self.assertEqual(self.store.get_session("oc_1"), None)  # 平时助理的会话不受影响
        self.send("开发：结束")
        self.assertTrue(wait_for(lambda: any("开发会话结束" in c[2] for c in self.fs.of("reply"))))
        self.assertIsNone(self.store.get_session("oc_1#dev"))

    def test_bad_index_and_files_sent(self):
        self.send("开发：接着 9")
        self.assertTrue(wait_for(lambda: any("没有第 9 个" in c[2] for c in self.fs.of("text"))))
        self.send("开发：发个文件给我")
        self.assertTrue(wait_for(lambda: self.fs.of("file")))
        self.assertEqual(self.fs.of("file")[0][2], "截图.png")

    def test_normal_messages_still_use_assistant(self):
        self.send("帮我查一下张总")
        self.assertIn("异常退出", self.md(0))  # 走的是平时的助理命令（这里是个会失败的假命令），不是开发模式

    def test_dev_mode_off(self):
        self.cfg.dev_mode = False
        self.send("开发：新任务 写个脚本")
        self.assertTrue(wait_for(lambda: any("开发模式已关" in c[2] for c in self.fs.of("reply"))))


if __name__ == "__main__":
    unittest.main()
