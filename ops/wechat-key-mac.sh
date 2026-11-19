#!/bin/bash
# 接微信（教程第十三步）：取这台 Mac 上当前登录的微信的钥匙，并写好配置。以你的账号运行（不要 sudo）：
#   ~/AgentOS/ops/wechat-key-mac.sh
# 做的事：
#   1. 没有取钥匙工具就下载到 ~/wechat-tool（开源 macos-wechat-export，MIT 协议；只用它的取钥匙和只读部分，
#      它的「发消息、操控微信」部分不编译、不使用）
#   2. 找出当前登录的微信账号（最近有写入的那个数据文件夹）
#   3. 等你正常退出微信，再取钥匙：打开一个微信的临时副本读钥匙，手机上可能要确认一次登录
#   4. 验证钥匙能打开数据库
#   5. 写好 ~/.agentos/wechat.env（已经填过的群名单等保留）
# 完成后运行 ~/AgentOS/ops/install-mac.sh 装上微信采集。微信「退出登录」、重装、大版本升级后钥匙会失效，重跑本脚本。
set -euo pipefail

TOOL="$HOME/wechat-tool"
ENVF="$HOME/.agentos/wechat.env"
PY=/opt/homebrew/bin/python3.14
XW="$HOME/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files"
[[ $EUID -ne 0 ]] || { echo "不要用 sudo 运行" >&2; exit 1; }
[[ -x "$PY" ]] || { echo "没有 Python 3.14，先运行 ~/AgentOS/ops/install-mac.sh" >&2; exit 1; }
[[ -d "$XW" ]] || { echo "这台 Mac 上没找到微信的数据（$XW），先装微信并登录" >&2; exit 1; }

PROXY=""
if [[ "$(scutil --proxy | awk '/HTTPSEnable/ {print $3}')" == "1" ]]; then
  PROXY="http://$(scutil --proxy | awk '/HTTPSProxy/ {print $3}'):$(scutil --proxy | awk '/HTTPSPort/ {print $3}')"
fi

echo "==> 1/5 取钥匙工具"
if [[ -f "$TOOL/bootstrap_keys.py" ]]; then
  echo "    已有 $TOOL"
else
  git ${PROXY:+-c http.proxy="$PROXY"} clone -q https://github.com/DaneelOlivaw1/macos-wechat-export.git "$TOOL"
  echo "    已下载到 $TOOL"
fi

echo "==> 2/5 当前登录的微信账号"
ROOT="$(/usr/bin/python3 - "$XW" <<'PY'
import sys
from pathlib import Path
best = None
for root in Path(sys.argv[1]).glob("wxid_*/db_storage"):
    for f in root.rglob("*.db*"):
        t = f.stat().st_mtime
        if best is None or t > best[0]:
            best = (t, root)
print(best[1] if best else "")
PY
)"
[[ -n "$ROOT" ]] || { echo "    没找到任何微信账号的数据，先在微信里登录" >&2; exit 1; }
ACCOUNT="$(basename "$(dirname "$ROOT")")"
echo "    $ACCOUNT（最近在用的就是它）"
echo "    不确定是不是你的：先在微信里登录你的账号、收发一条消息，再重跑本脚本"

echo "==> 3/5 取钥匙"
if pgrep -x WeChat >/dev/null; then
  echo "    请先**正常退出微信**：屏幕顶部菜单栏「微信」→ 退出微信（⌘Q）。只退出程序，不要退出登录。"
  while pgrep -x WeChat >/dev/null; do sleep 2; done
  echo "    微信已退出"
fi
echo "    接下来会打开一个微信窗口（临时副本）：点「进入微信」，手机上要确认就确认。取到钥匙后它会自动关掉、打开原来的微信。"
cd "$TOOL"
"$PY" bootstrap_keys.py --acknowledge-debug-copy --db-root "$ROOT"

echo "==> 4/5 验证钥匙"
if "$PY" wechat_db.py --db-root "$ROOT" verify >/dev/null; then
  echo "    ✅ 钥匙能打开全部数据库"
else
  echo "    ⚠️ 有的数据库打不开（见上面的输出）。微信还在后台更新的话，过一会儿重跑本脚本" >&2
  exit 1
fi

echo "==> 5/5 写配置 $ENVF"
mkdir -p "$(dirname "$ENVF")"
/usr/bin/python3 - "$ENVF" "$ROOT" "$TOOL" <<'PY'
import sys
from pathlib import Path
envf, root, tool = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
want = {"WECHAT_DB_ROOT": root, "WECHAT_KEYS": f"{tool}/.wechat-local/keys.json", "WECHAT_TOOL": tool}
lines = envf.read_text("utf-8").splitlines() if envf.exists() else [
    "# 微信采集（教程第十三步）。下面三行由 ops/wechat-key-mac.sh 自动写，不用改",
    "WECHAT_DB_ROOT=", "WECHAT_KEYS=", "WECHAT_TOOL=",
    "# 私聊全采；群只采这几个（群名关键词，逗号分隔）", "WECHAT_GROUPS=",
    "# 第一次每个会话往回读几天", "WECHAT_INITIAL_DAYS=3"]
out, seen = [], set()
for line in lines:
    k = line.split("=", 1)[0].strip()
    if k in want:
        line, _ = f"{k}={want[k]}", seen.add(k)
    out.append(line)
out += [f"{k}={v}" for k, v in want.items() if k not in seen]
envf.write_text("\n".join(out) + "\n", "utf-8")
envf.chmod(0o600)
PY
echo "    已写好。想采群：open -e $ENVF ，在 WECHAT_GROUPS= 后面填群名关键词（逗号分隔）"
echo
echo "完成。现在运行：~/AgentOS/ops/install-mac.sh   （装上微信采集、公众号抓取、语音转文字）"
