#!/bin/bash
# 以你的账号运行（不用 sudo）：ops/install-iflyrec.sh
# 接讯飞录音笔：下载讯飞官方的只读客户端（录音笔 Skill），核对指纹后放到 ~/.agentos/iflyrec-skill/，
# 再申请授权。授权好后重跑 ops/install-mac.sh，就会每 10 分钟把新录音的总结和转写收进知识库。
#
# 为什么不直接用官方的 `curl … | bash`：它会把 Skill 装进「当前 AI」的技能文件夹，而 AgentOS 的采集要以你本人账号
# 定时运行，凭据也要放在 AI 读不到的地方。这里做的事和官方安装器一样（取版本信息、下载、逐个核对指纹），只是换了位置。
# 可重复运行：已经授权过的不会要求重新登录。
set -euo pipefail

BASE="https://open.iflyrecorder.com/skills/iflytek-recorder"
DEST="$HOME/.agentos/iflyrec-skill"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> 1/3 下载讯飞录音笔官方客户端"
curl --proto '=https' --tlsv1.2 -fsSL "$BASE/latest.json" -o "$WORK/latest.json"
read -r URL SHA VERSION < <(/usr/bin/python3 - "$WORK/latest.json" "$BASE" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
a, base = d["artifact"], sys.argv[2]
ok = (d.get("name") == "iflytek-recorder" and d.get("skillDirectory") == "recording-assistant-prod"
      and a["url"].startswith(base + "/releases/") and re.fullmatch(r"[0-9a-f]{64}", a["sha256"]))
if not ok:
    sys.exit("版本信息不符合预期，停止")
print(a["url"], a["sha256"], d["version"])
PY
)
curl --proto '=https' --tlsv1.2 -fsSL "$URL" -o "$WORK/skill.zip"
[[ "$(shasum -a 256 "$WORK/skill.zip" | awk '{print $1}')" == "$SHA" ]] || { echo "技能包指纹不对，停止" >&2; exit 1; }
echo "    版本 $VERSION，指纹核对通过"

echo "==> 2/3 解压并逐个核对文件指纹，放到 $DEST"
unzip -q "$WORK/skill.zip" -d "$WORK/x"
/usr/bin/python3 - "$WORK/x/recording-assistant-prod" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
files = json.loads((root / "release.json").read_text())["files"]
for name, want in files.items():
    rel = name.split("/", 1)[1]
    if hashlib.sha256((root / rel).read_bytes()).hexdigest() != want:
        sys.exit("文件指纹不对：" + rel)
PY
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
mv "$WORK/x/recording-assistant-prod" "$DEST"
chmod -R go-rwx "$DEST"

echo "==> 3/3 授权（用你录音笔绑定的讯飞账号）"
CLI="$DEST/scripts/recording_assistant.py"
OUT="$(/usr/bin/python3 -B "$CLI" auth)"
/usr/bin/python3 - "$OUT" <<'PY'
import json, sys
d = json.loads(sys.argv[1]); data = d.get("data") or {}
if not d.get("success"):
    sys.exit("申请授权失败：" + str(d.get("errorCode")) + " " + str(d.get("message")))
if data.get("authenticated"):
    print("    已经授权过了，不用再登录")
else:
    print("    在浏览器里打开下面的链接，核对用户码后登录讯飞账号、点同意（" + str(data.get("expiresIn", 600) // 60) + " 分钟内有效）：")
    print("    " + data["verificationUriComplete"])
    print("    用户码：" + data["userCode"])
    print("    同意后运行下面这条确认，看到 \"authenticated\": true 就好了：")
PY
echo "    /usr/bin/python3 -B \"$CLI\" auth --check"
echo "完成后重跑 ~/AgentOS/ops/install-mac.sh，装上每 10 分钟的讯飞录音采集。"
