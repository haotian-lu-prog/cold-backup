# 还原手册

冷备只有在**能还原**的前提下才算备份。这份文档写清三种还原姿势、怎么验证、以及还原不回来的
东西（免得你以为它保住了）。

先看备份目录里有什么：

```
<DEST>/repos/<标签>/<标签>-<UTC时间戳>-<提交前12位>.bundle
<DEST>/snapshots/<标签>/<标签>-<UTC时间戳>-<内容指纹>.tar.gz
<DEST>/configs/<标签>/<标签>-<UTC时间戳>-<内容指纹>.tar.gz
```

`<标签>` = 仓库相对工作区根的路径，`/` 换成 `_`（`plugins/foo` → `plugins_foo`）。

## 1. 完整还原一个仓库（推荐）

```sh
git clone --mirror "<DEST>/repos/<标签>/<文件>.bundle" /tmp/restore.git
git -C /tmp/restore.git for-each-ref | head
```

`--mirror` 会把 bundle 里的**全部** refs 还原出来：`refs/heads/*`、`refs/tags/*`、
`refs/remotes/*`、`filter-branch` 留下的 `refs/original/*`，以及 `refs/stash`。
这正是普通 `git clone` 会丢掉的东西 —— 也是「为什么不用 git push 当备份」的答案。

要接着干活，把它当远端拉一份工作副本：

```sh
git clone /tmp/restore.git ~/work/恢复出来的仓库
```

## 2. 日常还原（只要一个工作副本）

```sh
git clone "<DEST>/repos/<标签>/<文件>.bundle" /tmp/restore
git -C /tmp/restore log --oneline | head
```

普通 clone 只带 `refs/heads/*` 与 tags。够日常用，但**不够完整** —— 要「一个字节都不少」
就用第 1 种。

## 3. 非 git 目录

```sh
# 先看里面有什么（不落盘）
tar -tzf "<DEST>/snapshots/<标签>/<文件>.tar.gz" | head -30

# 解到指定目录
mkdir -p /tmp/restore && tar -xzf "<DEST>/snapshots/<标签>/<文件>.tar.gz" -C /tmp/restore
```

快照的**文件名里带内容指纹**（前 12 位）：内容变了才会有新文件，所以同一目录下多个
文件 = 内容确实变过的几个版本，不是重复。

## 4. 验证：别等真要还原时才发现坏了

```sh
dev-backup --verify            # 逐份校验：最新那份真 clone + fsck，其余至少验结构
dev-backup --verify --fix      # 顺手删掉确认损坏的产物（仍返回 1：发现问题这件事不抹掉）
dev-backup --restore-drill     # 真演练：镜像 clone 每个最新 bundle，比对提交数与 ref 指纹
```

`--restore-drill` 是**唯一**能证明「这套备份真能还原」的东西：它把产物当远端 clone 出来，
逐个比对 ref 指纹与提交数，并额外验证普通 clone 出的工作副本 HEAD 与源一致。
建议在换机器、换云盘客户端、或者心里没底的时候跑一次。

`<DEST>/manifests/*.tsv` 是每次运行的清单，用来回答「这份产物是哪次运行、哪个触发源产生的」：

```sh
column -t -s $'\t' "<DEST>/manifests/20261002T103000Z-post-commit.tsv"
```

## 5. 云盘那一份坏了怎么办

- **单份产物损坏**（同步中断、磁盘错误）：`--verify` 会指出来，`--verify --fix` 删掉它，
  再跑一次 `dev-backup` 重建最新那份。历史产物坏了就只能删 —— 它们本来也是轮转要淘汰的。
- **`.sha256` 缺失或不符**：按「不可信」处理（不是「通过」）。重跑备份会重建并补回指纹。
- **整个目录空了**：先确认不是权限问题 —— macOS 上 `--status` 会报 `fda-blocked`，那是
  「读不到」，不是「没有了」。别在没授权的情况下跑 `--verify --fix`，那会把好产物误判成损坏。

## 6. 还原**不回来**的东西（有意为之）

| 不在覆盖内 | 为什么 |
|---|---|
| 仓库里未提交 / 未跟踪的改动 | 冷备是「提交历史」的保险，不是「工作区当前状态」的保险；要保未提交改动就 `git stash` 或提交 |
| 隐藏目录（`.worktrees/` 等） | 各分支的 ref 本来就在主仓库的 bundle 里，重复打包只会变慢 |
| `node_modules/`、`dist/`、`build/`、`out/`、`.venv/`、`__pycache__/`、`.cache/`、`tmp/`、`*.log` | 可重装/可再生；排除后快照小得多 |
| `.env` / `.env.*` | 默认排除（明文密钥不上云）。确实需要时用 `INCLUDE_ENV=1` 重跑 |
| 家目录里的凭据、会话、历史 | 配置白名单默认 `off`，且上云前有密钥预检 —— 本工具**不加密**，不碰这些 |

还有一条时间维度的限制：每个目标只保留最新 `KEEP`（默认 10）份产物，更旧的会被轮转删除。
**它是「最近状态的保险」，不是「历史归档」**。要长期留档就调大 `KEEP`，或者定期把
`<DEST>` 整个目录另存一份。

## 7. 换机器怎么开工

1. 装：`npm i -g dev-backup`（或 `./install.sh`）。
2. 写配置：`dev-backup --init` 后填 `ROOT` 与 `DEST`（新机器上的路径可以完全不同）。
3. 看：`dev-backup --status` —— 如果 `DEST` 是同一个同步目录，它应该直接认得那些产物。
4. 验：`dev-backup --restore-drill` 走一遍，确认能还原。
5. 装定时任务：`dev-backup schedule install`。

注意 `WORKSPACE_ID`（归属标记）默认含**主机名**：新机器是新的工作区身份，两边指向同一个
`DEST` 时不会互相删产物。若你就是要两边共享同一批产物，把两台机器的 `WORKSPACE_ID` 设成
同一个值。
