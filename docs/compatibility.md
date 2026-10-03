# 兼容性契约（下游消费者看这份）

这份文档写给**解析 `cold-backup` 输出的人**：看板插件、GUI 面板、你自己的脚本。
里面的东西一旦发布就不轻易改；改之前先看最后一节「什么算破坏性变更」。

## 1. 命令行与退出码

| 调用 | 退出码 |
|---|---|
| `cold-backup [--trigger=名]` | 0 成功；1 失败（同时写 `last-failure` 并发通知） |
| `cold-backup --status` | 0 全绿；1 有问题 |
| `cold-backup --status --json`（裸 `--json` 等价） | 与 `--status` **完全一致**；JSON 永远合法（目标目录不存在时也输出） |
| `cold-backup --verify [--fix]` | 0 / 1。`--fix` 删掉损坏产物**仍返回 1**（「这轮巡检发现了问题」这个事实不该被删掉动作抹平） |
| `cold-backup --daily` | 0 / 1 |
| `cold-backup --prune-orphans [--apply]` | 目标目录不存在 1；删除失败 1；否则 0 |
| `cold-backup --restore-drill [目录]` | 0 / 1 |
| `cold-backup --init` | 0 写入；2 已存在且没给 `--force` |
| `cold-backup schedule …` | 0 / 1 / 2 |
| 未知参数、`--json` 配非 `--status`、配置文件不存在 | 2 |

**约定**：`0` = 一切都好；`1` = 有事实问题；`2` = 你（调用方）用错了。
消费方永远应该**先看退出码，再看内容**；`verdict` 字段只是让这件事不必靠猜。

## 2. stdout

- 人读模式：`== …` 头 + 每行 `  ✓ / ✗ / ! …`（中文）。**不是契约**，不要解析。
- JSON 模式：**stdout 只有一份 JSON，stderr 必须为空**。带 `--json` 时任何调试信息都不许混进 stdout。

## 3. JSON 契约 `cold-backup.status/1`

```json
{
  "schema": "cold-backup.status/1",
  "generatedAt": 1790937202,
  "root": "/Users/you/dev",
  "dest": "/Users/you/Backup/cold-backup",
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
| `schema` | string | 恒为 `cold-backup.status/1`。**前缀匹配 `cold-backup.status/`**，别用它当版本号做严格相等以外的推断 |
| `generatedAt` | epoch 秒 | 这份文档的生成时间 |
| `root` / `dest` | string | 工作区根 / 备份目标（未配置 `dest` 时是空串） |
| `verdict` | `"ok"` \| `"bad"` | 与退出码一致。**只有这两个值**（加第三档会让老消费者静默丢弃整份文档） |
| `lastOk` | epoch 秒 \| null | 最近一次**成功**的备份时间 |
| `lastFailure` | object \| null | `{epoch, trigger, message}`，最近一次失败记录 |
| `orphans` | string[] | 已不对应任何目标的残留目录（相对 `dest`）。**不含**属于别的工作区的目录；**也不含**分组目录（见 §4 的嵌套标签说明） |
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

- 产物名里的 UTC 时间戳只有**秒**精度。同一秒内为两个不同提交各备一次时，会出现
  「秒相同、只差 sha 后缀」的**并列**产物 —— 此时「按文件名取最新」是不可判定的，
  消费方**不要**依赖并列时的顺序。（工具自己也不依赖：`--status` 判断的是「**HEAD 的 sha**
  那一份在不在」，不是「文件名最大的那份」。）
- **标签里带 `/` 的目标是嵌套的**（工作区子目录里的仓库，如 `plugins/foo` → 产物在
  `<DEST>/repos/plugins/foo/`）。于是 `repos/plugins` 这种**中间层只是分组目录，不是目标**，
  也不该被当成残留：判据是「它是不是某个已知目标产物路径的前缀」。
  消费方若自己扫这个目录树，请照同一条规矩来 —— 把分组目录当残留删掉，等于删掉下面所有目标的
  活产物（1.0.3 之前本工具就踩过这个坑，见 `decisions.md`）。
- `<DEST>/repos|snapshots|configs/<标签>/.cold-backup-owner` —— 归属标记，内容是工作区 ID。
  **不是**产物，不要当产物校验，也不要在没有把握时删它。
- `<DEST>/manifests/*.tsv` —— 8 列 `epoch / kind / label / sha / count / file / bytes / sha256`。
  它是**留给人排查的不可变记录**，目前没有任何消费方解析它；改列不算破坏性变更，但也别指望它稳定。

### 4.1 可选的进度文件（`COLD_BACKUP_PROGRESS_FILE`）

给**读侧**（GUI / 面板 / 插件 / 你自己的脚本）在一次运行**进行中**显示进度用：设了
`COLD_BACKUP_PROGRESS_FILE=<路径>`，引擎就把本次运行的事件**追加**成 JSONL —— 一行一个 JSON
对象，每行都能独立解析；每行一次追加写、写完即关闭，所以读侧刚读到的行一定是完整的。

**不设它 = 不建文件、不写一行**，其余输出（stdout / stderr / 退出码 / `last-ok` /
`last-failure` / manifest / 产物布局）与从前**逐字节一致** —— 这是「新增可选行为」，
不是破坏性变更（见 §5）。它也不进配置文件：只认这个环境变量（与 `COLD_BACKUP_DISABLE` 同类）。

文件在运行开始时**创建 / 清空（截断）**，之后只追加；父目录不存在时会尝试创建。
写入失败（磁盘满、只读、云盘占位…）**只记一条日志并停用进度**，绝不影响备份本身与退出码。

事件顺序与字段（`v` 恒为 `1`）：

| # | 何时 | 事件 |
|---|---|---|
| 1 | 备份阶段开始前（拿到目标清单之后） | `{"v":1,"phase":"plan","section":"backup","total":<目标数>,"units":[{"kind":"repo\|snapshot\|config","label":"<标签>","weight":<该目标最新产物字节数，未知为 0>}, …]}` |
| 2 | 每个目标开始处理 | `{"v":1,"phase":"backup","state":"start","kind":"<kind>","label":"<标签>"}` |
| 3 | 每个目标处理结束 | `{"v":1,"phase":"backup","state":"done","kind":"<kind>","label":"<标签>","result":"stored\|skipped\|failed","ms":<该目标耗时>}` |
| 4 | 校验阶段开始前 | `{"v":1,"phase":"plan","section":"verify","total":<待校验产物数>,"units":[{"kind":"…","label":"…","weight":<产物字节数>}, …]}` |
| 5 | 每份产物校验完 | `{"v":1,"phase":"verify","done":<累计数>,"total":<总数>,"label":"<标签>","ok":true\|false}` |
| 6 | 进入状态检查阶段 | `{"v":1,"phase":"status"}` |
| 7 | 运行结束（**成功失败都写**） | `{"v":1,"done":true,"exitCode":<整数>,"ms":<总耗时>}` |

约定：

- `units` 的条数恒等于同一条事件里的 `total`（backup 一个目标一条，verify 一份产物一条）；
  verify 的 `done` 是 `1..total` 的累计值，读侧直接用 `done/total` 画进度条即可。
- `ms` 是**秒级近似值**（秒差 × 1000）：bash 3.2 没有毫秒时钟，也不许引入 python3 / perl 之类
  依赖，所以子秒级的单目标常见 `"ms":0`。拿不到就写 0。
- `result`：`stored` = 写出了新产物；`skipped` = 幂等跳过（该提交已有完好产物 / 内容未变 /
  还没有提交 / 归属冲突）；`failed` = 这个目标没备上且整轮会以非 0 收场（疑似密钥、
  属于别的工作区的产物）。
- 只有 `--daily` 会出现全部三个阶段；**单独的备份运行**只有 1~3，**单独的 `--verify`** 只有 4~5
  （`section` 用 `verify`），`--restore-drill` / `--prune-orphans` 只写收尾那条 7。
  **纯只读模式不碰这个文件**：`--status` / `--status --json` / `--version` / `--init` /
  `schedule …` 既不建文件也不写事件 —— 「看一眼状态」不该在磁盘上留下足迹。
- 致命错误（`die`、`set -u` 中止、被信号杀死）时，正在处理的那个目标可能只有 `start` 没有
  `done`，但**末行永远是第 7 条**（它挂在 `on_exit` 上）。

## 5. 什么算破坏性变更

改这些**会**打断下游，必须当作破坏性变更来对待（同步改消费方、必要时加版本）：

- `schema` 常量、`verdict` 的取值集合、退出码语义；
- 字段名 / 类型 / `null` 与缺省的用法、`counts` 的键；
- reason code 词表与 upload token 词表（新增值通常安全，**删改不安全**）；
- `last-ok` / `last-failure` 的格式；
- 产物文件名的解析规则（名字里带 UTC 时间戳和提交前 12 位，是「按名排序取最新」的前提）。

改这些**不**算：人读文本、日志措辞、manifest 列、`--help` 文案、新增可选字段、
**新增可选行为**（例子：§4.1 的进度文件 —— 不设 `COLD_BACKUP_PROGRESS_FILE` 就一个字节都不写）。

> 例外记一笔：2026-10-02 的**改名**（§7）就是一次**有意**的破坏性变更 —— 趁已知用户只有作者本人，
> 把 `schema` 常量、路径、环境变量一次性换干净，而不是永久养一层旧名兼容。之后再没有这种窗口。

## 6. 现在的消费者

| 消费者 | 怎么读 |
|---|---|
| [dsh-cold-backup](https://www.npmjs.com/package/dsh-cold-backup)（DeepSeek Harness 插件） | 跑 `<命令> --status --json`，前缀匹配 schema，`verdict` 驱动红绿；也可退回读 `last-ok` / `last-failure` |
| 自建 macOS 面板 | 同一份 JSON 渲染成逐目标明细；也直接读 `last-ok` / `last-failure` |
| `--status` 自己 | 人读出口 —— 与 JSON 是**同一次判定**的两个渲染，不是两套规则 |

跑这两条可以验证契约没漂：

```sh
cold-backup --status --json | python3 -m json.tool     # JSON 合法
cold-backup --status | grep -c '✓'                      # 人读 ✓ 行数 == JSON 里 state=ok 的条数 + 1
```

## 7. 改名（2026-10-02）：`dev-backup` → `cold-backup`

这个工具 2026-09-30 首次公开发布时叫 **`dev-backup`**（npm 包名、命令名、GitHub 仓库名都是它）。
2026-10-02 起统一改成 **`cold-backup`** —— `dev` 既不准确也不自解释，它做的是**冷备**
（离线快照 + 可还原），不是实时同步。DSH 插件同步改名：`dsh-dev-backup` → `dsh-cold-backup`。

**换代是干净的：不保留任何旧名兼容。** 一起换掉的标识：

| 类别 | 旧 | 新 |
|---|---|---|
| npm 包名 / 命令名 | `dev-backup` | `cold-backup` |
| 环境变量前缀 | `DEV_BACKUP_*` | `COLD_BACKUP_*` |
| 配置文件 | `~/.config/dev-backup/config` | `~/.config/cold-backup/config` |
| 日志目录（macOS） | `~/Library/Logs/dev-backup` | `~/Library/Logs/cold-backup` |
| 日志目录（其它平台） | `~/.local/state/dev-backup` | `~/.local/state/cold-backup` |
| JSON schema | `dev-backup.status/1` | `cold-backup.status/1` |
| 归属标记 | `.dev-backup-owner` | `.cold-backup-owner` |
| crontab 标记 | `# >>> dev-backup >>>` | `# >>> cold-backup >>>` |
| launchd label 模板 | `com.dev-backup.daily` | `com.cold-backup.daily` |

**下游要做的事**：前缀匹配 schema 的改成 `cold-backup.status/`；读日志目录的换新路径；
传环境变量的换 `COLD_BACKUP_*`。旧 npm 包（`dev-backup`、`dsh-dev-backup`）已在 registry 上
deprecate —— 旧版本仍能安装，只是会提示改名；GitHub 旧仓库名 301 重定向到新仓库。

**已有数据怎么迁**（都不影响正确性，不做也不会丢东西）：

```sh
# 日志与状态文件：搬过去，历史判定（last-ok / last-failure）就还在
mv ~/Library/Logs/dev-backup ~/Library/Logs/cold-backup     # Linux: ~/.local/state/...
# 配置文件
mv ~/.config/dev-backup ~/.config/cold-backup
# 备份目录里的归属标记（不改也安全：没有标记一律按「大概是自己的」处理，见 §4）
find "$DEST" -name .dev-backup-owner -execdir mv {} .cold-backup-owner \;
# 定时任务：先用旧版卸掉再装新版，否则两份任务各跑各的
dev-backup schedule uninstall && cold-backup schedule install
```

**注意旧任务不会被自动接管**：旧 crontab 标记与旧 launchd label 都不在新版本的识别范围内，
不手工卸载就会每天跑两次（其中一次写的是旧路径）。这是「干净断代」的直接代价。
