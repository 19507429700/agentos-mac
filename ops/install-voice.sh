#!/bin/bash
# 以你的账号运行（不用 sudo）：ops/install-voice.sh
# 装微信语音转文字：建转写专用的 Python 环境（~/.agentos/voice-python），装 pilk（解码微信的 SILK 语音）
# 和 faster-whisper，再下载 whisper small 模型（约 460MB）到 ~/.agentos/whisper/small。
# 装好后微信采集会自动把语音转成文字，不用改别的。全程在本机转写，不上传语音。可重复运行。
#
# 国内下载模型默认走 hf-mirror.com；要换来源：HF_ENDPOINT=https://huggingface.co ops/install-voice.sh
# 要走代理：先 export HTTPS_PROXY=http://127.0.0.1:端口
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$HOME/.agentos"
VENV="$STATE/voice-python"
MODEL="$STATE/whisper/small"

# 1. Python：优先 Homebrew 的 3.14（和微信采集同一个），没有就找 3.13 / 3.12 / 3.11
PY=""
for p in /opt/homebrew/bin/python3.14 python3.14 python3.13 python3.12 python3.11; do
  if command -v "$p" >/dev/null 2>&1; then PY="$(command -v "$p")"; break; fi
done
[[ -n "$PY" ]] || { echo "没找到 Python 3.11 以上。先运行：brew install python@3.14" >&2; exit 1; }
echo "==> 1/3 转写环境 ${VENV}（用 ${PY}）"
[[ -x "$VENV/bin/python" ]] || "$PY" -m venv "$VENV"
"$VENV/bin/pip" install -q --disable-pip-version-check --upgrade pip

# 2. 装包。pilk 要现场编译；命令行工具默认的 SDK 是测试版时会链接失败，就换一个正式版 SDK 再试
echo "==> 2/3 装 pilk、faster-whisper"
install_pkgs() { "$VENV/bin/pip" install -q --disable-pip-version-check pilk faster-whisper; }
if ! install_pkgs; then
  SDKS=/Library/Developer/CommandLineTools/SDKs
  ok=""
  for sdk in $(ls -d "$SDKS"/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
    echo "    换 SDK 再试：$(basename "$sdk")"
    if SDKROOT="$sdk" install_pkgs; then ok=1; break; fi
  done
  [[ -n "$ok" ]] || { echo "装包失败：见上面的报错（多半是编译 pilk 失败，先运行 xcode-select --install）" >&2; exit 1; }
fi
"$VENV/bin/python" -c "import pilk, faster_whisper" >/dev/null

# 3. 模型
echo "==> 3/3 语音模型 $MODEL"
if [[ -f "$MODEL/model.bin" ]]; then
  echo "    已经有了，跳过下载"
else
  mkdir -p "$MODEL"
  HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}" "$VENV/bin/python" - "$MODEL" <<'PY'
import sys
from huggingface_hub import snapshot_download
snapshot_download("Systran/faster-whisper-small", local_dir=sys.argv[1],
                  allow_patterns=["config.json", "model.bin", "tokenizer.json", "vocabulary.*"])
PY
fi
[[ -f "$MODEL/model.bin" ]] || { echo "模型下载失败，重跑本脚本即可接着下" >&2; exit 1; }

echo "完成。之后微信采集（每 10 分钟）会把新的语音消息转成文字，写成「[语音 14秒] 转出的文字」。"
echo "不想要了：在 ~/.agentos/wechat.env 里加一行 WECHAT_VOICE=0"
