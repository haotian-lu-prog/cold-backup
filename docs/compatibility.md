# 兼容性契约（下游消费者看这份）

这份文档写给**解析 `dev-backup` 输出的人**：看板插件、GUI 面板、你自己的脚本。
里面的东西一旦发布就不轻易改；改之前先看最后一节「什么算破坏性变更」。

## 1. 命令行与退出码

| 调用 | 退出码 |
|---|---|
| `dev-backup [--trigger=名]` | 0 成功；1 失败（同时写 `last-failure` 并发通知） |
| `dev-backup --status` | 0 全绿；1 有问题 |
| `dev-backup --status --json`（裸 `--json` 等价） | 与 `--status` **完全一致**；JSON 永远合法（目标目录不存在时也输出） |
| `dev-backup --verify [--fix]` | 0 / 1。`--fix` 删掉损坏产物**仍返回 1**（「这轮巡检发现了问题」这个事实不该被删掉动作抹平） |
| `dev-backup --daily` | 0 / 1 |
| `dev-backup --prune-orphans [--apply]` | 目标目录不存在 1；删除失败 1；否则 0 |
| `dev-backup --restore-drill [目录]` | 0 / 1 |
| `dev-backup --init` | 0 写入；2 已存在且没给 `--force` |
| `dev-backup schedule …` | 0 / 1 / 2 |
| 未知参数、`--json` 配非 `--status`、配置文件不存在 | 2 |

**约定**：`0` = 一切都好；`1` = 有事实问题；`2` = 你（调用方）用错了。
消费方永远应该**先看退出码，再看内容**；`verdict` 字段只是让这件事不必靠猜。

## 2. stdout

- 人读模式：`== …` 头 + 每行 `  ✓ / ✗ / ! …`（中文）。**不是契约**，不要解析。
- JSON 模式：**stdout 只有一份 JSON，stderr 必须为空**。带 `--json` 时任何调试信息都不许混进 stdout。

## 3. JSON 契约 `dev-backup.status/1`

```json
{
  "schema": "dev-backup.status/1",
  "generatedAt": 1790937202,
  "root": "/Users/you/dev",
  "dest": "/Users/you/Backup/dev-backup",
  "verdict": "ok",
  "lastOk": 1790936761,
  "lastFailure": { "epoch": 1790930000, "trigger": "post-commit", "message": "打包失败：foo" },
  "orphans": ["repos/old-name"],
  "reasons": [ { "code": "behind", "target": "demo", "message": "备份落后（HEAD abc…）" } ],
  "targets": [
    {
      "kind": "repo", "label": "demo", "state": "ok",
      "artifact": "demo-20261002T103000Z-abc123def456.bundle",
      "at": 1790936761, "bytes": 40960, "sha256": "…",
      "upload": "uploaded", "dirty": 2,
      "message": "最新提交 abc123def456 已备份"
    }
  ],
  "counts": { "repos": 1, "snapshots": 0, "configs": 0, "problems": 0, "orphans": 0 }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `schema` | string | 恒为 `dev-backup.status/1`。**前缀匹配 `dev-backup.status/`**，别用它当版本号做严格相等以外的推断 |
| `generatedAt` | epoch 秒 | 这份文档的生成时间 |
| `root` / `dest` | string | 工作区根 / 备份目标（未配置 `dest` 时是空串） |
| `verdict` | `"ok"` \| `"bad"` | 与退出码一致。**只有这两个值**（加第三档会让老消费者静默丢弃整份文档） |
| `lastOk` | epoch 秒 \| null | 最近一次**成功**的备份时间 |
| `lastFailure` | object \| null | `{epoch, trigger, message}`，最近一次失败记录 |
| `orphans` | string[] | 已不对应任何目标的残留目录（相对 `dest`）。**不含**属于别的工作区的目录 |
| `reasons` | array | `{code, target, message}`；`code` 是机器可读的英文标识，`message` 是给人看的中文 |
| `targets` | array | 每个目标一条，见下 |
| `counts` | object | `{repos, snapshots, configs, problems, orphans}` |

### `targets[]`

| 字段 | 取值 |
|---|---|
| `kind` | `repo` \| `snapshot` \| `config` |
| `label` | 目标标签（仓库相对工作区根的路径，`/` 换成 `_`） |
| `state` | `ok` \| `missing` \| `behind` \| `skipped`（`ok`/`skipped` 不算问题；其余计入 `counts.problems`） |
| `artifact` | 产物文件名 \| null |
| `at` | 产物时间（epoch 秒，取文件名里的 UTC 时间戳，取不到才退回 mtime）\| null |
| `bytes` | 大小 \| null |
| `sha256` | 指纹（只有 `repo` 有）\| null |
| `upload` | 上传状态 token，见下 \| null |
| `dirty` | 未提交改动条数（只有 `repo` 有）\| null |
| `message` | 人读说明（中文） |

### `reasons[].code` 词表

| code | 含义 |
|---|---|
| `unconfigured` | 还没配置备份目标（与「配了但坏了」严格区分） |
| `dest-missing` | 目标目录不存在 |
| `fda-blocked` | macOS 隐私保护：读不到目标目录里已有的产物 |
| `missing` | 某个 repo 完全没有 bundle |
| `behind` | 有 bundle，但没有 HEAD 那一份（**判据是 HEAD，不是「文件名最大的那份」**） |
| `missing-snapshot` / `missing-config` | 还没有快照 / 配置快照 |
| `not-uploaded` | 产物还没上传到云端 |
| `sidecar` | `.sha256` 缺失或不符 |
| `gzip` | 快照 gzip 校验失败 |
| `last-failure` | 上次运行失败过（`last-failure` 文件里有记录） |

### `upload` token 词表

`uploaded` | `uploading` | `stale`（超过 `UPLOAD_GRACE` 秒还没上传） |
`unknown-nomdls`（本平台没有 `mdls`，如 Linux） | `unknown-cloud`（不在云盘目录里）

判定用 macOS 的 `mdls -name kMDItemIsUploaded`。**其他平台一律如实报「未知」，不假装已上传。**

## 4. 文件级契约

日志目录（`LOGDIR`）里这三样是给外部读的：

| 文件 | 格式 |
|---|---|
| `last-ok` | 纯 epoch 秒。若内容不是纯数字，消费方应退回用文件 mtime（面板与插件都这么写） |
| `last-failure` | **追加**的行，每行 `epoch=<秒>\ttrigger=<名>\t<消息>`；取最后一行 |
| `backup.log` | 人读日志，超过 1MB 轮转成 `backup.log.1` |

产物目录布局见 [README](../README.md#产物布局与还原)。其中：

- `<DEST>/repos|snapshots|configs/<标签>/.dev-backup-owner` —— 归属标记，内容是工作区 ID。
  **不是**产物，不要当产物校验，也不要在没有把握时删它。
- `<DEST>/manifests/*.tsv` —— 8 列 `epoch / kind / label / sha / count / file / bytes / sha256`。
  它是**留给人排查的不可变记录**，目前没有任何消费方解析它；改列不算破坏性变更，但也别指望它稳定。

## 5. 什么算破坏性变更

改这些**会**打断下游，必须当作破坏性变更来对待（同步改消费方、必要时加版本）：

- `schema` 常量、`verdict` 的取值集合、退出码语义；
- 字段名 / 类型 / `null` 与缺省的用法、`counts` 的键；
- reason code 词表与 upload token 词表（新增值通常安全，**删改不安全**）；
- `last-ok` / `last-failure` 的格式；
- 产物文件名的解析规则（名字里带 UTC 时间戳和提交前 12 位，是「按名排序取最新」的前提）。

改这些**不**算：人读文本、日志措辞、manifest 列、`--help` 文案、新增可选字段。

## 6. 现在的消费者

| 消费者 | 怎么读 |
|---|---|
| [dsh-dev-backup](https://www.npmjs.com/package/dsh-dev-backup)（DeepSeek Harness 插件） | 跑 `<命令> --status --json`，前缀匹配 schema，`verdict` 驱动红绿；也可退回读 `last-ok` / `last-failure` |
| 自建 macOS 面板 | 同一份 JSON 渲染成逐目标明细；也直接读 `last-ok` / `last-failure` |
| `--status` 自己 | 人读出口 —— 与 JSON 是**同一次判定**的两个渲染，不是两套规则 |

跑这两条可以验证契约没漂：

```sh
dev-backup --status --json | python3 -m json.tool     # JSON 合法
dev-backup --status | grep -c '✓'                      # 人读 ✓ 行数 == JSON 里 state=ok 的条数 + 1
```
