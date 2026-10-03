[English](https://github.com/haotian-lu-prog/cold-backup/blob/main/README.en.md) | 简体中文

# cold-backup

[![npm 版本](https://img.shields.io/npm/v/cold-backup)](https://www.npmjs.com/package/cold-backup)
[![许可证](https://img.shields.io/npm/l/cold-backup)](LICENSE)
[![CI](https://github.com/haotian-lu-prog/cold-backup/actions/workflows/ci.yml/badge.svg)](https://github.com/haotian-lu-prog/cold-backup/actions/workflows/ci.yml)

把「一个装着很多 git 仓库的工作区」**冷备**到一个目录里：产物直接落进你指定的同步目录
（OneDrive / iCloud / Dropbox / 坚果云…或一块外置磁盘），由你已经装好的同步客户端负责上传。

不依赖 rclone / restic，不加密，不做增量协议 —— 它做的是另一件事：**把工作区变成一堆
不可变、可校验、可完整还原的文件**。

```sh
npm i -g cold-backup      # 或者 ./install.sh（不需要 Node）
cold-backup --init        # 写一份配置文件模板
cold-backup --status      # 看一眼：备上了吗、上传了吗
cold-backup               # 跑一次备份
```

## 它解决什么问题

工作区里通常是几十个 git 仓库：有的推了远端，有的没有；有的一堆本地分支、tag、
`filter-branch` 留下的 `refs/original/*`；还有一堆根本不是 git 的目录（草稿、素材、配置）。
「推远端」覆盖不了这些，而全量 tar 又快又大。

`cold-backup` 的做法：

| 目标 | 做法 | 为什么 |
|---|---|---|
| git 仓库 | `git bundle create --all` + 存在时的 `refs/stash` | 一个文件装下**全部** refs（含远端不带的 `refs/original/*`、`refs/remotes/*`），可 `git clone --mirror` 完整还原 |
| 非 git 顶层目录 | `tar.gz` 快照，内容指纹写进文件名 | 内容没变就不新增文件（云盘里不会堆重复快照） |
| 工具配置（可选） | 白名单 + 上云前密钥预检 | 只收你显式列出的几个文件；命中疑似密钥就整份不收 |

三条贯穿始终的规则：

1. **幂等** —— 同一个提交不会打第二份包；同一份内容不会存第二个快照。
2. **不可变** —— 备份目录里只新增 / 删除文件，**从不原地修改**已有文件。这是给同步客户端
   和后台任务准备的：launchd 起的进程常常改不动别的进程建的文件。
3. **「最新」按文件名判断，不看 mtime** —— 云盘重新物化会改写 mtime，用它排序会让
   `--status` 误报落后、让 `--restore-drill` 拿旧产物演练。

## 安装

**npm（推荐）**

```sh
npm i -g cold-backup
```

**不用 Node**

```sh
git clone https://github.com/haotian-lu-prog/cold-backup.git
cd cold-backup && ./install.sh          # 装到 ~/.local/bin
```

要求：`bash`（macOS 自带的 3.2 就行）、`git`、`tar`、`gzip`，以及 `shasum` 或 `sha256sum`。

## 快速开始

```sh
cold-backup --init                 # 1) 生成 ~/.config/cold-backup/config
$EDITOR ~/.config/cold-backup/config   # 2) 改 ROOT 与 DEST
cold-backup --status               # 3) 看状态（此时应该是「还没有备份」）
cold-backup                        # 4) 跑第一次备份
cold-backup schedule install       # 5) 装每日任务（macOS: launchd；其他: cron）
```

第一次跑完，`DEST` 里会出现 `repos/`、`snapshots/`、`manifests/` 和一份写给人看的
`README.md`（还原步骤就在里面，离开这台机器也看得到）。

## 配置

优先级：**命令行 > 环境变量 > 配置文件 > 内置默认**。配置文件是 `KEY=VALUE`，
默认在 `~/.config/cold-backup/config`（`--config` 或 `COLD_BACKUP_CONFIG` 可改）。

| 配置文件键 | 环境变量 | 默认 | 说明 |
|---|---|---|---|
| `ROOT` | `DEV_ROOT` | `~/dev` | 要备份的工作区根 |
| `DEST` | `COLD_BACKUP_DEST` | 无（**必填**） | 备份目标目录。**必须在 `ROOT` 之外** —— 放在工作区里会让快照把备份自己逐轮打大，工具会直接拒绝 |
| `LOGDIR` | `COLD_BACKUP_LOGDIR` | macOS `~/Library/Logs/cold-backup`；其他 `~/.local/state/cold-backup` | 日志、锁、`last-ok` / `last-failure` |
| `DEPTH` | `COLD_BACKUP_DEPTH` | `3` | 从 ROOT 往下找 `.git` 的层数 |
| `KEEP` | `COLD_BACKUP_KEEP` | `10` | 每个目标保留多少份产物，更旧的轮转删除 |
| `SNAPSHOTS` | `COLD_BACKUP_SNAPSHOTS` | `1` | 是否给非 git 顶层目录打快照 |
| `INCLUDE_ENV` | `COLD_BACKUP_INCLUDE_ENV` | `0` | 快照是否包含 `.env` / `.env.*`（默认排除，明文密钥不上云） |
| `EXCLUDES` | `COLD_BACKUP_EXCLUDES` | 空 | 额外的 tar 排除项，空格分隔 |
| `CONFIGS` | `COLD_BACKUP_CONFIGS` | `off` | 工具配置白名单（见下） |
| `NOTIFY_TITLE` | `COLD_BACKUP_NOTIFY_TITLE` | `cold-backup（工作区冷备）` | 桌面通知标题 |
| `NO_NOTIFY` | `COLD_BACKUP_NO_NOTIFY` | `0` | 设 `1` 关掉桌面通知 |
| `UPLOAD_GRACE` | `COLD_BACKUP_UPLOAD_GRACE` | `600` | 产物超过这么多秒还没上传就报「未上传」 |
| `DRILL_DIR` | `COLD_BACKUP_DRILL_DIR` | 日志目录下的 `tmp/drill-*` | `--restore-drill` 的输出目录 |
| `WORKSPACE_ID` | `COLD_BACKUP_WORKSPACE_ID` | 主机名 + ROOT 路径的指纹 | 归属标记（见「多台机器共用一个备份目录」） |
| `FDA_APP` | `COLD_BACKUP_FDA_APP` | 自动探测 | macOS 上提示授权时指给用户看的 app |

`COLD_BACKUP_DISABLE=1` 会让备份模式立刻退出 0（git 钩子用它做开关）；
`COLD_BACKUP_DEEP_ALL=1` 让 `--verify` 对所有历史产物都做真 clone（慢，默认只对最新那份做）；
`COLD_BACKUP_PROGRESS_FILE=<路径>` 让引擎把本轮事件**追加**成 JSONL（进度条 / 看板用：
`plan` → 逐目标 `start`/`done` → 逐份产物校验 → 收尾 `done:true` + 退出码 + 耗时）。
它是给读侧的可选旁路信号：**不设就一个字节都不写**，只读模式连文件都不建；
写入失败只记日志、不影响备份。字段表见 [docs/compatibility.md](docs/compatibility.md) §4.1。

### 工具配置白名单

默认 `off` —— 它不会去猜你的 home 长什么样。要收就在配置里显式写：

```ini
CONFIGS=claude-config|~/.claude|settings.json,CLAUDE.md;codex-config|~/.codex|config.toml,AGENTS.md
```

格式 `<标签>|<家目录>|<相对路径,相对路径>`，多条用 `;` 分隔。上云前会对这些文件做一次
密钥预检（`sk-…`、`AKIA…`、`ghp_…`、私钥头、`token = "…"` 之类）：**命中就整份不收**，
并让整轮以非零退出 —— 本工具不加密，拦住比事后补救便宜。

## 命令

| 命令 | 做什么 | 退出码 |
|---|---|---|
| `cold-backup [--trigger=名]` | 跑一次备份（幂等） | 0 / 1 |
| `cold-backup --status` | 新鲜度 + 上传状态，人读 | 0 / 1 |
| `cold-backup --status --json` | 同一判定的 JSON 出口（契约见下） | 0 / 1 |
| `cold-backup --verify [--fix]` | 逐份校验**全部**产物；bundle 真 clone + `fsck` | 0 / 1（`--fix` 删了损坏产物**仍返回 1**） |
| `cold-backup --daily` | 补跑备份 + 逐份校验 + 状态检查 | 0 / 1 |
| `cold-backup --prune-orphans [--apply]` | 清理备份目录里已不对应任何目标的残留；默认只列不删 | 0 / 1 |
| `cold-backup --restore-drill [目录]` | 真还原演练：镜像 clone，比对提交数与 ref 指纹 | 0 / 1 |
| `cold-backup schedule install\|uninstall\|status [--dry-run]` | 装 / 卸 / 查定时任务 | 0 / 1 / 2 |
| `cold-backup --init [--force]` | 写配置文件模板 | 0 / 2 |
| `cold-backup --version` | 版本与当前配置文件 | 0 |

`--status` 与 `--version` 是**严格只读**的：不建目录、不写文件、不动日志。

## 产物布局与还原

```
<DEST>/repos/<标签>/<标签>-<UTC时间戳>-<提交前12位>.bundle    ← + 同名 .sha256
<DEST>/snapshots/<标签>/<标签>-<UTC时间戳>-<内容指纹>.tar.gz
<DEST>/configs/<标签>/<标签>-<UTC时间戳>-<内容指纹>.tar.gz
<DEST>/manifests/<UTC时间戳>-<触发源>.tsv                     ← 每次运行一份不可变清单
<DEST>/README.md                                              ← 还原说明（写给人看）
<DEST>/repos/<标签>/.cold-backup-owner                         ← 归属标记（见下）
```

标签 = 仓库相对工作区根的路径（`plugins/foo` → `plugins_foo`）。

```sh
# 完整还原（推荐）：refs/* 全量，含 refs/original/*、refs/remotes/*
git clone --mirror "<DEST>/repos/<标签>/<文件>.bundle" /tmp/restore.git

# 日常还原：普通工作副本
git clone "<DEST>/repos/<标签>/<文件>.bundle" /tmp/restore

# 非 git 目录
tar -xzf "<DEST>/snapshots/<标签>/<文件>.tar.gz" -C /tmp/restore
```

**不在覆盖内**（有意为之）：仓库里未提交 / 未跟踪的改动、隐藏目录（`.worktrees/` 之类）、
家目录里的凭据与会话历史、可重装的大体积内容（`node_modules/`、构建产物）。别把冷备当唯一
保险 —— 它是「推远端」之外的**第二层**，不是「未提交改动」的保险。

## 定时任务

```sh
cold-backup schedule install --at 12:00     # macOS: launchd 每天 12:00；Linux: cron
cold-backup schedule install --dry-run      # 只打印计划，不碰系统
cold-backup schedule status
cold-backup schedule uninstall
```

macOS 的坑：如果 `DEST` 在 `~/Library/CloudStorage/`（OneDrive / Google Drive 之类）或
`~/Library/Mobile Documents/` 下，**后台任务默认读不到那里已有的文件** —— 那是 TCC 保护，
写入通常没事、读改会被拒。两种解法：给运行它的程序「完全磁盘访问权限」，或者

```sh
cold-backup schedule install --program /path/to/已授权的可执行文件
```

把任务交给一个已经拿到授权的主体去跑。程序会被调用成 `<program> --daily --trigger=launchd`。
`--status` 会明确报告这种情况（`fda-blocked`），不会假装正常。

## 多台机器共用一个备份目录

每备份一个目标，工具会在目标目录里写一份 `.cold-backup-owner`（内容是「工作区 ID」，
默认 = 主机名 + 工作区根路径的指纹）。于是：

- 归属是**别的工作区/主机**的目录：`--status` 只报告、`--prune-orphans --apply` **绝不删**、
  备份时拒绝写入并整轮以非零退出（宁可少备一个目标，也不去覆盖别人的产物）。
- 没有归属标记的老目录按「大概是自己的」处理，行为与老版本一致。

同一个工作区在两台机器上跑、并且**就是要**共用一个 `DEST` 时，把两边的
`WORKSPACE_ID` 设成同一个值即可。

## 给下游消费者的契约

`cold-backup.status/1` JSON 是稳定契约，[dsh-cold-backup](https://www.npmjs.com/package/dsh-cold-backup)
（DeepSeek Harness 里的备份看板插件）与自建 macOS 面板都消费它。字段、reason code、
上传状态 token、退出码语义见 [`docs/compatibility.md`](docs/compatibility.md)。

## 平台支持与实测边界

- **macOS**：本机日常使用中，端到端自测全绿（含 bash 3.2）。
- **Linux**：代码里所有 `stat -f%z` / `date -j -f` / `shasum` 都走了兼容层，CI 在
  `ubuntu-latest` 上跑同一套自测。**作者尚未在真实 Linux 机器上手工验证过** —— 别把 CI
  绿当成「任何发行版都没问题」。
- 上传状态探测（`uploaded` / `uploading` / `stale`）用的是 macOS 的 `mdls`；其他平台如实
  报告「上传状态未知」，不会假装已上传。

## 测试

```sh
npm test            # = bash test/lint.sh && bash test/selftest.sh
npm run test:frozen # 冻结时钟压力测试：把产物时间戳钉成同一个值再跑一遍
```

自测全程只在 `mktemp -d` 造的临时工作区里操作，**不碰真实备份目录**。静态检查会拦
「bash 3.2 会把全角字符吃进变量名」这类本机踩过的坑、bash 4 专有语法、版本号不一致、
以及误入仓库的个人路径。

`npm run test:frozen` 是专门的**并列**压力测试：产物名里的 UTC 时间戳只有秒精度，
真实机器上「同一秒内为两个提交各备一次」是时序巧合（快的机器会撞上），冻结时钟把那巧合变成常态，
用来保证轮转不会删掉刚写出的产物、校验与还原演练也不会抓错那一份。

## 许可证

MIT，见 [LICENSE](LICENSE)。
