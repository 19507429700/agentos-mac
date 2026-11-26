#!/bin/bash
# 让 Tailscale 开源版走代理连它的官方服务器：sudo ~/AgentOS/ops/tailscale-proxy.sh 代理端口
# 为什么要：开源版是系统服务，不读 Mac「系统设置」里的代理；国内直连官方服务器会超时，
#   表现是 `sudo tailscale up` 一直不出登录网址，日志里反复 context deadline exceeded。
# 做什么：在 sudo brew services start tailscale 生成的服务配置里写上代理，再重启服务。
#   团队成员之间的连接、本机的查询服务不走代理（NO_PROXY）。
# 注意：brew services restart tailscale、brew upgrade tailscale 会重写这个配置，之后要再运行一次本脚本。
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "要用 sudo 运行：sudo $0 ${1:-代理端口}" >&2; exit 1; }
PORT="${1:-}"
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "写上代理端口（和装 AgentOS 时 git 用的同一个），例如：sudo $0 7890" >&2; exit 1; }
PLIST=/Library/LaunchDaemons/sh.brew.tailscale.plist
LABEL=sh.brew.tailscale
[[ -f "$PLIST" ]] || { echo "没找到 ${PLIST}：先运行 sudo brew services start tailscale" >&2; exit 1; }
nc -z -w 2 127.0.0.1 "$PORT" || { echo "127.0.0.1:$PORT 上没有代理：先打开代理软件，确认端口" >&2; exit 1; }

PB=/usr/libexec/PlistBuddy
"$PB" -c "Delete :EnvironmentVariables" "$PLIST" 2>/dev/null || true
"$PB" -c "Add :EnvironmentVariables dict" "$PLIST"
for key in HTTPS_PROXY HTTP_PROXY; do
  "$PB" -c "Add :EnvironmentVariables:$key string http://127.0.0.1:$PORT" "$PLIST"
done
"$PB" -c "Add :EnvironmentVariables:NO_PROXY string localhost,127.0.0.1,::1,.ts.net,100.64.0.0/10" "$PLIST"
plutil -lint "$PLIST" >/dev/null

launchctl bootout "system/$LABEL" 2>/dev/null || true
# bootout 是异步的，没退干净就 bootstrap 会报 Input/output error
for _ in {1..20}; do launchctl print "system/$LABEL" &>/dev/null || break; sleep 0.5; done
launchctl bootstrap system "$PLIST"
echo "✅ Tailscale 已改为经 127.0.0.1:$PORT 连官方服务器，服务已重启。"
echo "   下一步：sudo tailscale up --operator=$(stat -f %Su /dev/console)，几秒内应出现登录网址。"
