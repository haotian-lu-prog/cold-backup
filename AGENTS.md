# AGENTS.md — dev-backup

把「一个装着很多 git 仓库的工作区」冷备到一个目录（同步客户端负责上传）的 CLI。
纯 bash，无运行时依赖；产物是不可变的 bundle / tar.gz，可完整还原。

## 运行

- 安装依赖：**没有依赖**（需要 `bash` 3.2+、`git`、`tar`、`gzip`、`shasum` 或 `sha256sum`）
- 测试：`npm test`（= `bash test/lint.sh && bash test/selftest.sh`）
- 单跑静态检查：`bash test/lint.sh`；单跑端到端：`bash test/selftest.sh`
- 本地装一份试用：`./install.sh`（装到 `~/.local/bin`）

自测全程只在 `mktemp -d` 造的临时目录里操作，**不会碰真实备份目录**；唯一的例外是
macOS 上会读 `~/Library/Logs/dev-backup/` 之类的默认路径（只读）。

## 约定

- 工作区总则见各工具 home 的全局指令（`~/.dsh/AGENTS.md`、`~/.codex/AGENTS.md`、`~/.claude/CLAUDE.md`）；本文件只写**本项目特有**的内容。
- 开工先读 `HANDOFF.md`；收工更新它（当前状态、下一步、未决问题）并提交。
- 有取舍的决策追加到 `docs/decisions.md`。

## 这个仓库的五条硬约束

1. **对外契约冻结**：子命令、退出码、`dev-backup.status/1` 的字段、reason code、upload token、
   产物布局、`last-ok` / `last-failure` 格式，都已经有外部消费者（DSH 插件、macOS 面板、git 钩子）。
   改之前先读 [`docs/compatibility.md`](docs/compatibility.md) 的「什么算破坏性变更」。
2. **bash 3.2 是下限**：macOS 的 launchd 与 git 钩子跑的就是 `/bin/bash`（3.2）。
   不许用 `declare -A`、`mapfile`、`readarray`、`${x^^}`、`local -n`、`&>>` —— `test/lint.sh` 会拦。
3. **变量后面紧跟中文必须写 `${var}`**：bash 3.2 会把全角字节吃进变量名，`set -u` 下直接中止。
   lint 也拦这一条。
4. **不可变的产物布局**：备份目录里只新增 / 删除文件，**从不原地修改**已有文件；
   「最新」按文件名里的 UTC 时间戳排序，不信任 mtime（云盘会重写 mtime）。
5. **不碰别人的东西**：目标目录带归属标记（`.dev-backup-owner`）。判定为别的工作区时，
   只报告、不写、不删。宁可不备，也不覆盖。

## 结构

- `bin/dev-backup` — 全部实现（单个 bash 文件：配置层、可移植层、备份/状态/校验/调度）
- `install.sh` — 不用 npm 时的安装脚本
- `test/lint.sh` — 静态检查（bash 3.2 兼容、契约常量、版本号一致、无个人路径、CLI 冒烟）
- `test/selftest.sh` — 端到端自测（临时工作区里跑完备份→校验→还原演练→清理）
- `docs/compatibility.md` — 给下游消费者的契约
- `docs/scheduling.md` — launchd / cron 安装与 macOS TCC 坑
- `docs/restore.md` — 还原手册与「什么还原不回来」
- `docs/decisions.md` — 决策记录（倒序）
- `.github/workflows/` — `ci.yml`（ubuntu + macOS，后者用 `/bin/bash` 3.2 再跑一遍）、
  `conventions.yml`（工作区公约闸门）、`publish.yml`（Release → npm trusted publishing）
