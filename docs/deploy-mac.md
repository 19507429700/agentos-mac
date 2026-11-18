# AgentOS 安装教程：Mac

照着从上往下做。每一步都在**你自己的账号**的「终端」里运行（启动台 → 其他 → 终端）。代码块里的命令**一次复制一条**，粘贴到终端，回车。

核心只有一条安装脚本，**可以反复运行**：每填好一样钥匙，就再跑一次，它会把能装的装上，已经装好的不会弄坏。

```bash
~/AgentOS/ops/install-mac.sh
```

---

## 先看懂：它在 Mac 上怎么跑

- **手机上的飞书**是遥控器：你给机器人发消息派活，回复推回手机。
- **这台 Mac** 一直开着、插着电，上面跑着：飞书机器人（收消息、叫醒 AI）、每 10 分钟一次的采集（飞书、邮件、微信、讯飞录音）、每晚 23:00 的复盘、每天 03:00 的知识库备份。
- **安全上的设计**：AI 跑在一个隐藏的系统账号 `agentos` 里，它干活的地方是 `/Users/agentos/agentos`（运行副本）。你的钥匙都在**你自己账号**的 `~/.agentos` 里，`agentos` 账号**从系统层面就读不到**。AI 不能直接给任何人发消息、发邮件，对外的事都要你在飞书卡片上点头。
- 代码在 `~/AgentOS`；采集的原文（聊天、邮件……）只存在这台电脑上，不上传；知识库（画像、人物、项目、复盘）每天备份到**你自己的** GitHub 私有仓库。

装完大约 **1～2 小时**，大部分时间花在飞书开放平台点权限上。

---

## 第零步：准备

**电脑**
- 一台 Mac，最好是 Apple 芯片（M1 以后）。Intel 的 Mac 要改几处 `/opt/homebrew` 路径，先别用。
- 这台 Mac 的**开机密码**（装的时候要用一次）。
- **一直开着、插着电**：系统设置 → 电池（或「节能」）→ 打开「插电时防止自动睡眠」。笔记本合盖会睡，要开着盖。
- 在国内要有**代理软件**（连 Claude、GitHub 用），**装之前就打开**，并在代理软件里打开「设置为系统代理」。

**账号**（全部用你自己的）
- **Claude** 的 Pro 或 Max 订阅（当 AI 底座）。不想用 Claude，可以用 DeepSeek 等的 API 密钥，见最后「底座怎么选」。
- **飞书**：能登录飞书开放平台 https://open.feishu.cn （个人也能在自己的组织里建应用）。
- **邮箱**（可选）：QQ 或 163 邮箱的 IMAP **授权码**（邮箱网页版「设置」里生成，不是登录密码）。
- **GitHub**：一个空的**私有**仓库，放你自己的知识库备份（比如叫 `my-agentos`）。
- 可选：微信（第十三步）、讯飞录音笔（第十五步）、PushPlus 和 healthchecks.io（第十一步告警）。

---

## 第一步：装软件

先装苹果的命令行工具（自带 git）。弹窗点「安装」，等它装完：

```bash
xcode-select --install
```

再装 **Homebrew**：打开 https://brew.sh ，把首页那一行命令复制到终端运行（要输开机密码）。装完它会提示运行两三行 `echo … >> ~/.zprofile` 之类的命令，**照着运行**，然后**关掉终端重新打开**。

检查一下，能显示版本号就好：

```bash
brew --version
```

其他软件（Python 3.14、uv、sqlcipher、LibreOffice）第三步的安装脚本会自动装，不用管。

---

## 第二步：拿代码，设好两个仓库

国内连 GitHub 慢或者连不上，先让 git 走代理（端口换成你代理软件里写的，常见 7890）：

```bash
git config --global http.proxy http://127.0.0.1:7890
```

拿代码。**必须放在 `~/AgentOS`**，安装脚本按这个位置找。模板仓库是私有的话，先让作者把你的 GitHub 账号加为协作者：

```bash
git clone https://github.com/19507429700/agentos-mac.git ~/AgentOS
```

把模板仓库改名叫 `upstream`（以后从这里拉更新），再把 `origin` 设成**你自己的私有仓库**（知识库每天备份到这里）：

```bash
git -C ~/AgentOS remote rename origin upstream
```

```bash
git -C ~/AgentOS remote add origin https://github.com/你的账号/你的私有仓库.git
```

```bash
git -C ~/AgentOS push -u origin main
```

> 最后一条会弹出 GitHub 登录，按提示在浏览器里登录授权。
> 不设自己的仓库也能用，只是知识库不备份。安装脚本会自动检查：`origin` 还是模板仓库时，**绝不会**把你的知识库推上去。

---

## 第三步：运行安装脚本

**先确认代理软件开着**，然后：

```bash
~/AgentOS/ops/install-mac.sh
```

中间会让你输一次**开机密码**（屏幕上不显示，是正常的）。它会：
1. 用 Homebrew 装 Python 3.14、uv、sqlcipher、LibreOffice（LibreOffice 约 1GB，第一次要等一会儿）；
2. 建隐藏账号 `agentos`、运行副本 `/Users/agentos/agentos`、令牌文件，配好免密规则，以 agentos 身份装 Claude Code；
3. 生成空白配置 `~/.agentos/bridge.env`、`~/.agentos/mail.env`，装好飞书机器人（还没填钥匙，所以先不启动）；
4. 装上「提取文字」定时任务；其他的（飞书、邮件、微信……）会写「跳过」和原因，后面填好钥匙再跑一次就会装上。

只要**没有红色的报错**，就往下走。

---

## 第四步：填 Claude 令牌

切到 agentos 账号（要输开机密码）：

```bash
sudo -u agentos -i
```

在 agentos 的终端里，先让它用上代理设置，再生成一年期令牌：

```bash
set -a; . ~/.env; set +a
```

```bash
~/.local/bin/claude setup-token
```

浏览器里登录 Claude 并同意，终端会打印一串 `sk-ant-oat01-` 开头的令牌，复制下来。然后运行下面这一整行，**粘贴令牌、回车**（屏幕上不显示，是正常的）：

```bash
read -s "T?粘贴令牌后按回车："; echo; grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' ~/.env && sed -i '' "s|^CLAUDE_CODE_OAUTH_TOKEN=.*|CLAUDE_CODE_OAUTH_TOKEN=$T|" ~/.env || echo "CLAUDE_CODE_OAUTH_TOKEN=$T" >> ~/.env; chmod 600 ~/.env; unset T; grep -c '^CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat' ~/.env
```

显示 `1` 就成功了。回到自己的账号：

```bash
exit
```

检查底座通了没有，应该看到 `Claude 回复：OK`：

```bash
~/AgentOS/ops/check-agent.sh
```

> 报 `403`、`连不上`：代理没开，或者第三步时代理没开（令牌文件里没写代理）。打开代理后重跑第三步的安装脚本，再做这一步。

---

## 第五步：飞书应用（第一部分）

打开飞书开放平台 https://open.feishu.cn → 开发者后台 → 创建「**企业自建应用**」（名字随便，比如 agentos）：
- 添加应用能力 → 「**机器人**」；
- 权限管理 → 开通权限，切到「**应用身份权限**」，搜索并勾上：`im:message.p2p_msg:readonly`、`im:message:send_as_bot`、`im:resource`、`im:message:readonly`（最后这个用来下载你发给机器人的图片和文件）；
- 记下「凭证与基础信息」里的 **App ID** 和 **App Secret**。

> 已经有一台电脑在跑 AgentOS（比如 Windows 版）：这里要**另建一个新应用**，不要两台电脑共用一个机器人，否则飞书会把消息随机交给其中一台。

---

## 第六步：填飞书钥匙，启动机器人

用「文本编辑」打开配置：

```bash
open -e ~/.agentos/bridge.env
```

把 `FEISHU_APP_ID=`、`FEISHU_APP_SECRET=` 后面填上第五步记下的值（等号后面直接写，不要空格、不要引号），保存（⌘S），关掉。再跑一次安装脚本：

```bash
~/AgentOS/ops/install-mac.sh
```

看到 `state = running` 就是机器人启动了。

---

## 第七步：飞书应用（第二部分）——必须在第六步之后

机器人连上飞书之后，开放平台才能保存「长连接」设置：
- 事件与回调 → 事件配置 → 订阅方式选「**使用长连接接收事件**」→ 添加事件 `im.message.receive_v1`（接收消息）；
- 事件与回调 → 回调配置 → 同样选长连接 → 添加「**卡片回传交互**」（发邮件前的确认卡片要用）；
- 版本管理与发布 → 创建版本 → 发布。

---

## 第八步：绑定你自己

在手机飞书里搜到这个机器人，随便发一句。它会回一串 `ou_` 开头的 open_id。打开配置：

```bash
open -e ~/.agentos/bridge.env
```

填进 `OWNER_OPEN_ID=`，保存，再跑一次安装脚本：

```bash
~/AgentOS/ops/install-mac.sh
```

之后机器人只听你一个人的；每日复盘也会装上。

---

## 第九步：飞书采集（读你的聊天、文档、日程）+ 写飞书文档

开放平台 → 权限管理 → 开通权限，切到「**用户身份权限**」，开下面这些：

`offline_access`、`im:message:readonly`、`im:message.p2p_msg:get_as_user`、`im:message.group_msg:get_as_user`、`im:chat:readonly`、`search:message`、`contact:user.base:readonly`、`contact:contact.base:readonly`、`docx:document:readonly`、`wiki:wiki:readonly`、`calendar:calendar:readonly`、`minutes:minutes.transcript:export`、`docs:document.media:download`、`sheets:spreadsheet:readonly`、`bitable:app:readonly`、`drive:drive:readonly`、`docx:document`、`docx:document.block:convert`、`docs:document.media:upload`

最后三项是让机器人能**建飞书文档、往里补内容**；不想用可以不开。

安全设置 → 重定向 URL 加：`http://localhost:18080/feishu/callback`。发布新版本，审批通过后授权（会自动打开浏览器，登录、点「授权」）：

```bash
python3 ~/AgentOS/ops/feishu_auth.py
```

看到 `✅ 授权成功`，并且下面**没有** `⚠️ 以下权限没有授予` 就对了。再跑一次安装脚本，装上飞书采集：

```bash
~/AgentOS/ops/install-mac.sh
```

> 以后每次新开权限，都要**重新运行 `feishu_auth.py`**，新权限才生效。

**写飞书文档**（开了最后三项就能用）：在飞书里说「建一个飞书文档，写上……」「往那篇文档里补上……」，AI 写好内容，机器人**以你本人身份**建在你的飞书云盘里，把链接发给你。
- 试一下：发「建一个飞书文档，标题叫测试，写三条今天的待办」，过一会儿收到「📄 已建好飞书文档《测试》：链接」。
- 想建在某个文件夹里：浏览器打开那个文件夹，复制网址里 `/folder/` 后面那串字符，`open -e ~/.agentos/bridge.env` 加一行 `FEISHU_DOC_FOLDER=那串字符`，再运行 `~/AgentOS/ops/deploy.sh`。不设就建在「我的空间」根目录。
- 只往**机器人自己建的**文档里补内容，只加在末尾；你原有的文档不会去改。新文档默认只有你能看。

---

## 第十步：邮箱（可选）

先在邮箱网页版里打开 IMAP、生成**授权码**（QQ 邮箱：设置 → 账号 → POP3/IMAP 服务 → 开启 → 生成授权码；163 邮箱：设置 → POP3/SMTP/IMAP → 开启 IMAP）。然后打开配置：

```bash
open -e ~/.agentos/mail.env
```

填三项：`MAIL_IMAP_HOST=`（QQ 邮箱填 `imap.qq.com`，163 邮箱填 `imap.163.com`）、`MAIL_USER=`（邮箱地址）、`MAIL_PASSWORD=`（授权码）。保存，再跑一次安装脚本：

```bash
~/AgentOS/ops/install-mac.sh
```

看到 `登录 imap.qq.com 成功` 和「之后每 10 分钟自动拉」就好了。邮箱也用来发信：AI 写好邮件草稿，飞书弹卡片，你点「发送」才用这个邮箱发出。

---

## 第十一步（可选）：告警

**PushPlus**（告警和每日复盘也推到微信；实名认证约 10 元）：在 https://www.pushplus.plus 微信扫码登录、实名，复制「一对一推送」的 token，`open -e ~/.agentos/bridge.env` 加一行 `PUSHPLUS_TOKEN=那串token`，保存。

**healthchecks.io**（电脑关机、断网时发邮件提醒，免费）：在 https://healthchecks.io 注册，每个任务建一个检查（Period 10 分钟、Grace 1 小时；复盘和备份是 Period 1 天、Grace 3 小时），复制打卡地址，写进 `~/.agentos/healthchecks.env`，一个任务一行：

```
HC_COLLECT_MAIL=https://hc-ping.com/…
HC_COLLECT_FEISHU=https://hc-ping.com/…
HC_EXTRACT_TEXT=https://hc-ping.com/…
HC_DAILY_REVIEW=https://hc-ping.com/…
HC_PUSH_KB=https://hc-ping.com/…
```

（做了微信、讯飞的，再加 `HC_COLLECT_WECHAT`、`HC_FETCH_WECHAT_ARTICLES`、`HC_COLLECT_IFLYREC`。）不想建这么多，至少建邮件采集或飞书采集一个。

---

## 第十二步：验收

- 手机飞书发「介绍一下你能做什么」，一分钟内有回复；
- 发一段自我介绍、常打交道的人、正在跟的项目，说「整理进我的画像、人物页和项目页」；
- 发一张图片或一个 PDF，问它是什么；
- 当晚 23:00 收到第一份复盘。

到这里主要功能就齐了。下面几步是可选的。

---

## 第十三步（可选）：微信聊天记录

做完这一步，AI 能读这台 Mac 上登录的微信里的私聊和你选的几个群，每 10 分钟存进知识库，语音会在本机转成文字。

**先知道这几件事：**
- **只读这台电脑上你自己登录的微信**，不发消息、不改微信。读不到手机上有、电脑上没同步的历史。
- 做法是解密微信存在电脑里的聊天库，**违反微信用户协议，有小概率封号**；只适合个人自用。
- 微信在电脑上要**登录着、开着**。

**1. 取钥匙**（用开源工具 macos-wechat-export，大约 20 分钟）：

```bash
git clone https://github.com/DaneelOlivaw1/macos-wechat-export.git ~/wechat-tool
```

```bash
cd ~/wechat-tool && sh build.sh
```

（编译时「发消息、操控界面」那部分报错可以不管，用不到。）找出你账号的数据库位置（登录过多个微信号时，按最近修改时间认）：

```bash
cd ~/wechat-tool && python3.14 disk_inventory.py
```

**先在微信里正常退出**，再取钥匙（中途手机上可能要确认一次登录）：

```bash
cd ~/wechat-tool && python3.14 bootstrap_keys.py --acknowledge-debug-copy
```

验证（能列出和「文件传输助手」的最近几条就成功了）：

```bash
cd ~/wechat-tool && python3.14 wechat_db.py verify
```

**2. 写配置**：

```bash
open -e ~/.agentos/wechat.env
```

（文件不存在就先运行 `touch ~/.agentos/wechat.env` 再打开。）写这几行，第一行换成上面找到的路径：

```
WECHAT_DB_ROOT=/Users/你的用户名/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/你的账号目录/db_storage
WECHAT_KEYS=~/wechat-tool/.wechat-local/keys.json
WECHAT_TOOL=~/wechat-tool
# 私聊全采；群只采这几个（群名关键词，逗号分隔）
WECHAT_GROUPS=
WECHAT_INITIAL_DAYS=3
```

**3. 再跑一次安装脚本**：装上微信采集、公众号文章抓取，下载语音转文字的模型（约 460MB，只下一次）：

```bash
~/AgentOS/ops/install-mac.sh
```

**4. 给微信采集开「完全磁盘访问权限」**（不开的话每 10 分钟弹一次「想访问其他 App 的数据」）：系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 点 + → 按 ⌘⇧G，粘贴 `~/.agentos/wechat-python/bin/python3.14` → 打开。**只加这一个**，不要把平时用的 python3.14 加进去。

要知道的：
- 语音会写成「[语音 14秒] 转出的文字」，只能转电脑上有音频的语音，没有的只留「[语音]」；在本机转写，不上传。不想要：`wechat.env` 加一行 `WECHAT_VOICE=0`。
- 微信「退出登录」、重装、大版本升级后钥匙会失效，日志里会写「打开微信库失败」，重做第 1 步。关微信、重启电脑不影响。
- 群消息很吵，**群只采你点名的**。
- 工具里「发消息、操控微信」的脚本一律不碰。

---

## 第十四步：公众号文章

做了第十三步就已经装好了。聊天里出现的公众号文章，每 10 分钟抓一次正文（连图片），存进 `raw/wechat/articles/`，之后问「我存过哪些公众号文章」「总结一下那篇讲 XX 的文章」，AI 能读全文。

抓正文用的是开源工具（伪装成微信客户端绕过「环境异常」验证），**用不用由你决定**；不想用，在微信里把文章转发给飞书机器人也行。

---

## 第十五步（可选）：讯飞录音笔

用讯飞录音笔（讯飞听见 App）录的会议和谈话，接进来后每 10 分钟把新录音的「讯飞生成的总结」和「带发言人的转写」存进知识库，能问、能进复盘。只有文字，不存声音。

```bash
~/AgentOS/ops/install-iflyrec.sh
```

它下载讯飞官方的只读客户端（逐个核对指纹），给出一个授权链接。浏览器打开链接，核对用户码，用**录音笔绑定的讯飞账号**登录、点同意，再按它最后提示的命令确认，看到 `"authenticated": true` 就好了。然后：

```bash
~/AgentOS/ops/install-mac.sh
```

第一次往回取 30 天，每轮最多 15 条。刚录完的要等讯飞转写好（十几分钟到一小时）才进来。授权失效时日志会写「授权失效」，重跑上面第一条。

---

## 附：开发模式（可选，最高权限）

在飞书里发「开发：……」，机器人就在这台 Mac 上以**你本人账号**运行 Claude Code，**跳过所有权限确认**：能改代码、执行任何命令、操作电脑上的软件、截屏，文件会发回手机。平时的消息照旧走受限的助理。

- `开发：会话`：列出电脑上最近的 Claude 会话；`开发：接着 2 ……`：接着第 2 个干；`开发：新任务 ……`：新开；`开发：结束`：下次新开。
- 第一次用前，命令行要登录一次（国内要走代理，端口换成你的）：

```bash
HTTPS_PROXY=http://127.0.0.1:7890 ~/.local/bin/claude auth login
```

  再 `open -e ~/.agentos/bridge.env` 加一行 `DEV_PROXY=http://127.0.0.1:7890`，运行 `~/AgentOS/ops/deploy.sh`。
- 让它操作 Word、Excel 这类软件时，Mac 第一次会弹「想要控制……」，要在电脑前点「好」。
- **这等于把整台电脑交给飞书里的你**：谁拿到你的飞书账号，谁就能让它做任何事。不用时在 `bridge.env` 里写 `DEV_MODE=0`，再运行 `deploy.sh`。

---

## 底座怎么选

底座就是「真正干活的那个 AI」。有三种，机器人、采集、复盘都不用动，只换 agentos 账号里 `~/.env` 的钥匙。**本教程第四步用的是第一种。**

- **A. Claude 订阅**（默认，第四步）：效果最好；要 Pro 或 Max 订阅，国内要代理。
- **B. DeepSeek 等其他公司的接口**：Claude Code 不换，只让它去调别家的模型。国内直连、按量付费，效果要拿真实任务比一比。做法：`sudo -u agentos -i` 切到 agentos，`nano ~/.env`，把 `CLAUDE_CODE_OAUTH_TOKEN=` 那行前面加 `#`，加上三行（以厂商文档为准，DeepSeek 见文档里「Anthropic API」那页）：

```
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_MODEL=文档里的模型名
ANTHROPIC_AUTH_TOKEN=你的API密钥
```

  保存（⌃O 回车、⌃X），`exit`，运行 `~/AgentOS/ops/check-agent.sh` 验证。
- **C. WorkBuddy（腾讯的 CodeBuddy Code）**：用腾讯的 API 密钥，国内直连。**Mac 版还没接上**（Windows 版已经能用，在 `agent.env` 里写 `AGENT_ENGINE=codebuddy`）。要注意：WorkBuddy 桌面 App 本身不能当底座，要的是它的命令行 `codebuddy`（`npm install -g @tencent-ai/codebuddy-code`），密钥在 https://copilot.tencent.com/profile/ 生成。Mac 上要用，先找作者把这一项接上。

---

## 日常和排错

- **日志**都在 `~/.agentos/logs/`：`bridge.log`（机器人）、`collect-mail.log`、`collect-feishu.log`、`daily-review.log` 等。看最后几行：`tail -50 ~/.agentos/logs/bridge.log`
- **拉更新**（模板有新版本时）：

```bash
git -C ~/AgentOS pull --no-edit upstream main
```

```bash
~/AgentOS/ops/install-mac.sh
```

- **机器人没反应**：先看 `bridge.log` 最后几行；再跑 `~/AgentOS/ops/check-agent.sh` 看底座通不通。
- **令牌失效**（机器人突然不回、复盘写不出来，日志里有 `OAuth token revoked`、`401`）：重做第四步。
- **代理没开或换了端口**：Claude 连不上。打开代理；端口变了就 `sudo -u agentos -i` 后 `nano ~/.env` 改 `HTTPS_PROXY`、`HTTP_PROXY` 两行。
- **电脑重启后**：要登录一次你的账号，机器人和定时任务才会开始跑。
- **断网、关机过**：采集会自动补齐；当晚没出的复盘可以手动补：`~/AgentOS/ops/daily-review.sh 2026-11-18`。
- **飞书新开了权限没反应**：重新运行 `python3 ~/AgentOS/ops/feishu_auth.py`。
- **采集日志里「新存 0 条」**：正常，定时任务每 10 分钟采一次，新消息早被采走了。
- **「文档：新存 N 份，读不了 M 份」**：读不了的多半是别人的文档没分享给你、已删除，或者云盘里上传的 PDF/Word 文件。具体哪几份、为什么，看 `collect-feishu.log` 里「读不了：标题（原因）」。
- **知识库不要在 `~/AgentOS` 里直接改**：它是 AI 在运行副本里写的，要改就在飞书里让机器人改，否则同步时会冲突。

---

## 测试记录（请照着填，发给作者）

每一步做完记一下：✅ 通过；❌ 失败 + 报错原文（截图或复制最后几行）。

- 第一步 装软件：
- 第二步 拿代码、两个仓库：
- 第三步 安装脚本第一次运行（有没有红色报错）：
- 第四步 `check-agent.sh` 的结果：
- 第六步 机器人启动（`state = running`）：
- 第八步 手机发消息有回复：
- 第九步 飞书授权、建文档收到链接：
- 第十步 用的哪个邮箱、登录成功没有：
- 第十二步 出 Word、复盘：
- 第十三步 微信 `verify` 结果、采到几条、语音有没有转成文字：
- 第十五步 讯飞授权、存了几条：
