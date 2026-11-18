#!/bin/bash
# 以你的账号运行（launchd 每天 03:00；也可手动）：ops/push-kb.sh
# 知识库备份到 GitHub：知识库是 Agent 在运行副本里写的，所以按 副本 → 本仓库 → GitHub 的方向走，
# 三处始终是同一串提交，deploy.sh 不会冲突。
#   1. 运行副本先快进到本仓库的最新代码（免密规则里已有的 git pull）
#   2. 以 agentos 身份提交 spaces/me/kb/（免密规则里的 backup-kb.sh）
#   3. 本仓库从运行副本快进拉回这次提交
#   4. 推到 GitHub（走系统代理）
#   5. 推到 Gitee（配了 gitee 远程才推）
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# 模板仓库（只放代码、给别人装的）。知识库绝不能推到这里：刚 git clone 下来时 origin 就是它，
# 忘了换成自己的备份仓库，每天的备份就会把画像、复盘推进模板。以后模板换了地址，改这一行。
TEMPLATE_REPOS="19507429700/agentos-mac"
slug() { echo "$1" | tr 'A-Z' 'a-z' | sed -E 's#\.git$##; s#/$##; s#:#/#g' | awk -F/ '{print $(NF-1)"/"$NF}'; }
ORIGIN="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"
if [[ -z "$ORIGIN" ]]; then
  echo "还没设备份仓库（origin），知识库不备份。按教程第二步设好自己的私有仓库。"; exit 1
fi
for t in $TEMPLATE_REPOS; do
  if [[ "$(slug "$ORIGIN")" == "$t" ]]; then
    echo "origin 还是模板仓库（$t），知识库不能推到这里。按教程第二步把 origin 换成你自己的私有仓库。"; exit 1
  fi
done
[[ "${1:-}" == "--check" ]] && { echo "知识库备份到：$ORIGIN"; exit 0; }
RUNTIME=/Users/agentos/agentos
BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"

echo "==> $(date '+%F %T') 备份知识库（分支 ${BRANCH}）"
sudo -n -H -u agentos /usr/bin/git -C "$RUNTIME" pull --ff-only
sudo -n -H -u agentos "$RUNTIME/ops/backup-kb.sh"
git -C "$REPO" -c safe.directory="$RUNTIME" pull --ff-only -q "$RUNTIME" "$BRANCH"

PROXY=""
if [[ "$(scutil --proxy | awk '/HTTPSEnable/ {print $3}')" == "1" ]]; then
  PROXY="http://$(scutil --proxy | awk '/HTTPSProxy/ {print $3}'):$(scutil --proxy | awk '/HTTPSPort/ {print $3}')"
fi
git -C "$REPO" ${PROXY:+-c http.proxy="$PROXY"} push -q origin "$BRANCH"
echo "    已推到 GitHub：$(git -C "$REPO" log --oneline -1)"

# 5. 同步到 Gitee（国内直连，不走代理；失败只提示，不影响 GitHub 备份）
if git -C "$REPO" remote get-url gitee >/dev/null 2>&1; then
  if GIT_TERMINAL_PROMPT=0 git -C "$REPO" push -q gitee "$BRANCH"; then
    echo "    已推到 Gitee"
  else
    echo "    !! 推送 Gitee 失败（凭据失效？手动跑一次 git push gitee ${BRANCH} 重新登录）" >&2
  fi
fi
