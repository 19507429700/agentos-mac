#!/bin/bash
# 把 AI 底座换成 DeepSeek（不用 Claude 订阅、不用代理）。在你自己的账号里运行（要输一次开机密码）：
#   sudo -u agentos -H ~/AgentOS/ops/use-deepseek.sh
# 做的事：在 agentos 的 ~/.env 里注释掉 Claude 令牌，写入 DeepSeek 官方推荐的 Claude Code 配置
# （https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code ）。原文件先备份。
# 模型全部用 deepseek-flash：它能看图；deepseek-v4-pro 看不了图（图会变成 [Unsupported Image]）。
# 可以重复运行（换密钥时再跑一次）。
set -euo pipefail

[[ "$(id -un)" == agentos ]] || { echo "要以 agentos 身份运行：sudo -u agentos -H $0" >&2; exit 1; }
cd "$HOME"
ENV="$HOME/.env"
touch "${ENV}"

read -rs -p "粘贴 DeepSeek API 密钥（屏幕上不显示，是正常的），按回车：" KEY; echo
KEY="$(printf '%s' "${KEY}" | tr -d '[:space:]')"
[[ -n "${KEY}" ]] || { echo "没收到密钥，什么都没改" >&2; exit 1; }

cp "${ENV}" "${ENV}.bak.$(date +%Y%m%d%H%M%S)"
TMP="$(mktemp)"
# 去掉旧的底座设置（包括上次写的 DeepSeek 段），Claude 令牌改成注释
grep -vE '^(ANTHROPIC_[A-Z_]+|CLAUDE_CODE_SUBAGENT_MODEL|CLAUDE_CODE_EFFORT_LEVEL|CLAUDE_CODE_AUTO_COMPACT_WINDOW)=|^# 底座：DeepSeek' "${ENV}" \
  | sed -E 's/^CLAUDE_CODE_OAUTH_TOKEN=/#CLAUDE_CODE_OAUTH_TOKEN=/' > "${TMP}" || true
# DeepSeek 国内直连：不走代理（代理软件关了也能用）
if grep -qE '^NO_PROXY=' "${TMP}"; then
  grep -qE '^NO_PROXY=.*api\.deepseek\.com' "${TMP}" || sed -i '' -E 's/^NO_PROXY=(.*)$/NO_PROXY=\1,api.deepseek.com/' "${TMP}"
else
  echo 'NO_PROXY=localhost,127.0.0.1,api.deepseek.com' >> "${TMP}"
fi
cat >> "${TMP}" <<EOF

# 底座：DeepSeek（ops/use-deepseek.sh 写入；换回 Claude 就删掉这一段，去掉上面令牌行前的 #）
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_AUTH_TOKEN=${KEY}
ANTHROPIC_MODEL=deepseek-flash[1m]
ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-flash[1m]
ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-flash[1m]
ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-flash
CLAUDE_CODE_SUBAGENT_MODEL=deepseek-flash
CLAUDE_CODE_EFFORT_LEVEL=max
CLAUDE_CODE_AUTO_COMPACT_WINDOW=786432
EOF
install -m 600 "${TMP}" "${ENV}"
rm -f "${TMP}"
unset KEY
echo "已写好 ${ENV}（旧文件备份在 ${ENV}.bak.*）。回到你自己的账号运行 ~/AgentOS/ops/check-agent.sh 验证。"
