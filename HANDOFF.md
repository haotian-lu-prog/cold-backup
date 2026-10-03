# HANDOFF

> 三家的接力棒：DSH / Codex / Claude Code 都读这个文件。**开工先读，收工必更新并提交。**

## 当前写者

- 工具：DSH（**进行中，2026-10-03 11:30 +09:00 起**）
- 分支：main
- 开始时间：2026-10-03 11:30 (+09:00)
- 本轮：两处小改（都由本机 2026-10-03 的冷备链路改造触发，**未发布**，版本号等你定）：
  ① `--init` 模板里的 `FDA_APP` 默认值不再写死某个具体 app，改成「指向你自己那个跑本 CLI 的
  app」，并写清原因（FDA 授权绑在 app 的 bundle id + 代码签名上，脚本因 shebang 拿不到）；
  ② **修掉「仅大小写改名」导致的残留误报**：macOS 默认 APFS 不区分大小写，`snapshots/Scratch`
  与 `snapshots/scratch` 是**同一个目录**；工作区目录只改大小写后，纯字符串比较把**活目录**
  判成残留，而 `--prune-orphans --apply` 是 `rm -rf` —— 真机实测会删掉该目标的当前活快照
  （连 `.cold-backup-owner` 一起）。判据改成 `-ef`（同一 inode）比目录，见 `same_as_known_dir()`；
  自测新增 13b 节（macOS 验「同目录不算残留 + --apply 不许删」，Linux 验反向「真残留仍要报」）。
- 上一轮：**改名** —— 引擎 CLI `dev-backup` → **`cold-backup`**，与 DSH 插件
  `dsh-dev-backup` → `dsh-cold-backup` 同步：包名、可执行文件 `bin/cold-backup`、
  环境变量前缀 `DEV_BACKUP_*` → `COLD_BACKUP_*`、默认目录 `~/Library/Logs/cold-backup`（Linux
  `~/.local/state/cold-backup`）、配置文件 `~/.config/cold-backup/config`、JSON 契约
  `cold-backup.status/1`、归属标记 `.cold-backup-owner`、crontab 标记与 launchd label 一并换名，
  **不留旧名兼容**。本文件下文与 `docs/decisions.md` 里的旧名是当时的真实名称，作为历史记录不回改
  （下文出现的路径 `~/dev/dev-backup` 就是今天的 `~/dev/cold-backup`）。
- 上一轮：① 新增两个防护（都是 1.0.0 发布后实测出来的）：**`DEST` 不许落在工作区里**（会自我繁殖：
  快照把上一轮产物打进去，实测 3 轮 3194 → 6945 → 14110 字节）、**`schedule install --program`
  不可执行时当场警告**（否则任务每天静默失败）。② 试走 trusted publishing **失败**
  （CI `PUT` 404，npm 侧配置未匹配），最终**用本机 token 发布 1.0.1（无 provenance）**；
  排查线索与待办见「未决问题」。

> 一个仓库同一时刻只允许一个写者。交接时把上一行改成自己，并先读完下面的状态。

## 当前状态

**2026-10-02 追加（七）：修掉残留清理的「分组目录」误报，随 `1.0.3` 发布。**

- 改名那轮在本机撞见：`--status` 每天提示「清理：`--prune-orphans --apply`」，
  而被点名的 `repos/plugins` 下面装的正是六个插件的**活备份**（`repos/dsh` 同理，
  下面是活目标 `dsh/notify-v2`）。根因是 `orphan_scan()` 只看 `$DEST/repos/*` 的**第一层**，
  把分组目录也当成标签去比对。**`--apply` 是 `rm -rf`** —— 照工具自己的提示做就是删活产物。
- 修法：`find` 递归枚举 + 判据「等于某个已知目标，或是某个已知目标产物路径的前缀 → 跳过」。
  顺带把此前**根本列不出来**的嵌套真残留（`repos/plugins/dsh-dev-backup` 之类）纳入视野。
- 验证：`test/lint.sh` 39/39、`test/selftest.sh` **222/222**（新增第 26 节，11 项断言）、
  `test/frozen-clock.sh` **222/222**；**变异测试**（拿掉前缀判据）稳定红 6 项，
  其中就有「⑤ 活产物被误删」——证明这条护栏真的拦得住。
- 发布：`cold-backup@1.0.3`（本机 `npm publish`，无 provenance）+ Release `v1.0.3`，
  asset 就是 registry 那一份（sha256 `18ab00491515d932ba037b941354c8eb32e590964cb001b04b073ea3e3dfd74c`）。
- 本机私有脚本 `_shared/bin/backup-dev.sh` 同步修掉：真机 `--prune-orphans` 的 dry-run 里
  两个假阳性消失、两个嵌套真残留浮出（详见 `_shared/HANDOFF.md`）。
- `docs/compatibility.md` 写清嵌套标签与分组目录的判据，供下游自扫目录树时照抄。

**2026-10-02 追加（六）：改名 —— CLI `dev-backup` → `cold-backup`（本轮，已发布）。**

- 目录 `~/dev/dev-backup` → `~/dev/cold-backup`；可执行文件 `bin/dev-backup` → `bin/cold-backup`。
- 一次性换掉的标识：环境变量 `COLD_BACKUP_*`、配置文件 `~/.config/cold-backup/config`、
  macOS 日志目录 `~/Library/Logs/cold-backup`（其它平台 `~/.local/state/cold-backup`）、
  JSON schema `cold-backup.status/1`、归属标记 `.cold-backup-owner`、crontab 标记
  `# >>> cold-backup >>>`、launchd label 模板 `com.cold-backup.daily`、临时文件名前缀。
  **不留旧名兼容** —— 理由、代价与迁移命令见 `docs/decisions.md` 顶部与 `docs/compatibility.md` §7
  （旧标记在新版眼里等于「没标记」，按 `unowned` 处理，不会误删）。
- 验证：`test/lint.sh` **39/39**、`test/selftest.sh` **211/211**、`test/frozen-clock.sh` **211/211**。
- **顺手修掉一个真问题**（改名后跑 lint 时撞见的）：`--init --dry-run` 会在**真实**日志目录里建一个
  `tmp/` —— 与 `AGENTS.md`「自测只在临时目录里操作」的承诺矛盾，也让「dry-run 无副作用」不成立
  （本机 `~/Library/Logs/cold-backup/tmp` 就是这么冒出来的）。修法：把 `init` 并进那条
  「只读模式不建目录」的 `case`，并在 `test/lint.sh` 加一条断言（38 → **39** 项）钉住它。
- 发布面（同一天完成）：
  - GitHub 仓库改名 `dev-backup` → **`cold-backup`**（旧 URL 301 重定向已实测）；
    Website 按公约回填成 <https://www.npmjs.com/package/cold-backup>。
  - npm 新包 **`cold-backup@1.0.2`** 已发布（本机 `npm publish`，**无 provenance**）；
    旧包 `dev-backup` 的 1.0.0 / 1.0.1 / 1.0.2 三个版本已 deprecate 并指向新名。
  - 市场投稿换成 PR **#6410**（`data/plugins/haotian-lu-prog__dsh-cold-backup.yml`，+1 文件 / +6 行）；
    旧的 #6322 因分支改名被 GitHub 自动关闭，已在上面留了说明。
- 配对改动：DSH 插件 `dsh-dev-backup` → `dsh-cold-backup`（同一批次，见那个仓库）。

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
- 1.0.1 的发布方式：**本机 `npm publish`（无 provenance）**。CI 那条路（Release → trusted
  publishing）这次没走通，原因见「未决问题」；`dist-tags.latest = 1.0.1`，registry `dist.shasum`
  `29bc71770dd49cab53e5b264f99a0552980143cc`。Release asset 已按老规矩对齐成 registry 那一份
  （sha256 `37f780d227e6828aff1d4363c4d2a5357b879347dd9607653ced84662e3cde4d`，47432 字节）。

**2026-10-02 追加（1.0.2，未发布）：同秒并列的两个产品级修复 + 冻结时钟护栏**

- **缘起**：CI 上「按时序抽签」式地红（第 7、11、14 节先后失败；macOS 绿、ubuntu 红、重跑仍红）。
  根因是产物名**只有秒精度**：同一秒内为两个提交各备一次时，`ls | sort | tail -1`（按名取最新）
  退化成按 sha 后缀随机排。
- **顺着它挖出两个产品侧真问题**（不只测试）：
  ① `prune()` 按名保留最新 KEEP 份，并列时**可能把本轮刚写出的那份删掉** —— 而调用方刚报「备份成功」；
  ② `--verify` / `--restore-drill` 用「按名取最新」挑产物做深校验/演练，可能抓到**旧提交**那份，
  把一次完好的备份报成「不一致」。
- **修法**：`prune()` 增加第 3 个参数（本次刚写的产物永不删）；新增 `head_bundle_of()`，
  校验与演练优先挑 **HEAD 那一份**（HEAD 还没备上才退回最新）。
- **护栏**：新增 `test/frozen-clock.sh` —— 把产物时间戳钉成同一个值再跑整套自测，
  把「同一秒」从时序巧合变成**常态**。修复前它稳定红 2~7 项；修复后连续 3 轮全绿。
  已接进 CI（两个平台各跑一遍）。
- **测试侧**：自测里所有「按名取最新」改成按 HEAD 的 sha（第 7、11、14 节）。
- **1.0.2 已发布**：仍走本机 `npm publish`（**无 provenance**，trusted publishing 未匹配，见「未决问题」）。
  `dist-tags.latest = 1.0.2`，registry `dist.shasum` `c6be5421f114e0ca2a9b265ec49ed0a84a7e2a30`；
  Release asset 已按老规矩对齐成 registry 那一份（sha256 `b9d862e402ca457ba49c1c7e6922e9e097aecd8fffd12254bb9c20526c92b9e2`）。
  这一版的 Release 触发的 CI 发布**正确地跳过**了（日志：`dev-backup@1.0.2 is already on the registry`）。

**2026-10-02 追加（1.0.1 之后）：CI 上修掉一个「按时序翻车」的用例**

- **现象**：主分支 `ci` 在 ubuntu 上 4 项失败，而 macOS 绿、同一提交在 PR 上绿、重跑**仍然红**。
- **根因**：产物名只有**秒**精度。ubuntu runner 够快，自测里连续「提交 + 备份」会落在同一秒，
  两份产物的秒相同、只剩 sha 后缀可比 —— `ls | sort | tail -1`（「取最新」）退化成按 sha 随机排，
  可能挑到**旧提交**的产物；而自愈只为 HEAD 重建，损坏的旧产物不会被重建 → `--verify` 永远红。
  已用「造一份时间戳更晚的产物并损坏它」确定性复现。**是自测的假设错，不是产品错。**
- **修法**（纯测试侧）：7a/7b 改成按 **HEAD 的 sha** 挑产物（新增 `head_bundle`）；新增 7d 钉住
  产品侧真正重要的性质 —— **`--status` 的判据是 HEAD 的 sha，与文件名排序无关**；
  `docs/compatibility.md` 记下「同一秒的并列产物不可排序，消费方别依赖顺序」。
- **现状**：main 两个平台都绿（`dcdd385`，PR #6）；自测 **211 项**（ubuntu 上为 204 + 2 跳过 = 平台门控项）。

**CI**：两个平台都跑通了 —— `ubuntu-latest` 16s、`macos-latest` 1m17s（后者再用 `/bin/bash` 3.2
复跑一遍）。Linux 的 GNU 兼容层由此第一次得到真实验证（本机没有 Linux 环境，只有 CI）。

**仍未验证**：bash 5（本机只有 3.2，靠 lint 的 bash4 规则集 + 按构造兼容）；
非 macOS/非 Linux 平台不在支持范围内。

## 下一步

- [x] ~~**`1.0.3` 已就绪，正在发布**~~ → **已发布（2026-10-02）**：`dist-tags.latest = 1.0.3`，
  registry `dist.shasum = bae4f119899d6ecbeae6b21832a0b2e8ffba4d44`。
  Release `v1.0.3` 已建（tag → `c69d044`），asset `cold-backup-1.0.3.tgz` 就是 **registry 那一份**
  （53545 字节，sha256 `18ab00491515d932ba037b941354c8eb32e590964cb001b04b073ea3e3dfd74c`）。
  这一版 `npm pack` 与 registry **逐字节相同**（不再有 1.0.0~1.0.2 那种「字节不同、解包一致」的现象 ——
  因为这次本机 npm 与发布时的 npm 就是同一个）。CI：`publish` 正确地跳过（版本已在 registry 上）
  并 success，`ci` / `conventions` 也 success。
- [x] ~~**（改名后新增，优先）新包名要各自再配一次 trusted publishing**~~ → **2026-10-03 已配好并核对**：
  用户用网页配好两份，`npm trust list`（经 2FA）读回来都是
  `type: github / file: publish.yml / repository: haotian-lu-prog/cold-backup /
  permissions: publish, stage publish` —— 与工作流文件逐项对得上。插件侧那份同理
  （`haotian-lu-prog/dsh-cold-backup`）。旧包的两份配置已删除（`npm trust list dev-backup`
  → `E404`，即「没有配置」）。
  **但 OIDC 发布这条路还没被真实发版验过**（`workflow_dispatch` 会在「版本已在 registry 上」时
  跳过 publish 步骤，测不到 token 交换）—— 下一次发版即验证。
- [x] ~~**这个账号上的 bypass-2FA token 已无用**~~ → **已撤销**（2026-10-03）：
  `npm token revoke 371aff`（`dsh-dev publish`，2026-09-30 建）成功，`npm token list` 现在为空，
  用备份里的旧值实测 `npm whoami` → **401**。本机 `~/.npmrc` 现在是网页登录会话 token
  （读操作照常，写操作每次要过一次浏览器 2FA —— 所以正常发版请走 CI 的 OIDC）。
- [x] ~~**trusted publishing 没匹配上，待查**~~ → **作废（2026-10-03）**：这条清单针对的是
      **旧包名 `dev-backup`**；改名后新包 `cold-backup` 已单独配好 OIDC（见上一条），
      旧包已 deprecate、其 trusted publisher 也已删除（`npm trust list dev-backup` → `E404`）。
      原文保留只为查档：
      CI 的 `publish.yml` 跑到
      `npm publish` 那步报 `E404 PUT https://registry.npmjs.org/dev-backup`（npm 用 404 表示
      「不匹配 / 无权限」）。工作流本身与**已能成功发布**的 `dsh-dev-backup` 那份结构一致
      （`id-token: write`、无 `environment:`、`node-version: 24`、同样的 `npm publish` 命令），
      所以问题在 npm 侧那四项。按可能性排序逐一核对：
      1. **allowed actions 那一档**：若选的是「stage publish only」（默认），直接 `npm publish` 会被拒 ——
         这与症状最吻合（`dsh-dev-backup` 当初也是这样，改成 allow publish 后 1.1.1 才直接发出去）；
      2. **Environment** 必须**留空**（本工作流没有声明 `environment:`）；
      3. **Workflow filename** 必须是 `publish.yml`（不是 `.github/workflows/publish.yml`）；
      4. **Repository** 必须是 `dev-backup`（不带 owner 前缀）。
      核对完重跑失败的那次即可：`gh run rerun 37001740529 --failed`（工作流幂等，1.0.1 已在 registry 上，
      重跑会走到「已发布 → 跳过发布」；所以真要验证得等下一个版本，或先用一个 patch 版试）。
      本机 token 读不到该配置：`npm trust list dev-backup` 返回 403（需带 2FA 的会话）。
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

- [x] ~~**⚠ 残留清理有误报，照着提示 `--prune-orphans --apply` 会删掉活的产物**~~ →
  **2026-10-02 当日已修**，随 `1.0.3` 发布。根因：`orphan_scan()` 只枚举 `$DEST/repos/*` 的
  **直接**子目录，把 `repos/plugins` 这种分组目录也当成标签去比对；而标签带 `/` 的目标
  （如 `plugins/foo`）在备份目录里是**嵌套**的，父目录必然匹配不上 → 被报成残留。
  修法：`find` 递归枚举 + 判据「等于某个已知目标，或是某个已知目标产物路径的**前缀** → 跳过」。
  自测新增第 26 节（11 项断言）；变异测试（拿掉前缀判据）稳定红 6 项，其中就有「⑤ 活产物被误删」。
  本机私有脚本 `_shared/bin/backup-dev.sh` 同步修掉：真机 `--prune-orphans` 的 dry-run 里
  两个会误删活产物的假阳性（`repos/plugins`、`repos/dsh`）消失，同时浮出两个此前看不见的
  嵌套真残留（`repos/plugins/dsh-{archived-sessions-manager,dev-backup}`）。
  **下面保留原始的复现与影响记录，免得下次又当成新发现**：
  旧 `orphan_scan()` 的枚举方式是 `for dir in "$DEST/repos"/* ...`（只看第一层）。
  复现（不到 30 秒）：
  ```sh
  W=$(mktemp -d); mkdir -p "$W/ws/plugins/foo"
  (cd "$W/ws/plugins/foo" && git init -q && git -c user.email=t@t -c user.name=t commit -qm x --allow-empty)
  bin/cold-backup --root "$W/ws" --dest "$W/dest" --logdir "$W/logs" --trigger=t   # 备份
  bin/cold-backup --root "$W/ws" --dest "$W/dest" --logdir "$W/logs" --prune-orphans
  #   旧行为：· 待删 repos/plugins   ← 它下面装的正是 plugins/foo 的**活产物**
  #   新行为：✓ 没有残留目录
  ```
  1.0.2 及更早的版本在嵌套标签的工作区上**不要**跑 `--prune-orphans --apply`。
- **npm trusted publishing（本包）尚未生效**：CI 的 `npm publish` 报 `PUT` 404，排查清单见
  「下一步」第一条。在它修好之前，发版必须走本机 `npm publish`（**无 provenance**）——
  1.0.1 就是这么发的。
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
