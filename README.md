# AgentOS（Mac 版）

个人 AI 助理：在手机飞书里一句话派活；它自动读你的飞书聊天、文档、邮件、微信、讯飞录音，每晚写复盘推到手机；出合同、出文件、写飞书文档、起草邮件，对外发送前要你点头。方案见 [docs/plan.md](docs/plan.md)。

**怎么装：照着 [docs/deploy-mac.md](docs/deploy-mac.md) 一步步做。** 核心就是一条可以重复运行的安装脚本：

```bash
~/AgentOS/ops/install-mac.sh
```

## 它在 Mac 上怎么跑

- 手机上装飞书当遥控器；Mac 一直开着、插着电。
- AI 跑在一个隐藏的系统账号 `agentos` 里，**从系统层面就读不到你的钥匙**；它干活的地方是运行副本 `/Users/agentos/agentos`。
- 代码在你自己账号的 `~/AgentOS`；钥匙在 `~/.agentos`（只有你能读）；采集的原文 `spaces/me/raw/` 不上传 GitHub。
- 飞书机器人和定时任务由 launchd 管，名字以 `com.agentos.` 开头；日志在 `~/.agentos/logs/`。

## 底座

默认用 Claude 订阅（Claude Code + 一年期令牌，国内要开代理）；也可以换成 DeepSeek 等其他公司的接口，见部署文档「底座怎么选」。

## 目录

```
CLAUDE.md             AI 的总规则
.claude/              AI 的权限 settings.json、技能 skills/
spaces/me/kb/         知识库：profile.md、people/、projects/、daily/、decisions.md
spaces/me/raw/        采集原文，不进 Git
ops/                  安装脚本、飞书机器人（bridge/）、采集、复盘、备份、检索、出文件
ops/launchd/          定时任务的配置模板
docs/                 部署文档、方案
```

## 日常

- 拉更新：`git -C ~/AgentOS pull --no-edit upstream main`，再 `~/AgentOS/ops/install-mac.sh`
- 只改了代码、重启飞书机器人：`~/AgentOS/ops/deploy.sh`
- 检查底座：`~/AgentOS/ops/check-agent.sh`
- 手动补写某天的复盘：`~/AgentOS/ops/daily-review.sh 2026-11-09`
- 手动备份知识库：`~/AgentOS/ops/push-kb.sh`
- 离线测试：`/usr/bin/python3 -m unittest discover -s ~/AgentOS/ops -p 'test_*.py'`
