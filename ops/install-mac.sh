#!/bin/bash
# AgentOS Mac 版一键安装 / 更新。在你自己的账号里（不要 sudo）运行：~/AgentOS/ops/install-mac.sh
# 可以重复运行：每次都会补上还没装的部分（哪一项的钥匙填好了，就装哪一项），不会弄坏已有的。
# 做的事：
#   1. 检查软件（Homebrew、Python 3.14、uv、sqlcipher、LibreOffice），缺的用 Homebrew 装上
#   2. 初始化（要输一次管理员密码）：建隐藏账号 agentos、运行副本、Claude 令牌文件、免密规则、装 Claude Code
#   3. 飞书机器人（填好 bridge.env 就启动）
#   4. 定时任务：邮件、飞书、微信、讯飞录音笔采集，公众号抓取，提取文字，每日复盘，知识库备份
#   5. 微信语音转文字（配了微信才装，下载约 460MB 的模型，只下一次）
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$HOME/.agentos"
[[ $EUID -ne 0 ]] || { echo "不要用 sudo 运行，直接运行：$0（中间要管理员密码时会问你）" >&2; exit 1; }
[[ "$REPO" == "$HOME/AgentOS" ]] || { echo "代码要放在 $HOME/AgentOS（现在在 ${REPO}），安装脚本按这个位置找" >&2; exit 1; }
BREW="$(command -v brew || echo /opt/homebrew/bin/brew)"

echo "==> 1/5 检查软件"
[[ -x "$BREW" ]] || { echo "    没装 Homebrew：打开 https://brew.sh ，把首页那一行命令复制到终端运行，装完重开终端再跑本脚本" >&2; exit 1; }
need=()
[[ -x /opt/homebrew/bin/python3.14 ]] || need+=(python@3.14)
command -v uv >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/uv" ]] || need+=(uv)
command -v sqlcipher >/dev/null 2>&1 || need+=(sqlcipher)
if ((${#need[@]})); then
  echo "    用 Homebrew 装：${need[*]}"
  "$BREW" install "${need[@]}"
else
  echo "    Python 3.14、uv、sqlcipher 都有了"
fi
if [[ -d /Applications/LibreOffice.app ]]; then
  echo "    LibreOffice 有了"
else
  echo "    装 LibreOffice（出 Word、PDF 用，约 1GB，第一次要等一会儿）"
  "$BREW" install --cask libreoffice || echo "    ⚠️ LibreOffice 没装上（不影响其他功能），之后重跑本脚本会再试"
fi

# 已经初始化过（免密规则在、运行副本在）：只用免密规则把运行副本更新到最新代码，不再要密码。
# 要强制重做初始化（比如免密规则改过）：AGENTOS_BOOTSTRAP=1 ~/AgentOS/ops/install-mac.sh
RUNTIME=/Users/agentos/agentos
# 注意：命令要和免密规则里写的一字不差（bootstrap-mac.sh），多一个参数 sudo 就会要密码
if [[ -z "${AGENTOS_BOOTSTRAP:-}" ]] && sudo -n -H -u agentos /usr/bin/git -C "$RUNTIME" pull --ff-only >/dev/null 2>&1; then
  echo "==> 2/5 初始化：之前做过了，运行副本已更新到最新代码"
else
  echo "==> 2/5 初始化（要输入这台 Mac 的开机密码，输的时候屏幕不显示，是正常的）"
  sudo "$REPO/ops/bootstrap-mac.sh"
fi

echo "==> 3/5 飞书机器人"
"$REPO/ops/install-bridge.sh"

echo "==> 4/5 定时任务"
"$REPO/ops/install-collectors.sh"

echo "==> 5/5 微信语音转文字"
if ! grep -qE '^WECHAT_DB_ROOT=.+' "$STATE/wechat.env" 2>/dev/null; then
  echo "    还没配微信（教程第十三步），跳过"
elif grep -qE '^WECHAT_VOICE=0' "$STATE/wechat.env"; then
  echo "    wechat.env 里关了（WECHAT_VOICE=0），跳过"
elif [[ -f "$STATE/whisper/small/model.bin" && -x "$STATE/voice-python/bin/python" ]]; then
  echo "    已经装好了"
else
  "$REPO/ops/install-voice.sh" || echo "    ⚠️ 语音转文字没装好（多半是网络），重跑本脚本会接着装；不影响其他功能"
fi

echo
echo "全部完成。还没做的步骤，上面会写「跳过」和原因；按教程补上后，再运行一次本脚本："
echo "  ~/AgentOS/ops/install-mac.sh"
