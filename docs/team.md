# 团队互查：在飞书里问同事最近和 AI 聊到哪了（Mac）

> **测试中（2026-11-26）**：Mac 版代码已经做好，本机采集和后台服务已实测；Tailscale 已装好；登录团队网络、和 Windows 互查还没在 Mac 上实测（见文末「测试记录」）。标「待实测」的地方是推断。

装好以后，你在自己的飞书机器人里问「张三最近三天和 AI 在做什么」，机器人会去张三的电脑上查他共享的 AI 聊天记录，带时间和出处回答。**Mac 和 Windows 在同一个团队网络里，可以互相查**，规则和 Windows 版完全一样（见 Windows 版教程 `agentos-windows/docs/team.md`）。

```text
你的飞书 → 你的机器人（Mac 上在 agentos 账号里干活）→ team_chat_query.py
                              ↓ Tailscale 团队网络（加密，只有网络里的人能连）
                     张三电脑上的查询服务（只读）
                              ↓
                     张三本机的 AI 聊天库（每 10 分钟自动采集）
```

**全团队统一规则（和 Windows 一样）**

- 共享的内容：本机采到的所有 AI 软件聊天：WorkBuddy、Claude Code、Codex、Grok Bot。微信、邮件、飞书不在共享范围。
- 时间范围：别人最多查到你最近 15 天。
- 平时只把搜到的几条（每次最多 20 条）传过去；对方**明确要某个话题的全部对话**时，才把相关会话整段传过去，整理成 Word，截图嵌在 Word 里；你发给 AI 的文件只写名字，他点名要某个文件（PDF、Word、PPT、Excel 等，20MB 以内），才把原件发给他；zip 等其他文件只有名字。
- 每次被查都记下来，`status` 能看到是谁查的。

---

## 先看懂：Mac 和 Windows 哪里不一样

Mac 版 AgentOS 有两个账号，团队互查要分在两边：

| | 你自己的账号 | agentos 账号（隐藏） |
|---|---|---|
| 在这里的东西 | 你平时用的 AI 软件和它们的聊天记录 | 机器人的 AI 在这里干活 |
| 团队互查在这里做什么 | 采集你的 AI 聊天；运行查询服务，让别人来查你 | 你在飞书里问时，去查别人 |

所以 Tailscale 必须**两个账号都能用**。我们用 Tailscale 的**开源命令行版**，不用 App Store 或官网下载的 App：

- 开源版装成系统服务，**开机就连上**，不用等谁登录桌面（相当于 Windows 上勾的 Run unattended）。
- App 版只在你登录后运行；agentos 账号能不能用它的命令行，官方没写，很可能不行。
- 代价：开源版没有图形界面，全靠命令。下面每条命令都写清楚了。

依据：[Tailscale 的三种 Mac 版本](https://tailscale.com/kb/1065/macos-variants)（开源版「Run before login: yes」，App 版是 no）。

---

## 第一步（管理员做一次）：邀请他进团队网络

和 Windows 一样：管理员在 Tailscale 后台 → **Users** → **Invite users**，填他的邮箱。免费版一个网络最多 6 人。

**成功的样子**：他的邮箱里收到邀请。

## 第二步（本人，一次）：装 Tailscale 开源版，加入网络

先检查「应用程序」里有没有 Tailscale。有的话先在菜单栏退出它，再把它拖进废纸篓。两种版本不能同时装。

**1. 安装**

```bash
brew install tailscale
```

- 做什么：用 Homebrew 装 Tailscale 的命令行版（装 AgentOS 时已经装过 Homebrew）。
- 成功的样子：最后没有红色的 Error。

**2. 装成开机自动运行的系统服务**

```bash
sudo brew services start tailscale
```

- 做什么：让 Tailscale 开机就在后台运行，谁登录都不影响。要输开机密码，输的时候屏幕上不显示，输完回车。
- 成功的样子：`Successfully started tailscale`。

**国内网络必做：让 Tailscale 走代理**

```bash
sudo ~/AgentOS/ops/tailscale-proxy.sh 代理端口
```

- 为什么：开源版是系统服务，不读 Mac「系统设置」里的代理。国内直连 Tailscale 官方服务器会超时，下一步就会一直卡住，不出登录网址。
- 做什么：只让 Tailscale 连官方服务器时走你的代理（端口和装 AgentOS 时 git 用的同一个，例如 7890）。成员之间的连接、本机查询服务不走代理。
- 成功的样子：`✅ Tailscale 已改为经 127.0.0.1:端口 连官方服务器`。
- 以后运行过 `brew upgrade tailscale` 或 `brew services restart tailscale`，要再运行一次这条。

**3. 加入团队网络**

```bash
sudo tailscale up --operator=$(whoami)
```

- 做什么：把这台 Mac 加进团队网络。屏幕上会出现一个 `https://login.tailscale.com/...` 的网址，复制到浏览器打开，用**收到邀请的那个账号**登录，选加入管理员的网络。
- `--operator=$(whoami)` 是什么：让你自己的账号以后不用 sudo 就能打开、关闭共享。
- 成功的样子：浏览器里显示 Success；终端里命令自己结束。
- 本人不在电脑旁也行：把网址发给他，他在自己的手机或电脑浏览器里打开登录，效果一样。
- 一直没出网址：多半是上一小步的代理没设好。按 Ctrl+C 停掉，看 `tail -5 /opt/homebrew/var/log/tailscaled.log`，有 `context deadline exceeded` 就是连不上官方服务器。

**4. 检查**

```bash
tailscale status
```

- 成功的样子：列出团队里的其他电脑（同事的 Windows、Mac），后面不是 offline。

**代理提示**：如果代理软件开了 TUN / 增强模式，可能把团队网络的流量抢走。在代理规则里把 `*.ts.net` 和 `100.64.0.0/10` 设成「直连」。

## 第三步（本人，一次）：拉更新、重跑安装

```bash
git -C ~/AgentOS pull --no-rebase --no-edit upstream main
```

```bash
~/AgentOS/ops/install-mac.sh
```

- 做什么：拿到带团队互查的新版，装上「每 10 分钟采集 AI 聊天」的定时任务，并当场先采一次（往回读 30 天）。新规则会同步给机器人。
- 成功的样子：安装过程中有一行 `==> 本机 AI 聊天：先采一次`，下面列出各软件采到的会话数。

## 第四步：看看采到了哪些会话

```bash
python3 ~/AgentOS/ops/team_chat_server.py sessions
```

- 做什么：列出你的 AI 会话：软件、编号、条数、最近时间、你说的第一句话。打开共享前先看一眼，不想给别人看的会话记下编号，第五步之后用 `hide` 藏起来。
- 成功的样子：能看到 workbuddy、claude、codex、grokbot 开头的若干行。哪个软件一行都没有，说明这台电脑上没用过它。
- 第三步的采集如果报错，手动再采一次：`python3 ~/AgentOS/ops/collect_ai_chats.py`。它只读聊天文字，不读账号和密码。

## 第五步：打开共享

```bash
python3 ~/AgentOS/ops/team_chat_server.py on --name "你的名字"
```

- 做什么：在你的账号里启动只读查询服务，并让 Tailscale 给它挂一个团队网络地址。以后每次登录都会自动运行。
- 成功的样子：`✅ 已打开共享`，下面有 `你的地址：https://你的电脑名.xxx.ts.net`。
- 名字写你的真名，别人在飞书里就用这个名字找你。

## 第六步：在飞书里问

1. 给自己的机器人发「**新对话**」，让它读到新规则。
2. 问：「团队里现在谁能查？」
3. 问：「查一下张三最近三天和 AI 聊了什么」。

**成功的样子**：
- 第 2 问的回复里有团队成员的名字，以及在线、共享的状态。
- 第 3 问的回复里有软件名、消息时间和 `evidence_id`。

另外，请一位 Windows 的同事在他的飞书里查你一次，确认反方向也通。

---

## 自己怎么控制

| 想做什么 | 命令 |
|---|---|
| 看现在共享了什么、**最近谁查过我** | `python3 ~/AgentOS/ops/team_chat_server.py status` |
| 列出我的会话（编号 + 我说的第一句话） | `python3 ~/AgentOS/ops/team_chat_server.py sessions` |
| 某个会话不给别人看（立刻生效） | `python3 ~/AgentOS/ops/team_chat_server.py hide 会话编号` |
| 恢复共享这个会话 | `python3 ~/AgentOS/ops/team_chat_server.py unhide 会话编号` |
| 改成只让别人查最近 7 天 | `python3 ~/AgentOS/ops/team_chat_server.py on --days 7` |
| **关掉共享，谁都查不了我** | `python3 ~/AgentOS/ops/team_chat_server.py off` |

已经被别人查到、看过的内容收不回来。

## 排错

| 现象 | 先查什么 |
|---|---|
| `sudo tailscale up` 一直不出登录网址 | 连不上官方服务器：运行 `tailscale-proxy.sh`（第二步），确认代理软件开着 |
| `tailscale status` 说没在运行 | `sudo brew services restart tailscale`；还不行看 `sudo brew services info tailscale` |
| 别人说你「不在线」 | Mac 睡眠或关机了。系统设置 → 电池（或节能）→ 打开「接通电源时防止自动睡眠」 |
| 别人说你「关掉了共享」，可你没关 | 重启后还没登录账号：Mac 上查询服务要登录后才运行，登录一次就好 |
| 机器人说「找不到 Tailscale」 | 先确认第二步装的是开源版（`/opt/homebrew/bin/tailscale` 存在），不是 App 版 |
| 能 `tailscale status`，但查别人一直「连不上」 | 多半是代理的 TUN 模式抢了流量，见第二步的代理提示 |

## 这台 Mac 上不止一个人用 AI 时

采集读的是你自己账号里的 AI 软件记录。如果别人（比如帮你装机、做开发的人）也在这个账号里用过 Claude Code、WorkBuddy 等，那些对话会一起算在你名下共享。打开共享前，用第四步的 `sessions` 看一遍，不想给别人看的用 `hide` 藏起来。

还有一点：你的机器人进了团队网络，你在飞书里也能查团队里的每个人。

---

## 测试记录

| 日期 | 测了什么 | 结果 |
|---|---|---|
| 2026-11-26 | 一台在用的 Mac 上采集（写进临时目录，没动正在用的知识库） | 通过：WorkBuddy 108 个会话文件、Claude Code 114 个、Grok Bot 14 个，约 3 秒；Codex 本机没用过 |
| 2026-11-26 | launchd 拉起查询服务、`off` 时卸掉 | 通过：本机 `/health` 有回应，卸掉后不再运行 |
| 2026-11-26 | 装 Tailscale 开源版（1.104.7）；agentos 账号能不能用 `tailscale status` | 通过：装成开机系统服务（/Library/LaunchDaemons），控制接口对所有账号开放，两个账号都能运行 `tailscale status`（未登录时显示 Logged out.） |
| — | Mac 登录 Tailscale 后，和 Windows 在飞书里互查 | 待测 |
