#!/bin/bash
# 以你的账号运行（不用 sudo）：ops/install-collectors.sh
# 装定时任务：邮箱采集、飞书采集（每 10 分钟），知识库备份到 GitHub（每天 03:00）。
# 各自满足前提才装（填好 mail.env / 运行过 feishu_auth.py / 免密规则里有 backup-kb.sh）。可重复运行。
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$HOME/.agentos"
ENV_FILE="$STATE/mail.env"

mkdir -p "$STATE/logs"
chmod 700 "$STATE"

# 装一个 launchd 定时任务：install_job <名字>，模板是 ops/launchd/com.agentos.<名字>.plist
install_job() {
  local name="$1"
  local plist="$HOME/Library/LaunchAgents/com.agentos.$name.plist"
  local label="gui/$(id -u)/com.agentos.$name"
  mkdir -p "$(dirname "$plist")"
  sed -e "s#__HOME__#$HOME#g" -e "s#__REPO__#$REPO#g" "$REPO/ops/launchd/com.agentos.$name.plist" > "$plist"
  plutil -lint "$plist" >/dev/null
  launchctl bootout "$label" 2>/dev/null || true
  # bootout 是异步的，旧服务没退干净就 bootstrap 会报 Input/output error
  for _ in {1..20}; do launchctl print "$label" &>/dev/null || break; sleep 0.5; done
  launchctl bootstrap "gui/$(id -u)" "$plist"
}

# ---------- 邮箱 ----------
if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<'EOF'
# 邮箱 IMAP 只读采集。授权码在邮箱网页版「设置」里开启 IMAP 后生成，不是登录密码
# QQ 邮箱 imap.qq.com ｜ 163 邮箱 imap.163.com ｜ 腾讯企业邮 imap.exmail.qq.com
# Gmail imap.gmail.com（国内要代理开 TUN/全局模式，IMAP 不走 HTTP 代理）
MAIL_IMAP_HOST=
MAIL_USER=
MAIL_PASSWORD=
# 多个文件夹用逗号隔开；第一次拉最近几天
MAIL_FOLDERS=INBOX
MAIL_INITIAL_DAYS=7
EOF
  echo "已生成 ${ENV_FILE}，要采邮件就按教程第十步填好 MAIL_IMAP_HOST / MAIL_USER / MAIL_PASSWORD，再运行 ~/AgentOS/ops/install-mac.sh"
fi
chmod 600 "$ENV_FILE"

if grep -qE '^MAIL_PASSWORD=.+' "$ENV_FILE"; then
  echo "==> 邮箱：测试登录"
  if /usr/bin/python3 "$REPO/ops/collect_mail.py" --check; then
    install_job collect-mail
    if [[ ! -f "$STATE/mail_state.json" ]]; then  # 只有第一次装时当场拉一次，之后交给定时任务，重跑安装不用干等
      echo "==> 邮箱：先拉一次"
      /usr/bin/python3 "$REPO/ops/collect_mail.py" || echo "    （这次拉取有报错，见上面；定时任务已装好，下次会重试）"
    else
      echo "==> 邮箱：已经在采了（定时任务每 10 分钟一次）"
    fi
    echo "    之后每 10 分钟自动拉。日志：$STATE/logs/collect-mail.log"
  else
    echo "    ⚠️ 邮箱登录失败（看上面的原因，检查 mail.env），邮件采集这次没装；其他照装"
  fi
else
  echo "==> 邮箱还没填，跳过"
fi

# ---------- 飞书 ----------
if [[ -f "$STATE/feishu_user_token.json" ]]; then
  install_job collect-feishu
  if [[ ! -f "$STATE/feishu_state.json" ]]; then  # 只有第一次装时当场拉一次，之后交给定时任务，重跑安装不用干等
    echo "==> 飞书：先拉一次"
    /usr/bin/python3 "$REPO/ops/collect_feishu.py" || echo "    （这次拉取有报错，见上面；定时任务已装好，下次会重试）"
  else
    echo "==> 飞书：已经在采了（定时任务每 10 分钟一次）"
  fi
  echo "    之后每 10 分钟自动拉。日志：$STATE/logs/collect-feishu.log"
else
  echo "==> 飞书还没以你本人身份授权，跳过（先运行：python3 $REPO/ops/feishu_auth.py）"
fi

# ---------- 微信（本机，个人自用）----------
if grep -qE '^WECHAT_DB_ROOT=.+' "$STATE/wechat.env" 2>/dev/null; then
  # 专用 Python：python3.14 的独立拷贝，只给微信采集用。读微信目录要「完全磁盘访问权限」，只授给它，
  # 平时的 python3.14 拿不到。Homebrew 升级 Python 后它可能失效：删掉这个目录重跑本脚本，再重新授权
  WXPY="$STATE/wechat-python/bin/python3.14"
  if ! "$WXPY" -c "from compression import zstd" 2>/dev/null; then
    rm -rf "$STATE/wechat-python"
    /opt/homebrew/bin/python3.14 -m venv --copies "$STATE/wechat-python"
  fi
  install_job collect-wechat
  if [[ ! -f "$STATE/wechat_state.json" ]]; then  # 只有第一次装时当场拉一次，之后交给定时任务，重跑安装不用干等
    echo "==> 微信：先拉一次"
    "$WXPY" "$REPO/ops/collect_wechat.py" || echo "    （这次拉取有报错，见上面；定时任务已装好，下次会重试）"
  else
    echo "==> 微信：已经在采了（定时任务每 10 分钟一次）"
  fi
  echo "    之后每 10 分钟自动拉。日志：$STATE/logs/collect-wechat.log"
  echo "    不想每次弹「访问其他 App 的数据」：系统设置 → 隐私与安全性 → 完全磁盘访问权限 → + → 加入 $WXPY"
else
  echo "==> 微信没配置，跳过（取好密钥、配置 $STATE/wechat.env 里的 WECHAT_DB_ROOT 后重跑）"
fi

# ---------- 讯飞录音笔（可选）----------
# 装了客户端、并且授权过（凭据由讯飞客户端存在 ~/.iflyrec-assistant/prod/）才装；没授权就装的话每 10 分钟报一次「授权失效」
if [[ -f "$STATE/iflyrec-skill/scripts/recording_assistant.py" && -f "$HOME/.iflyrec-assistant/prod/credentials.json" ]]; then
  install_job collect-iflyrec
  if [[ ! -f "$STATE/iflyrec_state.json" ]]; then  # 只有第一次装时当场拉一次，之后交给定时任务，重跑安装不用干等
    echo "==> 讯飞录音笔：先拉一次"
    /usr/bin/python3 "$REPO/ops/collect_iflyrec.py" || echo "    （这次拉取有报错，见上面；授权失效就重跑 ~/AgentOS/ops/install-iflyrec.sh）"
  else
    echo "==> 讯飞录音笔：已经在采了（定时任务每 10 分钟一次）"
  fi
  echo "    之后每 10 分钟自动拉。日志：$STATE/logs/collect-iflyrec.log"
else
  launchctl bootout "gui/$(id -u)/com.agentos.collect-iflyrec" 2>/dev/null || true
  echo "==> 讯飞录音笔没接（或还没授权），跳过（要接就做教程第十五步）"
fi

# ---------- 本机 AI 聊天（WorkBuddy、Claude Code、Codex、Grok Bot）----------
# 只读你账号里这些软件的本地聊天记录，不读账号和密码；原文写进运行副本的 raw/ai/，复盘和搜索都会用到
install_job collect-ai
if [[ ! -f "$STATE/ai_chats.db" ]]; then  # 只有第一次装时当场采一次（往回读 30 天），之后交给定时任务
  echo "==> 本机 AI 聊天：先采一次"
  /usr/bin/python3 "$REPO/ops/collect_ai_chats.py" || echo "    （这次采集有报错，见上面；定时任务已装好，下次会重试）"
else
  echo "==> 本机 AI 聊天：已经在采了（定时任务每 10 分钟一次）"
fi
echo "    之后每 10 分钟自动采。日志：$STATE/logs/collect-ai.log"

# ---------- 团队互查（本人打开过共享才装）----------
if /usr/bin/python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("enabled") else 1)' "$STATE/team-sharing.json" 2>/dev/null; then
  install_job team-chat
  echo "==> 团队互查：查询服务已装好，登录后一直运行。看状态：python3 $REPO/ops/team_chat_server.py status"
else
  echo "==> 团队互查还没打开共享，跳过（要接入见 docs/team.md）"
fi

# ---------- 公众号文章自动抓取归档 ----------
if grep -qE '^WECHAT_DB_ROOT=.+' "$STATE/wechat.env" 2>/dev/null; then
  # 专用 Python：wxfetch-python，带 requests+bs4（fetch_wx.py 抓正文用）。抓正文不读微信目录，
  # 不需要完全磁盘访问权限。Homebrew 升级 Python 后可能失效：删掉重跑本脚本即可重建。
  WXFETCHPY="$STATE/wxfetch-python/bin/python"
  if ! "$WXFETCHPY" -c "import requests, bs4" 2>/dev/null; then
    rm -rf "$STATE/wxfetch-python"
    /opt/homebrew/bin/python3.14 -m venv --copies "$STATE/wxfetch-python"
    "$WXFETCHPY" -m pip install -q "requests>=2.28" "beautifulsoup4>=4.11"
  fi
  install_job fetch-wechat-articles
  if [[ ! -f "$STATE/wechat_articles.json" ]]; then  # 只有第一次装时当场拉一次，之后交给定时任务，重跑安装不用干等
    echo "==> 公众号文章：先抓一次"
    /usr/bin/python3 "$REPO/ops/fetch_wechat_articles.py" || echo "    （这次抓取有报错，见上面；定时任务已装好，下次会重试）"
  else
    echo "==> 公众号文章：已经在采了（定时任务每 10 分钟一次）"
  fi
  echo "    之后每 10 分钟自动抓 pending 链接并归档。日志：$STATE/logs/fetch-wechat-articles.log"
else
  echo "==> 公众号文章抓取跳过：wechat.env 里还没有 WECHAT_DB_ROOT（先配置微信采集）"
fi

# ---------- 提取文字（图片识字、PDF / Word / PPT 正文）----------
# 只用 macOS 自带的 Vision、PDFKit、textutil 和系统 Python，不用装东西。第一次原文多，要跑几轮才做完。
install_job extract-text
echo "==> 提取文字：每 10 分钟一轮（每轮最多 4 分钟），结果存成原文件旁边的 .txt。日志：$STATE/logs/extract-text.log"

# ---------- 每日复盘 ----------
if grep -qE '^OWNER_OPEN_ID=.+' "$STATE/bridge.env" 2>/dev/null; then
  install_job daily-review
  echo "==> 每日复盘：每天 23:00 写复盘并推到飞书和微信。日志：$STATE/logs/daily-review.log（手动试跑：$REPO/ops/daily-review.sh）"
else
  echo "==> 每日复盘跳过：bridge.env 里还没有 OWNER_OPEN_ID（先做教程第八步「绑定你自己」）"
fi

# ---------- 知识库备份 ----------
if ! "$REPO/ops/push-kb.sh" --check; then
  launchctl bootout "gui/$(id -u)/com.agentos.push-kb" 2>/dev/null || true
  echo "==> 知识库备份跳过（原因见上一行）"
elif sudo -n -H -u agentos /usr/bin/git -C /Users/agentos/agentos pull --ff-only >/dev/null 2>&1; then  # 免密规则在（初始化时和备份规则一起装的）
  install_job push-kb
  echo "==> 知识库：每天 03:00 备份到 GitHub。日志：$STATE/logs/push-kb.log（手动备份：$REPO/ops/push-kb.sh）"
else
  echo "==> 知识库备份跳过：免密规则里还没有 backup-kb.sh，先重跑一次 sudo $REPO/ops/bootstrap-mac.sh"
fi
