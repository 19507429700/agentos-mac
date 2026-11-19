"""微信采集的离线测试：不碰真微信库，语音转写用假的转写程序。

运行：/opt/homebrew/bin/python3.14 -m unittest ops/test_wechat.py -v（3.9 也能跑）
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent))
import collect_wechat as cw  # noqa: E402


class FakeWechat:
    """read_new 返回固定的几条消息；voice_audio 只认识 111、222 两条语音。"""

    def __init__(self, rows):
        self.rows = rows
        self.asked = []

    def display_name(self, u):
        return {"wxid_friend": "小王"}.get(u, u)

    def message_dbs_for(self, chat_id, cached):
        return ["message_0.db"]

    def read_new(self, chat_id, dbname, after_id, start_ts, is_group):
        return self.rows

    def voice_audio(self, ids):
        self.asked.append(list(ids))
        return {i: b"\x02#!SILK_V3" + i.encode() for i in ids if i in ("111", "222")}

    def copy_file(self, *a):
        return None

    def save_image(self, chat_id, svr_id, ts, raw_dir, day, self_id):
        return f"spaces/me/raw/wechat/images/{day}/x-{svr_id}.png" if svr_id == "555" else None


class VoiceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.raw = Path(self.tmp.name) / "raw"
        self.ts = 1794802892  # 2026-11-16 一个时刻
        self.rows = [
            (1, self.ts, "wxid_friend", "在吗", None, "", ""),
            (2, self.ts + 60, "wxid_friend", "[语音]", None, "111", ""),
            (3, self.ts + 120, "wxid_me", "[语音]", None, "222", ""),
            (4, self.ts + 180, "wxid_friend", "[语音]", None, "333", ""),  # 库里找不到音频
        ]

    def tearDown(self):
        self.tmp.cleanup()

    def collect(self, transcribe):
        wx = FakeWechat(self.rows)
        st = {"chats": {}}
        n = cw.collect_chat(wx, {"username": "wxid_friend", "last_timestamp": self.ts + 200}, st,
                            self.raw, 3, "wxid_me", self.ts + 300, 25, transcribe)
        text = "".join(p.read_text(encoding="utf-8") for p in sorted(self.raw.rglob("*.md")))
        return n, text, wx

    def test_voice_turned_into_text(self):
        seen = []

        def fake(audio):
            seen.append(sorted(audio))
            return {"111": {"text": "明天下午三点开会", "sec": 4.2}, "222": {"text": "", "sec": 1.0}}
        n, text, wx = self.collect(fake)
        self.assertEqual(n, 4)
        self.assertEqual(wx.asked, [["111", "222", "333"]])  # 一个会话的语音一次取、一次转
        self.assertEqual(seen, [["111", "222"]])
        self.assertIn("小王：在吗", text)
        self.assertIn("小王：[语音 4秒] 明天下午三点开会", text)
        self.assertIn("我：[语音 1秒]（没听出内容）", text)
        self.assertIn("小王：[语音]\n", text)  # 没有音频的照旧只留占位

    def test_transcribe_failure_keeps_placeholder(self):
        def broken(audio):
            raise RuntimeError("模型坏了")
        n, text, _ = self.collect(broken)
        self.assertEqual(n, 4)
        self.assertEqual(text.count("：[语音]\n"), 3)
        self.assertIn("小王：在吗", text)

    def test_no_transcriber(self):
        n, text, wx = self.collect(None)
        self.assertEqual(wx.asked, [])  # 没开转写，不去取音频
        self.assertEqual(text.count("：[语音]\n"), 3)


class TranscribeVoicesTest(unittest.TestCase):
    """transcribe_voices 调转写程序：用一个假的「Python」脚本代替真的 whisper。"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fake = Path(self.tmp.name) / "python"
        self.fake.write_text(
            "#!/bin/sh\n"
            "# 参数：$1=transcribe_voice.py，$2=放 .silk 的文件夹\n"
            "for f in \"$2\"/*.silk; do n=$(basename \"$f\");\n"
            "  case \"$n\" in bad*) echo '{\"name\": \"'$n'\", \"ok\": false, \"error\": \"坏文件\"}';;\n"
            "  *) echo '{\"name\": \"'$n'\", \"ok\": true, \"text\": \"你好\", \"sec\": 2.0}';; esac; done\n"
            "echo 'ctranslate2 的提示行，不是 JSON'\n")
        self.fake.chmod(0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def test_parses_results(self):
        with mock.patch.dict(os.environ, {"WECHAT_VOICE_PYTHON": str(self.fake)}):
            got = cw.transcribe_voices({"111": b"x", "bad2": b"y"})
        self.assertEqual(got, {"111": {"text": "你好", "sec": 2.0}})

    def test_missing_env_returns_empty(self):
        with mock.patch.dict(os.environ, {"WECHAT_VOICE_PYTHON": str(Path(self.tmp.name) / "没有")}):
            self.assertEqual(cw.transcribe_voices({"111": b"x"}), {})

    def test_voice_line(self):
        self.assertEqual(cw.voice_line(None), "[语音]")
        self.assertEqual(cw.voice_line({"text": "好的", "sec": 13.8}), "[语音 14秒] 好的")
        self.assertEqual(cw.voice_line({"text": "好的", "sec": None}), "[语音] 好的")


if __name__ == "__main__":
    unittest.main()


class ImageTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.raw = Path(self.tmp.name) / "raw"
        self.ts = 1794802892

    def tearDown(self):
        self.tmp.cleanup()

    def test_image_line_points_to_saved_file(self):
        rows = [(1, self.ts, "wxid_friend", "[图片]", None, "", "555"),
                (2, self.ts + 60, "wxid_friend", "[图片]", None, "", "666")]  # 本机没有这张
        cw.collect_chat(FakeWechat(rows), {"username": "wxid_friend", "last_timestamp": self.ts + 100},
                        {"chats": {}}, self.raw, 3, "wxid_me", self.ts + 300, 25, None)
        text = "".join(p.read_text(encoding="utf-8") for p in self.raw.rglob("*.md"))
        self.assertIn("小王：[图片] 可看：spaces/me/raw/wechat/images/2026-11-16/x-555.png", text)
        self.assertIn("小王：[图片]\n", text)

    def test_images_off(self):
        rows = [(1, self.ts, "wxid_friend", "[图片]", None, "", "555")]
        cw.collect_chat(FakeWechat(rows), {"username": "wxid_friend", "last_timestamp": self.ts + 100},
                        {"chats": {}}, self.raw, 3, "wxid_me", self.ts + 300, 25, None, images=False)
        text = "".join(p.read_text(encoding="utf-8") for p in self.raw.rglob("*.md"))
        self.assertNotIn("可看", text)

    def test_decode_v2_v1_and_plain(self):
        """按同样的格式造一张加密图（V2：AES 段 + 原样段 + 异或段），能解回原图。"""
        import hashlib, struct
        import wechat_images as wi
        png = b"\x89PNG\r\n\x1a\n" + bytes(range(60)) + b"IEND\xaeB`\x82"
        acct = Path(self.tmp.name) / "xwechat_files" / "wxid_me_ab12"
        (acct.parent.parent / "app_data" / "net" / "kvcomm").mkdir(parents=True)
        (acct.parent.parent / "app_data" / "net" / "kvcomm" / "key_12345_1.statistic").write_text("")
        acct.mkdir(parents=True)
        keys = wi.candidate_keys(acct, "wxid_me")
        key, xor = hashlib.md5(b"12345wxid_me").hexdigest()[:16].encode(), 12345 & 255
        self.assertIn((key, xor), keys)

        def enc(k, plain):
            pad = 16 - len(plain) % 16
            plain += bytes([pad]) * pad
            try:
                from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
                e = Cipher(algorithms.AES(k), modes.ECB()).encryptor()
                return e.update(plain) + e.finalize()
            except ImportError:
                import subprocess
                return subprocess.run(["/usr/bin/openssl", "enc", "-aes-128-ecb", "-nopad", "-K", k.hex()],
                                      input=plain, capture_output=True).stdout

        def build(marker, k, x_byte, a=20, x=6):
            mid = png[a:len(png) - x]
            return (marker + struct.pack("<II", a, x) + b"\x01" + enc(k, png[:a]) + mid
                    + bytes(c ^ x_byte for c in png[-x:]))
        self.assertEqual(wi.decode_dat(build(wi.V2, key, xor), keys), (png, ".png"))
        self.assertEqual(wi.decode_dat(build(wi.V1, wi.V1_KEY, 0x37), []), (png, ".png"))
        self.assertEqual(wi.decode_dat(bytes(c ^ 0x5A for c in png), []), (png, ".png"))  # 老格式：整体异或
        self.assertIsNone(wi.decode_dat(build(wi.V2, b"0" * 16, 0), keys))  # 钥匙不对：解不开
