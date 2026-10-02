# HANDOFF

> 三家的接力棒：DSH / Codex / Claude Code 都读这个文件。**开工先读，收工必更新并提交。**

## 当前写者

- 工具：DSH
- 分支：main（尚未建远端）
- 开始时间：2026-10-02 19:30

> 一个仓库同一时刻只允许一个写者。交接时把上一行改成自己，并先读完下面的状态。

## 当前状态

**这个仓库还不存在公开副本** —— 它先在 DSH 会话工作区的 `.dev-backup-staging/dev-backup/`
里搭好并通过测试，再整体搬到 `~/dev/dev-backup`、建远端、推上去。搬迁前的状态：

- `bin/dev-backup`（约 1500 行）已从私有的 `~/dev/_shared/bin/backup-dev.sh` 泛化完成：
  接口、退出码、JSON 契约、产物布局**逐字节保持兼容**；新增配置文件、
  `--config/--root/--dest/--logdir`、`--init`、`--version`、`schedule install|uninstall|status`，
  以及 BSD/GNU 兼容层（`stat` / `date` / `sha256`）。
- **兼容性已实测**（两道证据）：
  - ① 把私有仓库那套 677 行 / 122 条断言的自测指向新 CLI：**114 项通过、2 项失败**，
    且那 2 项是「找不到 `_shared/app` 文案表」——即测试脚本自己的路径假设，
    与本 CLI 行为无关（面板本地化那两节属于私有仓库）。
  - ② 在**本机真实数据**上跑新旧两个实现的 `--status --json`：16 个目标
    （6 仓库 / 7 快照 / 3 配置 / 6 残留），去掉 `generatedAt` 后 **JSON 结构完全一致**；
    人读输出只差措辞（`云盘残留` → `备份目录残留`、头部去掉了 `~/dev → OneDrive` 的字样）。
- 已修掉四个真 bug：① 三处「变量后紧跟全角字符」（bash 3.2 会中止）；
  ② `--status` 有副作用（建目录 / 轮转日志 / 写 `last-failure`）；③ `--prune-orphans`
  删除失败仍退出 0；④ `schedule install --at 25:00` 被管道吞掉失败、照样输出 plist 且退 0。
- npm 形态已验证：`npm pack` 出 10 个文件 / 45KB；装进临时 prefix 后 `bin` 软链正确、
  可执行位保留、CLI 能跑（`npm pack --dry-run` 需要 `npm_config_cache` 指到工作区内）。
- 新增安全机制：`.dev-backup-owner` 归属标记 —— 别的工作区的产物**不写不删只报告**。
- 文档：README（中/英）、`docs/compatibility.md`、`docs/scheduling.md`、
  `docs/restore.md`、`docs/decisions.md`（8 条决策）。
- 已就位：`package.json`（npm 名 `dev-backup`，无依赖）、`install.sh`、MIT LICENSE、
  `.github/workflows/{ci,conventions,publish}.yml`（conventions 与 `_shared/ci/` 模板逐字节一致）。
- `test/selftest.sh`（704 行、24 节）：移植了私有仓库那套的全部引擎断言，
  丢掉面板/runner/钩子那几节，并补了配置优先级、`--init`、只读承诺、未配置 JSON、
  归属标记、`schedule --dry-run`、版本一致性、删除失败退出 1。

**已验证**（都在本机跑过，命令可复现）：

| 验证 | 结果 |
|---|---|
| `bash test/lint.sh` | **37 项通过，0 失败** |
| `bash test/selftest.sh` | **197 项通过，0 失败，0 跳过** |
| `/bin/bash test/selftest.sh`（系统 bash **3.2.57**） | 同样 **197 / 0 / 0** |
| 私有仓库那套 677 行自测指向新 CLI | 114 通过 / 2 失败（那 2 项是它自己找 `_shared/app` 文案表的路径假设） |
| 真实数据新旧 `--status --json` | 16 个目标，去掉 `generatedAt` 后**结构完全一致** |
| 陌生人验收（从 npm 包装出来、按 README 从零走） | `--init` → 改两行 → `--status`(1) → 备份(0) → `--status`(0) → `--verify`(0) → `--restore-drill`(0) → 从 bundle `clone --mirror` 还原成功 |
| `npm pack` | 10 个文件 / 45KB；装进临时 prefix 后 bin 软链正确、可执行位保留 |
| **变异测试**（往 CLI 副本里注入 3 个人造 bug，看测试是否有牙齿） | 关掉 sidecar 校验 → 4 项失败；关掉归属守卫 → 4 项失败；去掉 KEEP 轮转 → 46 项失败。**三个变异全部被抓** |

**尚未验证**：CI 还没跑过（仓库还没推上去）；Linux 只有代码级兼容，没有真机验证。

## 下一步

- [x] 收齐 `test/selftest.sh`，`npm test` 全绿；`/bin/bash test/selftest.sh`（3.2）也全绿
- [x] 补 `README.en.md`
- [ ] 整体搬到 `~/dev/dev-backup`（需要一次沙箱外的写权限批准），`git init` + 首次提交
- [ ] `gh repo create haotian-lu-prog/dev-backup --public --source . --push`
      （**Website 先留空**：还没发到 npm，公约禁止拿别的链接凑数）
- [ ] 推上去后看 CI 是否两个平台都绿（尤其 ubuntu 上的 GNU 分支）
- [ ] npm 首发 `dev-backup@1.0.0`；发完把 GitHub Website 回填成
      `https://www.npmjs.com/package/dev-backup`
- [ ] 本机切换：`_shared/bin/backup-dev.sh` 改成薄壳（`exec dev-backup --config ~/dev/_shared/backup-dev.conf "$@"`），
      个人约定（`ROOT` / `DEST` / `CONFIGS` / `LOGDIR` / `NOTIFY_TITLE`）搬进那份配置文件。
      **改完必须验证**：`git commit` 一次 → `$DEST/manifests/` 出现新 tsv、`--status` 退 0、
      插件与面板仍能读到 JSON。
- [ ] 顺手修私有仓库的已知隐患（见下）

## 未决问题

- **`_shared` 一侧的静默失效点**（搬迁时必须一起处理，否则会「提交照常、云盘再无新产物、零报警」）：
  - `git-hooks/post-commit` 在脚本不可执行时**静默 exit 0**；
  - `audit.sh` 把「备份脚本不存在」只算提醒（`rc` 仍 0），建议升级为 error；
  - `app/main.swift` 与 `backup-selftest.sh` 各自硬编码脚本路径（前者可用 `DEV_BACKUP_SCRIPT` 注入）。
- **`_shared/bin/backup-dev.sh:712`** 也有一处「变量后紧跟全角字符」（`$src）`），
  只在「配置白名单里的目标缺少快照」这条路径上触发 —— 属于潜伏 bug，切到公开版后自然消失。
- 私有仓库的 `_shared/app`（macOS 面板）**要不要也公开**？当前决定是只公开引擎；
  面板绑着签名身份与 TCC 授权，公开了别人也得自己签名。
- Linux 真机验证：作者手上没有 Linux 环境，目前只有 CI 覆盖。
