# HANDOFF

> 三家的接力棒：DSH / Codex / Claude Code 都读这个文件。**开工先读，收工必更新并提交。**

## 当前写者

- 工具：（空 —— 2026-10-02 DSH 会话已收工：**1.0.1 两个防护 + 走 trusted publishing 首发验证**）
- 分支：main
- 开始时间：—
- 本轮：① 新增两个防护（都是 1.0.0 发布后实测出来的）：**`DEST` 不许落在工作区里**（会自我繁殖：
  快照把上一轮产物打进去，实测 3 轮 3194 → 6945 → 14110 字节）、**`schedule install --program`
  不可执行时当场警告**（否则任务每天静默失败）。② 用 1.0.1 验证 trusted publishing：
  Release → CI 直接发布、带 provenance，不再需要本机 npm 登录。

> 一个仓库同一时刻只允许一个写者。交接时把上一行改成自己，并先读完下面的状态。

## 当前状态

**已公开发布**：[GitHub](https://github.com/haotian-lu-prog/dev-backup)（public，
Website 已按公约回填成 npm 包页）与 [npm](https://www.npmjs.com/package/dev-backup)
（`dev-backup@1.0.0`，首发起始于本机 `npm publish`，registry shasum 与本地打包一致）。
本机源码就在 `~/dev/dev-backup`；下面这些是它在本机验证过的状态：
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
- 已修掉**五个**真 bug：① 三处「变量后紧跟全角字符」（bash 3.2 会中止）；
  ② `--status` 有副作用（建目录 / 轮转日志 / 写 `last-failure`）；③ `--prune-orphans`
  删除失败仍退出 0；④ `schedule install --at 25:00` 被管道吞掉失败、照样输出 plist 且退 0；
  ⑤ Linux 上没装 `crontab` 时 `schedule --dry-run` 直接失败（dry-run 不该依赖工具是否安装）。
- npm 形态已验证：`npm pack` 出 10 个文件 / 45KB；装进临时 prefix 后 `bin` 软链正确、
  可执行位保留、CLI 能跑（`npm pack --dry-run` 需要 `npm_config_cache` 指到工作区内）。
- 新增安全机制：`.dev-backup-owner` 归属标记 —— 别的工作区的产物**不写不删只报告**。
- 文档：README（中/英）、`docs/compatibility.md`、`docs/scheduling.md`、
  `docs/restore.md`、`docs/decisions.md`（8 条决策）。
- 已就位：`package.json`（npm 名 `dev-backup`，无依赖）、`install.sh`、MIT LICENSE、
  `.github/workflows/{ci,conventions,publish}.yml`（conventions 与 `_shared/ci/` 模板逐字节一致）。
- `test/selftest.sh`（715 行、25 节）：移植了私有仓库那套的全部引擎断言，
  丢掉面板/runner/钩子那几节，并补了配置优先级、`--init`、只读承诺、未配置 JSON、
  归属标记、`schedule --dry-run`、版本一致性、删除失败退出 1。
  夹具仓库显式把 `core.hooksPath` 指向空目录，免得本机全局钩子污染自测输出。

**已验证**（都在本机跑过，命令可复现）：

| 验证 | 结果 |
|---|---|
| `bash test/lint.sh` | **37 项通过，0 失败** |
| `bash test/selftest.sh` | **201 项通过，0 失败，0 跳过** |
| `/bin/bash test/selftest.sh`（系统 bash **3.2.57**） | 同样 **201 / 0 / 0** |
| 私有仓库那套 677 行自测指向新 CLI | 114 通过 / 2 失败（那 2 项是它自己找 `_shared/app` 文案表的路径假设） |
| 真实数据新旧 `--status --json` | 16 个目标，去掉 `generatedAt` 后**结构完全一致** |
| 陌生人验收（从 npm 包装出来、按 README 从零走） | `--init` → 改两行 → `--status`(1) → 备份(0) → `--status`(0) → `--verify`(0) → `--restore-drill`(0) → 从 bundle `clone --mirror` 还原成功 |
| `npm pack` | 10 个文件 / 45KB；装进临时 prefix 后 bin 软链正确、可执行位保留 |
| **变异测试**（往 CLI 副本里注入 3 个人造 bug，看测试是否有牙齿） | 关掉 sidecar 校验 → 4 项失败；关掉归属守卫 → 4 项失败；去掉 KEEP 轮转 → 46 项失败。**三个变异全部被抓** |
| 伪 Linux（`uname` 桩）跑非 Darwin 分支 | 194 通过 / 0 失败 / 2 跳过（mdls 与 FDA 探针，跳过被计数报出） |
| 无 `crontab` 的 PATH 下跑 `schedule --dry-run` | rc=0 且照常打印受管区块；真装才 rc=1 |

**2026-10-02 追加（1.0.1）：两个防护 + 发版链路验证**

- **`DEST` 落在工作区里 → 备份直接拒绝**（退出 1、不写任何产物、明说原因）：`SNAPSHOTS=1` 时
  快照会把上一轮的产物打进去、逐轮翻倍（实测 3 轮 3194 → 6945 → 14110 字节）；`DEST == ROOT` 一并拒绝。
  判定用规范化路径前缀（`canon_path`：存在的走 `pwd -P`，不存在的用「规范化父目录 + 名字」），
  `/tmp` 与 `/private/tmp` 这类软链写法不会被误判。
- **`schedule install --program <不可执行>` → 当场警告**（`--dry-run` 也警告）。只警告不失败 ——
  「先装任务、稍后再构建程序」是合理用法，但「每天静默失败」必须说出来。
- 自测 **210 项 / 0 失败 / 0 跳过**（新增第 25 节 9 项断言）；`test/lint.sh` 37 项。
- 1.0.1 走 **trusted publishing** 发布（不进 staging、带 provenance），见「下一步」第一条。

**CI**：两个平台都跑通了 —— `ubuntu-latest` 16s、`macos-latest` 1m17s（后者再用 `/bin/bash` 3.2
复跑一遍）。Linux 的 GNU 兼容层由此第一次得到真实验证（本机没有 Linux 环境，只有 CI）。

**仍未验证**：bash 5（本机只有 3.2，靠 lint 的 bash4 规则集 + 按构造兼容）；
非 macOS/非 Linux 平台不在支持范围内。

## 下一步

- [x] ~~**给 npm 配 trusted publishing**~~ → **用户已在 npm 侧配好**（2026-10-02），
      并由 **1.0.1** 走通：GitHub Release → `publish.yml` → 直接发布、带 provenance，无需本机 npm 登录。
      以后发版就是「bump version → tag → Release」三步。
- [ ] 用一段时间后，再评估要不要把**本机**冷备切到这个 CLI（本次用户明确决定保持现状，
      接口与产物契约没变，切换成本已被压到一个 5 行薄壳）。
- [ ] 若切换：`_shared/bin/backup-dev.sh` 换成 `exec dev-backup --config ~/dev/_shared/backup-dev.conf "$@"`，
      个人约定（`ROOT`/`DEST`/`CONFIGS`/`LOGDIR`/`NOTIFY_TITLE`）搬进那份配置文件；改完必须验证
      「`git commit` 一次 → `$DEST/manifests/` 出现新 tsv、`--status` 退 0、插件与面板仍能读到 JSON」。
- [x] ~~上游联动：`dsh-dev-backup` 插件 README 里 `statusJsonCommand` 的示例指向私有路径~~ →
      已随 **`dsh-dev-backup@1.1.1`** 发布：示例改成 `dev-backup --status --json`，
      中英 README 都新增了「与 dev-backup 的关系」（它不是必需的、两边互相独立），
      并写清「本插件的默认文件路径**就是**本 CLI 在 macOS 上的默认日志目录 —— 装两边一个字段都不用改」。
      插件侧记录见该仓库 `HANDOFF.md` 的「当前状态（五）」。

## 未决问题

- **`_shared` 的两个静默失效点已在 2026-10-02 修掉**（`_shared@697fef2`）：
  `git-hooks/post-commit` 找不到脚本时不再静默 `exit 0`（改为每次提交打印警告，仍 exit 0）；
  `audit.sh` 的「缺备份脚本」从提醒升级为错误。**两处都已实测**（缺脚本→有警告且 rc=0；
  有脚本→后台照常触发；`DEV_BACKUP_DISABLE=1`→安静退出）。
- **`_shared/bin/backup-dev.sh:712`** 有一处「变量后紧跟全角字符」（`$src）`），只在
  「配置白名单里的目标缺少快照」这条路径触发 —— 潜伏 bug，公开版里已修，私有版仍在（未切换）。
- **两实现并存的漂移风险**：本机跑私有脚本、公开版是另一份。契约面（JSON / 退出码 / 产物布局 /
  `last-ok` / `last-failure`）已冻结，改任一侧都要同步另一侧 —— 这是「不切换」的已知代价，
  记在 `_shared/docs/decisions.md`。
- 私有仓库的 `_shared/app`（macOS 面板）**要不要也公开**？当前决定是只公开引擎；
  面板绑着签名身份与 TCC 授权，公开了别人也得自己签名。
- **bash 5 未实测**（本机只有 3.2，靠 lint 的 bash4 规则集 + 按构造兼容）；
  **Linux 真机未手工验证**，只有 CI（`ubuntu-latest`）覆盖。
