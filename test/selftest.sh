#!/usr/bin/env bash
# dev-backup 端到端自测：在临时工作区里造 git 仓库与非 git 目录，把整条链路真跑一遍。
#   备份 → 幂等 → 状态 → 校验 → 还原演练 → 落后检测 → KEEP 轮转 → 快照去重 → 损坏自愈 →
#   失败信号 → stash → 配置白名单/密钥预检 → 残留清理 → JSON 契约 → 每日巡检 →
#   配置优先级 → --init → 只读承诺 → 未配置 → 归属标记 → schedule → 版本 → 删除失败 → 平台项
#
# 隔离：全程只用 mktemp -d 造的临时目录；开头强制 DEV_BACKUP_CONFIG 指向不存在的路径
# （否则开发机上真实的 ~/.config/dev-backup/config 会污染每一项判定）；不写真实备份目录、
# 不装定时任务（schedule 只跑 --dry-run）、不发桌面通知（DEV_BACKUP_NO_NOTIFY=1，通知路径用桩验证）。
#
# 用法：
#   bash test/selftest.sh                            # 用 PATH 里的 bash
#   /bin/bash test/selftest.sh                       # macOS 系统自带 bash 3.2
#   BIN=/path/to/dev-backup bash test/selftest.sh    # 换被测对象
#
# 退出码：0 = 全部断言通过；1 = 有断言失败（跳过项不算失败，但会在结尾计数报出）。
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
BIN="${BIN:-$REPO/bin/dev-backup}"
[ -x "$BIN" ] || { printf '找不到可执行的 %s\n' "$BIN"; exit 2; }

pass=0; fail=0; skipped=0
ok()  { printf '   ✓ %s\n' "$*"; pass=$((pass + 1)); }
no()  { printf '   ✗ %s\n' "$*"; fail=$((fail + 1)); }
eq()  { if [ "$2" = "$3" ]; then ok "${1}（$2）"; else no "${1}：期望 $3，实得 $2"; fi; }
# 平台/环境导致的跳过：必须计数，不能静默
skip() { printf '   - 跳过：%s\n' "$*"; skipped=$((skipped + 1)); }
hdr()  { printf '\n== %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
sha_stdin() { # 与引擎同一套指纹口径（macOS 用 shasum，Linux 用 sha256sum）
  if have shasum; then shasum -a 256 | cut -d' ' -f1; else sha256sum | cut -d' ' -f1; fi
}
jstr() { # $1=JSON 文本 $2=键名 → 字符串字段的值（本 CLI 的 JSON 每个字段独占一行）
  printf '%s\n' "$1" | sed -n 's/.*"'"$2"'": "\([^"]*\)".*/\1/p' | head -1
}
jline() { # $1=JSON 文本 $2=键名 → 该键所在的那一行（原样）
  printf '%s\n' "$1" | grep -m1 -- "\"$2\"" || true
}
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

W="$(mktemp -d "${TMPDIR:-/tmp}/dev-backup-selftest.XXXXXX")" || exit 2
W="$(cd "$W" && pwd -P)"   # TMPDIR 可能带尾斜杠，规范化后再用，避免前缀比较误判
# H 节会把一个目录 chmod 500；退出前先恢复权限，否则临时目录删不干净
cleanup() { chmod -R u+rwX "$W" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT

export DEV_BACKUP_CONFIG="$W/no-such-config"   # 隔离的关键：绝不读开发机上真实的配置文件
export DEV_BACKUP_NO_NOTIFY=1
export DEV_BACKUP_KEEP=2
export DEV_BACKUP_LOGDIR="$W/logs"
export DEV_ROOT="$W/dev"
export DEV_BACKUP_DEST="$W/cloud/dev-backup"
export DEV_BACKUP_CONFIGS=off                  # 配置冷备默认 off；需要时在对应小节显式打开
mkdir -p "$DEV_ROOT/scratch" "$W/cloud"
printf 'hello\n' >"$DEV_ROOT/scratch/a.txt"

printf '== dev-backup 端到端自测\n'
printf '   被测：%s\n' "$BIN"
printf '   工作区：%s → 备份到：%s\n' "$DEV_ROOT" "$DEV_BACKUP_DEST"
printf '   bash：%s    平台：%s\n' "${BASH_VERSION:-?}" "$(uname -s)"

run()  { "$BIN" --trigger=selftest "$@" >/dev/null 2>&1; }
lines() { cat "$DEV_BACKUP_DEST"/manifests/*.tsv 2>/dev/null | wc -l | tr -d ' '; }
nf()   { ls -1 "$1"/$2 2>/dev/null | wc -l | tr -d ' '; }   # 数产物个数
ref_fp() { # ref 指纹：与引擎 --restore-drill 同一口径（不含 refs/remotes/*，那是派生状态）
  git -C "$1" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null \
    | grep -v '^refs/remotes/' | sha_stdin
}

hdr "0 冒烟"
have git && ok "有 git" || no "找不到 git（后面全都跑不了）"
"$BIN" --version >/dev/null 2>&1; eq "--version 退出码" "$?" "0"
out="$("$BIN" --help 2>&1)"; eq "--help 退出码" "$?" "0"
for kw in --status --verify --daily --restore-drill --prune-orphans --init schedule; do
  contains "$out" "$kw" && ok "--help 提到 ${kw}" || no "--help 没提到 ${kw}"
done

# ── 造一个仓库 ──────────────────────────────────────────────────────────────
# 本机（或 CI）可能装了全局 git 钩子（core.hooksPath）——提交时跑备份、跑仓库公约检查。
# 自测必须与机器无关：这里把夹具仓库的钩子路径指到一个空目录，全局钩子一律不生效。
R="$DEV_ROOT/demo"
mkdir -p "$R" "$W/empty-hooks"
git init -q "$R"
git -C "$R" config core.hooksPath "$W/empty-hooks"
git -C "$R" config user.email selftest@example.com
git -C "$R" config user.name selftest
for i in 1 2 3; do
  printf 'line %s\n' "$i" >>"$R/f.txt"
  git -C "$R" add -A
  git -C "$R" commit -qm "chore: c${i}"
done
head="$(git -C "$R" rev-parse HEAD)"

hdr "1 备份与幂等"
run
eq "备份退出码" "$?" "0"
eq "bundle 个数" "$(nf "$DEV_BACKUP_DEST/repos/demo" '*.bundle')" "1"
b0="$(ls -1 "$DEV_BACKUP_DEST/repos/demo"/*.bundle 2>/dev/null | head -1)"
contains "$(basename "$b0")" "-${head:0:12}.bundle" && ok "bundle 文件名带当前提交（${head:0:12}）" \
  || no "bundle 文件名没带当前提交：$(basename "$b0")"
[ -f "$b0.sha256" ] && ok "bundle 带 .sha256 指纹" || no "bundle 缺 .sha256 指纹"
n1="$(lines)"
[ "${n1:-0}" -ge 2 ] && ok "manifest 有记录（${n1} 行：仓库 + 快照）" || no "manifest 记录异常（${n1} 行）"
[ -f "$DEV_BACKUP_DEST/README.md" ] && ok "写了给人看的 README.md" || no "没写 README.md"

hdr "2 幂等"
run
eq "重跑后 manifest 行数不变" "$(lines)" "$n1"
eq "重跑后 bundle 个数不变" "$(nf "$DEV_BACKUP_DEST/repos/demo" '*.bundle')" "1"
"$BIN" --status >/dev/null 2>&1; eq "--status 退出码（最新提交已备份）" "$?" "0"
"$BIN" --verify >/dev/null 2>&1; eq "--verify 退出码" "$?" "0"
"$BIN" --status --json >/dev/null 2>&1; eq "--status --json 退出码与 --status 一致" "$?" "0"

hdr "3 还原演练（提交数 + ref 指纹 + 工作副本 HEAD）"
"$BIN" --restore-drill "$W/drill" >/dev/null 2>&1; eq "--restore-drill 退出码" "$?" "0"
if [ -d "$W/drill/demo.git" ]; then
  eq "镜像还原的提交数" "$(git -C "$W/drill/demo.git" rev-list --count --all)" \
     "$(git -C "$R" rev-list --count --all)"
  eq "镜像还原的 ref 指纹" "$(ref_fp "$W/drill/demo.git")" "$(ref_fp "$R")"
  eq "工作副本 HEAD 一致" "$(git -C "$W/drill/demo" rev-parse HEAD 2>/dev/null)" "$(git -C "$R" rev-parse HEAD)"
else
  no "镜像还原目录不存在：$W/drill/demo.git"
fi

hdr "4 落后检测与 KEEP 轮转"
printf 'more\n' >>"$R/f.txt"
git -C "$R" add -A
git -C "$R" commit -qm "chore: c4"
"$BIN" --status >/dev/null 2>&1; eq "--status 退出码（有未备份的新提交）" "$?" "1"
run
eq "备份后 --status 退出码" "$("$BIN" --status >/dev/null 2>&1; printf '%s' "$?")" "0"
eq "KEEP=2：bundle 保留数" "$(nf "$DEV_BACKUP_DEST/repos/demo" '*.bundle')" "2"

hdr "5 落后检测：HEAD 的 bundle 在就不算落后（不吃「文件名最大那份」的亏）"
# 回归：先备份 A，再提交 B 并备份，然后 reset 回 A。此时 HEAD 是 A、A 的 bundle 也在，
# 但 B 的 bundle 文件名时间戳更晚。按「文件名最大的那份」判定会**永久**误报落后。
rm -f "$DEV_BACKUP_DEST/repos/demo"/*.bundle "$DEV_BACKUP_DEST/repos/demo"/*.sha256 2>/dev/null
base="$(git -C "$R" rev-parse HEAD)"
run
if ls "$DEV_BACKUP_DEST/repos/demo"/*-"$(printf '%s' "$base" | cut -c1-12)".bundle >/dev/null 2>&1; then
  ok "用例前提：base 提交的 bundle 已存在"
else
  no "用例本身失效：没能为 base 建出 bundle"
fi
printf 'ahead\n' >>"$R/f.txt"
git -C "$R" add -A
git -C "$R" commit -qm "chore: ahead"
run
ahead="$(git -C "$R" rev-parse HEAD)"
"$BIN" --status >/dev/null 2>&1; eq "新提交备份后 --status 退出码" "$?" "0"
git -C "$R" reset -q --hard "$base"
out="$("$BIN" --status 2>&1)"; rc=$?
eq "HEAD 的 bundle 在时 --status 退出码（不被更晚的文件名误导）" "$rc" "0"
contains "$out" '备份落后' && no "--status 误报「落后」：HEAD 的 bundle 明明在" || ok "--status 没误报落后"
# 反向确认：HEAD 真的没有 bundle 时必须报落后
git -C "$R" reset -q --hard "$ahead"
ashort="$(git -C "$R" rev-parse --short=12 HEAD)"
rm -f "$DEV_BACKUP_DEST/repos/demo"/*-"$ashort".bundle "$DEV_BACKUP_DEST/repos/demo"/*-"$ashort".bundle.sha256 2>/dev/null
"$BIN" --status >/dev/null 2>&1; eq "删掉 HEAD 的 bundle 后 --status 退出码" "$?" "1"
run
"$BIN" --status >/dev/null 2>&1; eq "重建后 --status 退出码" "$?" "0"

hdr "6 快照内容指纹去重"
before="$(nf "$DEV_BACKUP_DEST/snapshots/scratch" '*.tar.gz')"
run; after="$(nf "$DEV_BACKUP_DEST/snapshots/scratch" '*.tar.gz')"
eq "内容未变时不新增快照" "$after" "$before"
printf 'changed\n' >>"$DEV_ROOT/scratch/a.txt"
run
eq "内容变化后新增快照" "$(nf "$DEV_BACKUP_DEST/snapshots/scratch" '*.tar.gz')" "$((before + 1))"
cases="$(ls -1 "$DEV_BACKUP_DEST/snapshots/scratch"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
run
eq "再次重跑仍不新增（指纹在文件名里）" "$(nf "$DEV_BACKUP_DEST/snapshots/scratch" '*.tar.gz')" "$cases"

hdr "7 损坏自愈三态"
# 7a「尾部垃圾 + sidecar 不匹配」：这种 git bundle verify 抓不到，只有真 clone 才能发现
b="$(ls -1 "$DEV_BACKUP_DEST/repos/demo"/*.bundle | sort | tail -1)"
printf 'x' >>"$b"
"$BIN" --verify >/dev/null 2>&1; eq "--verify 对「尾部垃圾」bundle 的退出码" "$?" "1"
run
"$BIN" --verify >/dev/null 2>&1; eq "重跑后自愈，--verify 退出码" "$?" "0"
eq "自愈后 bundle 个数（KEEP=2）" "$(nf "$DEV_BACKUP_DEST/repos/demo" '*.bundle')" "2"
# 7b「sidecar 缺失 + 内容损坏」：缺失的 sidecar 绝不能被当成「通过」
b="$(ls -1 "$DEV_BACKUP_DEST/repos/demo"/*.bundle | sort | tail -1)"
printf 'x' >>"$b"; rm -f "$b.sha256"
"$BIN" --verify >/dev/null 2>&1; eq "--verify 对「无 sidecar + 损坏」的退出码" "$?" "1"
run
b="$(ls -1 "$DEV_BACKUP_DEST/repos/demo"/*.bundle | sort | tail -1)"
[ -f "$b.sha256" ] && ok "重跑后重建了产物并补回 .sha256" || no "重跑后 .sha256 仍缺失"
# 7c 同一提交有两份产物、坏的是**最新**那份：自愈必须扫描全部匹配文件，不能只看第一个
bdir="$DEV_BACKUP_DEST/repos/demo"
hshort="$(git -C "$R" rev-parse --short=12 HEAD)"
good="$(ls -1 "$bdir"/*-"$hshort".bundle 2>/dev/null | head -1)"
if [ -n "$good" ]; then
  cp "$good" "$bdir/demo-29990101T000000Z-$hshort.bundle"
  printf 'x' >>"$bdir/demo-29990101T000000Z-$hshort.bundle"
  run
  "$BIN" --verify >/dev/null 2>&1
  eq "同提交多份产物：坏的是最新那份也能自愈" "$?" "0"
  [ -f "$bdir/demo-29990101T000000Z-$hshort.bundle" ] && no "损坏的副本没被清掉" \
    || ok "损坏的副本已清掉，完好那份保留"
else
  no "7c 用例本身失效：找不到 HEAD 的 bundle"
fi
"$BIN" --verify >/dev/null 2>&1; eq "重建后 --verify 退出码" "$?" "0"

hdr "8 失败信号（last-failure + 日志 + --status 如实报告）"
rm -f "$DEV_BACKUP_LOGDIR/last-failure"
DEV_BACKUP_DEST="$W/does-not-exist/backup" "$BIN" --trigger=selftest >/dev/null 2>&1
eq "目标上级目录不存在时退出码" "$?" "1"
[ -f "$DEV_BACKUP_LOGDIR/last-failure" ] && ok "写了 last-failure 标记" || no "没写 last-failure 标记"
grep -q '备份目标的上级目录不存在' "$DEV_BACKUP_LOGDIR/backup.log" 2>/dev/null \
  && ok "日志里记了失败原因" || no "日志里没有失败原因"
out="$("$BIN" --status 2>&1)"; rc=$?
eq "--status 退出码（上一轮失败过）" "$rc" "1"
contains "$out" '上次运行失败' && ok "--status 如实报告「上次运行失败」" || no "--status 没报告上次失败"
run
[ -f "$DEV_BACKUP_LOGDIR/last-failure" ] && no "成功的一轮没清掉 last-failure" || ok "成功的一轮清掉了 last-failure"

hdr "9 --verify 的失败必须可见（rc 与 --fix 语义）"
DEV_BACKUP_DEST="$W/does-not-exist/backup" "$BIN" --verify >/dev/null 2>&1
eq "DEST 整目录不存在时 --verify 退出码" "$?" "1"
rm -rf "$DEV_BACKUP_DEST/repos/demo"
"$BIN" --verify >/dev/null 2>&1; eq "仓库没有任何产物时 --verify 退出码" "$?" "1"
run   # 重建
old="$(ls -1 "$DEV_BACKUP_DEST/repos/demo"/*.bundle 2>/dev/null | sort | head -1)"
if [ -n "$old" ]; then
  printf 'x' >>"$old"
  "$BIN" --verify >/dev/null 2>&1; eq "旧产物（非最新）损坏时 --verify 退出码" "$?" "1"
  "$BIN" --verify --fix >/dev/null 2>&1; fixrc=$?
  eq "--fix 退出码（发现损坏仍报 1）" "$fixrc" "1"
  [ -f "$old" ] && no "--fix 没删掉损坏的旧产物" || ok "--fix 删掉了损坏的旧产物"
  run   # 删掉的是唯一那份，重跑把它补回来
  "$BIN" --verify >/dev/null 2>&1; eq "重建后 --verify 退出码" "$?" "0"
else
  no "没拿到用于损坏测试的旧产物"
fi

hdr "10 快照被删后必须重建，且删光时要报错"
if [ -n "$(ls -1 "$DEV_BACKUP_DEST/snapshots/scratch"/*.tar.gz 2>/dev/null)" ]; then
  # 只删最新那份不算故障（还有更旧的一份可用）；删光才是
  rm -f "$DEV_BACKUP_DEST/snapshots/scratch"/*.tar.gz
  "$BIN" --status >/dev/null 2>&1; eq "快照全被删时 --status 退出码" "$?" "1"
  run
  [ -n "$(ls -1 "$DEV_BACKUP_DEST/snapshots/scratch"/*.tar.gz 2>/dev/null)" ] \
    && ok "重跑后快照被重建" || no "重跑后快照仍缺失"
  "$BIN" --status >/dev/null 2>&1; eq "重建后 --status 退出码" "$?" "0"
else
  no "没找到 scratch 快照"
fi

hdr "11 refs/stash 也要进 bundle"
# 先造一个新提交：同一提交已有完好 bundle 时引擎会跳过打包，stash 就进不了产物
printf 'stash-base\n' >>"$R/f.txt"
git -C "$R" add -A
git -C "$R" commit -qm "chore: stash base"
printf 'stashme\n' >>"$R/f.txt"
if git -C "$R" stash -q 2>/dev/null && git -C "$R" rev-parse --verify -q refs/stash >/dev/null 2>&1; then
  run
  st="$(ls -1 "$DEV_BACKUP_DEST/repos/demo"/*.bundle | sort | tail -1)"
  git bundle list-heads "$st" 2>/dev/null | grep -q 'refs/stash' \
    && ok "bundle 里含 refs/stash" || no "bundle 里缺 refs/stash（stash 内容会丢）"
  "$BIN" --restore-drill "$W/drill-stash" >/dev/null 2>&1
  eq "--restore-drill（含 stash）退出码" "$?" "0"
  git -C "$W/drill-stash/demo.git" rev-parse --verify -q refs/stash >/dev/null 2>&1 \
    && ok "镜像还原后 refs/stash 仍在（可 git stash pop）" || no "镜像还原后 refs/stash 丢了"
else
  no "用例本身失效：没能造出 stash"
fi

hdr "12 工具配置白名单 + 密钥预检"
FAKE_HOME="$W/home"
mkdir -p "$FAKE_HOME/fake-claude/plugins" "$FAKE_HOME/fake-codex"
printf '{"theme":"auto"}\n' >"$FAKE_HOME/fake-claude/settings.json"
printf '# 指令\n内容\n' >"$FAKE_HOME/fake-claude/CLAUDE.md"
printf '{"plugin":"keep"}\n' >"$FAKE_HOME/fake-claude/plugins/keep.json"
printf '[model]\nname="x"\n' >"$FAKE_HOME/fake-codex/config.toml"
export DEV_BACKUP_CONFIGS="claude-config|$FAKE_HOME/fake-claude|settings.json,CLAUDE.md,plugins;codex-config|$FAKE_HOME/fake-codex|config.toml"
cfgfiles() { nf "$DEV_BACKUP_DEST/configs/$1" '*.tar.gz'; }
run; eq "配置备份退出码" "$?" "0"
eq "claude-config 产物数" "$(cfgfiles claude-config)" "1"
eq "codex-config 产物数" "$(cfgfiles codex-config)" "1"
run
eq "重跑后不新增（指纹写在文件名里）" "$(cfgfiles claude-config)" "1"
"$BIN" --status >/dev/null 2>&1; eq "配置目标计入 --status" "$?" "0"
mkdir -p "$W/cfgout"
tar -xzf "$(ls -1 "$DEV_BACKUP_DEST"/configs/claude-config/*.tar.gz | head -1)" -C "$W/cfgout" 2>/dev/null
diff -r "$FAKE_HOME/fake-claude" "$W/cfgout" >/dev/null 2>&1 \
  && ok "解压内容与源目录一致" || no "解压内容与源目录不一致"
# node_modules 既不该进快照，也不该让密钥预检误报。
# 实测过的坑：第三方代码里的 `token: '…'` 撞上 token/key 规则，会让整份配置被跳过、
# 每日任务连续退出码 1 —— 而那是可重装的依赖，不是「配置」。
mkdir -p "$FAKE_HOME/fake-claude/plugins/node_modules/@x"
printf "token: 'abcdefghijklmnopqrstuvwxyz123456'\n" >"$FAKE_HOME/fake-claude/plugins/node_modules/@x/bad.js"
printf '{"theme":"dark"}\n' >"$FAKE_HOME/fake-claude/settings.json"
run
eq "node_modules 里有疑似密钥也不跳过整份（退出码）" "$?" "0"
latest_cfg="$(ls -1 "$DEV_BACKUP_DEST"/configs/claude-config/*.tar.gz 2>/dev/null | sort | tail -1)"
tar -tzf "$latest_cfg" 2>/dev/null | grep -q 'node_modules' \
  && no "node_modules 进了配置快照（应排除）" || ok "node_modules 未进配置快照"
tar -tzf "$latest_cfg" 2>/dev/null | grep -q 'plugins/keep.json' \
  && ok "白名单里的其他内容仍在快照里（排除没误伤）" || no "排除 node_modules 时把真配置也排掉了"
rm -rf "$FAKE_HOME/fake-claude/plugins/node_modules"
# 预检的词边界：`ask-codex-...` 这类路径里也含 "sk-"，不锚定就会误报
printf '[projects."/x/ask-codex-to-look-across-your"]\ntrust=1\n' >"$FAKE_HOME/fake-codex/config.toml"
run; eq "路径里含 ask-codex- 不误报（仍退出 0）" "$?" "0"
before_cfg="$(cfgfiles codex-config)"
printf '[model]\napi_key = "abcdefghijklmnopqrstuvwxyz123456"\n' >"$FAKE_HOME/fake-codex/config.toml"
run; eq "含真密钥时整轮退出码" "$?" "1"
eq "含密钥的配置没有新增产物" "$(cfgfiles codex-config)" "$before_cfg"
[ -f "$DEV_BACKUP_LOGDIR/last-failure" ] && ok "写了 last-failure 标记" || no "没写 last-failure 标记"
grep -q '疑似密钥' "$DEV_BACKUP_LOGDIR/backup.log" 2>/dev/null \
  && ok "日志里有跳过原因" || no "日志里没有跳过原因"
printf '[model]\nname="x"\n' >"$FAKE_HOME/fake-codex/config.toml"   # 夹具复原，后面还要用
run; eq "夹具复原后恢复退出 0" "$?" "0"

hdr "13 --prune-orphans（默认 dry-run，--apply 才删）"
mkdir -p "$DEV_BACKUP_DEST/repos/ghost-dir" "$DEV_BACKUP_DEST/snapshots/ghost-snap" "$DEV_BACKUP_DEST/configs/ghost-cfg"
printf 'x' >"$DEV_BACKUP_DEST/repos/ghost-dir/x.bundle"
"$BIN" --prune-orphans >/dev/null 2>&1; eq "--prune-orphans（默认 dry-run）退出码" "$?" "0"
[ -d "$DEV_BACKUP_DEST/repos/ghost-dir" ] && ok "dry-run 不删任何东西" || no "dry-run 竟然删了东西"
"$BIN" --prune-orphans --apply >/dev/null 2>&1; eq "--prune-orphans --apply 退出码" "$?" "0"
for gone in repos/ghost-dir snapshots/ghost-snap configs/ghost-cfg; do
  [ -d "$DEV_BACKUP_DEST/$gone" ] && no "残留没清掉：${gone}" || ok "已清掉残留：${gone}"
done
[ -d "$DEV_BACKUP_DEST/repos/demo" ] && ok "真目标目录（repos/demo）未被误删" || no "真目标 repos/demo 被误删"
[ -n "$(ls -1 "$DEV_BACKUP_DEST/repos/demo"/*.bundle 2>/dev/null)" ] && ok "真目标的产物仍在" || no "真目标的产物没了"
[ -d "$DEV_BACKUP_DEST/configs/claude-config" ] && ok "真配置目标未被误删" || no "真配置目标被误删"
"$BIN" --prune-orphans >/dev/null 2>&1; eq "清理后再跑一次仍退出 0（无残留）" "$?" "0"

hdr "14 JSON 契约（dev-backup.status/1）：一次判定、两种渲染"
"$BIN" --status --json >"$W/status.json" 2>"$W/status.err"
eq "--status --json 退出码（一切正常）" "$?" "0"
[ -s "$W/status.err" ] && no "JSON 模式不该往 stderr 写东西：$(cat "$W/status.err")" || ok "JSON 模式 stderr 干净"
grep -qF '"schema": "dev-backup.status/1"' "$W/status.json" && ok "带 schema 字段" || no "缺 schema 字段"
grep -qF '"verdict": "ok"' "$W/status.json" && ok "verdict=ok" || no "verdict 不是 ok"
grep -qF '"reasons": []' "$W/status.json" && ok "reasons 为空" || no "reasons 不为空"
grep -qF '"orphans": []' "$W/status.json" && ok "orphans 为空（没有残留）" || no "orphans 不为空"

if have python3; then
  if python3 - "$W/status.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["schema"] == "dev-backup.status/1", d.get("schema")
assert d["verdict"] == "ok", d["verdict"]
assert d["reasons"] == [], d["reasons"]
assert d["orphans"] == [], d["orphans"]
assert d["lastFailure"] is None, d["lastFailure"]
assert d["root"] and d["dest"], d
kinds = {}
for t in d["targets"]:
    kinds[t["kind"]] = kinds.get(t["kind"], 0) + 1
    assert t["state"] in ("ok", "missing", "behind", "skipped"), t
    assert t["upload"] in ("uploaded", "uploading", "stale", "unknown-nomdls", "unknown-cloud"), t
    if t["kind"] == "repo" and t["state"] == "ok":
        assert len(str(t["sha256"])) == 64, ("repo 缺 sha256", t)
    if t["kind"] in ("snapshot", "config"):
        assert t["sha256"] is None, ("快照/配置没有 sidecar，应为 null", t)
assert kinds.get("repo", 0) == d["counts"]["repos"], (kinds, d["counts"])
assert kinds.get("snapshot", 0) == d["counts"]["snapshots"], (kinds, d["counts"])
assert kinds.get("config", 0) == d["counts"]["configs"], (kinds, d["counts"])
assert d["counts"]["problems"] == 0, d["counts"]
assert d["counts"]["orphans"] == 0, d["counts"]
assert d["lastOk"] and str(d["lastOk"]).isdigit(), d["lastOk"]
PY
  then
    ok "JSON 自洽（schema/verdict/reasons/counts/字段枚举/sha256 语义）"
  else
    no "JSON 不自洽（见上）"
  fi
  # 「一次判定、两种渲染」的回归护栏：人读的 ✓ 行数必须等于 JSON 里 state=ok 的条数。
  # 人读的 ✓ 行有两类：每个目标一行，外加一行收尾句。所以要比 +1。
  human_ok="$("$BIN" --status 2>/dev/null | grep -c '^  ✓ ' || true)"
  json_ok="$(python3 -c 'import json,sys;print(sum(1 for t in json.load(open(sys.argv[1], encoding="utf-8"))["targets"] if t["state"]=="ok"))' "$W/status.json")"
  eq "人读 ✓ 行数 == JSON state=ok 条数 + 收尾句" "$human_ok" "$((json_ok + 1))"
else
  skip "JSON 结构深校验（没有 python3）"
fi

# 坏状态：删掉 demo 的产物 → verdict=bad、reason 能定位到目标，rc 与 --status 一致
demo_b="$(ls -1 "$DEV_BACKUP_DEST/repos/demo"/*.bundle 2>/dev/null | sort | tail -1)"
rm -f "$demo_b" "$demo_b.sha256"
"$BIN" --status --json >"$W/status-bad.json" 2>&1
eq "--status --json 退出码（少了 demo 的产物）" "$?" "1"
grep -qF '"verdict": "bad"' "$W/status-bad.json" && ok "verdict 变成 bad" || no "verdict 没变成 bad"
grep -qF '"target": "demo"' "$W/status-bad.json" && ok "reasons 定位到 demo" || no "reasons 没定位到 demo"
run
"$BIN" --status --json >/dev/null 2>&1; eq "重建后 --status --json 恢复 0" "$?" "0"

# 备份目录不存在：仍然必须给**合法 JSON**（消费方不该因为一个 rc=1 就解析失败）
DEV_BACKUP_DEST="$W/no-such-dest" "$BIN" --status --json >"$W/status-nodest.json" 2>&1
eq "--status --json（DEST 不存在）退出码" "$?" "1"
grep -qF '"code": "dest-missing"' "$W/status-nodest.json" && ok "给出 dest-missing 原因" || no "缺 dest-missing 原因"
grep -qF '"verdict": "bad"' "$W/status-nodest.json" && ok "DEST 不存在时 verdict=bad" || no "DEST 不存在时 verdict 不对"
grep -qF '"targets": []' "$W/status-nodest.json" && ok "DEST 不存在时 targets 为空" || no "DEST 不存在时 targets 不为空"
if have python3; then
  python3 -c 'import json,sys;d=json.load(open(sys.argv[1], encoding="utf-8"));assert d["verdict"]=="bad" and d["targets"]==[] and d["schema"]=="dev-backup.status/1"' "$W/status-nodest.json" \
    && ok "DEST 不存在时 JSON 仍可解析且结构完整" || no "DEST 不存在时 JSON 不合法"
fi

# --json 的糖与边界
"$BIN" --json >"$W/status-sugar.json" 2>&1; eq "--json（省略 --status）退出码" "$?" "0"
grep -qF '"schema": "dev-backup.status/1"' "$W/status-sugar.json" && ok "--json 等价于 --status --json" || no "--json 没输出 JSON"
"$BIN" --verify --json >/dev/null 2>&1; eq "--json 配 --verify 明确报错" "$?" "2"
"$BIN" --bogus >/dev/null 2>&1; eq "未知参数退出码" "$?" "2"

hdr "15 --daily 每日巡检（补跑备份 + 逐份校验 + 状态检查）"
printf 'daily\n' >>"$R/f.txt"
git -C "$R" add -A
git -C "$R" commit -qm "chore: daily"
"$BIN" --daily >/dev/null 2>&1; eq "--daily 退出码" "$?" "0"
if ls "$DEV_BACKUP_DEST"/manifests/*-daily.tsv >/dev/null 2>&1; then
  ok "清单记下了触发源 daily"
else
  no "没有 *-daily.tsv 清单（--trigger 没变成 daily？）"
fi
"$BIN" --status >/dev/null 2>&1; eq "巡检后 --status 退出码" "$?" "0"

hdr "16 A 配置优先级（命令行 > 环境变量 > 配置文件 > 内置默认）"
CONF_A="$W/conf/a.conf"
mkdir -p "$W/conf"
cat >"$CONF_A" <<EOF
# 自测用配置文件（KEY=VALUE，一行一个）
ROOT=$DEV_ROOT
DEST=$DEV_BACKUP_DEST
KEEP=3
EOF
# ① 配置文件生效：先摘掉环境变量，否则环境变量优先，测的就不是配置文件了
out="$(env -u DEV_ROOT -u DEV_BACKUP_DEST "$BIN" --config "$CONF_A" --status --json 2>/dev/null)"
eq "① 配置文件里的 DEST 生效" "$(jstr "$out" dest)" "$DEV_BACKUP_DEST"
eq "① 配置文件里的 ROOT 生效" "$(jstr "$out" root)" "$DEV_ROOT"
# ② 环境变量覆盖配置文件
out="$(DEV_ROOT="$W/env-root" DEV_BACKUP_DEST="$W/cloud/env-dest" "$BIN" --config "$CONF_A" --status --json 2>/dev/null)"
eq "② 环境变量 DEV_BACKUP_DEST 覆盖配置文件" "$(jstr "$out" dest)" "$W/cloud/env-dest"
eq "② 环境变量 DEV_ROOT 覆盖配置文件" "$(jstr "$out" root)" "$W/env-root"
# ③ 命令行覆盖环境变量
out="$(DEV_ROOT="$W/env-root" DEV_BACKUP_DEST="$W/cloud/env-dest" \
  "$BIN" --config "$CONF_A" --root "$W/cli-root" --dest "$W/cloud/cli-dest" --status --json 2>/dev/null)"
eq "③ --dest 覆盖环境变量" "$(jstr "$out" dest)" "$W/cloud/cli-dest"
eq "③ --root 覆盖环境变量" "$(jstr "$out" root)" "$W/cli-root"
# ④ --config 指向不存在的文件 → 用法/配置错误
"$BIN" --config "$W/conf/no-such.conf" --status >/dev/null 2>&1
eq "④ --config 指向不存在的文件 → 退出 2" "$?" "2"

hdr "17 B --init（写模板 / 不覆盖 / --dry-run 不落盘 / 模板可用）"
CFG_INIT="$W/conf/init.conf"
"$BIN" --init --config "$CFG_INIT" >"$W/init.out" 2>"$W/init.err"; rc=$?
eq "① --init --config <新路径> 退出码" "$rc" "0"
[ -f "$CFG_INIT" ] && ok "生成了配置文件模板" || no "没生成配置文件模板"
grep -q '^ROOT=' "$CFG_INIT" && ok "模板含未注释的 ROOT=" || no "模板缺 ROOT="
grep -q '^DEST=' "$CFG_INIT" && ok "模板含未注释的 DEST=" || no "模板缺 DEST="
# 回归：提示语里的命令必须原样打印。写成 "…跑 \`$PROG --status\`" 会被 bash 当成命令替换：
# 轻则提示里少了命令名、stderr 多一行 command not found，重则**真的执行一次 --status**。
[ -s "$W/init.err" ] && no "--init 往 stderr 写了东西：$(head -1 "$W/init.err")" || ok "--init 的 stderr 干净"
contains "$(cat "$W/init.out")" '--status' \
  && ok "提示里带可复制的下一步命令" || no "提示里没有可复制的下一步命令"
cp "$CFG_INIT" "$W/init.snapshot"
"$BIN" --init --config "$CFG_INIT" >/dev/null 2>&1; rc=$?
eq "② 第二次 --init（无 --force）退出码" "$rc" "2"
cmp -s "$CFG_INIT" "$W/init.snapshot" && ok "② 被拒绝时文件字节没变" || no "② 被拒绝却改了文件"
"$BIN" --init --config "$CFG_INIT" --force >/dev/null 2>&1
eq "② --force 才允许覆盖" "$?" "0"
# 环境变量指路也要能用（DEV_BACKUP_CONFIG 与 --config 等价）
DEV_BACKUP_CONFIG="$W/conf/init-env.conf" "$BIN" --init >/dev/null 2>&1
eq "①b DEV_BACKUP_CONFIG 指到新路径也能写" "$?" "0"
"$BIN" --init --config "$W/conf/init-dry.conf" --dry-run >/dev/null 2>&1
eq "③ --init --dry-run 退出码" "$?" "0"
[ -f "$W/conf/init-dry.conf" ] && no "③ --dry-run 竟然创建了文件" || ok "③ --dry-run 没创建文件"
# ④ 生成的模板能被自己的 CLI 读：改掉 ROOT/DEST 后 --status 可跑
sed -e "s|^ROOT=.*|ROOT=$DEV_ROOT|" -e "s|^DEST=.*|DEST=$DEV_BACKUP_DEST|" "$CFG_INIT" >"$W/conf/init.used"
"$BIN" --status --config "$W/conf/init.used" >/dev/null 2>&1
eq "④ 用生成的模板（改过 ROOT/DEST）跑 --status" "$?" "0"

hdr "18 C 只读承诺（--status / --version 不建目录、不写文件）"
RO="$W/readonly/nested/logs"
DEV_BACKUP_LOGDIR="$RO" "$BIN" --status >/dev/null 2>&1; rc=$?
eq "--status 退出码（LOGDIR 不存在）" "$rc" "0"
[ -e "$W/readonly" ] && no "--status 创建了并不存在的 LOGDIR" || ok "--status 没创建任何目录"
DEV_BACKUP_LOGDIR="$RO" "$BIN" --version >/dev/null 2>&1; rc=$?
eq "--version 退出码" "$rc" "0"
[ -e "$W/readonly" ] && no "--version 创建了并不存在的 LOGDIR" || ok "--version 没创建任何目录"
log_lines="$(wc -l <"$DEV_BACKUP_LOGDIR/backup.log" 2>/dev/null | tr -d ' ')"
DEV_BACKUP_LOGDIR="$RO" "$BIN" --status >/dev/null 2>&1
DEV_BACKUP_LOGDIR="$RO" "$BIN" --version >/dev/null 2>&1
eq "只读模式不往日志里追加" "$(wc -l <"$DEV_BACKUP_LOGDIR/backup.log" 2>/dev/null | tr -d ' ')" "${log_lines:-0}"

hdr "19 D 未配置状态（没设 DEST）"
: >"$W/conf/empty.conf"   # 空配置文件：只剩内置默认
out="$(env -u DEV_BACKUP_DEST "$BIN" --config "$W/conf/empty.conf" --status --json 2>/dev/null)"; rc=$?
eq "--status --json 退出码（未配置）" "$rc" "2"
contains "$out" '"verdict": "bad"' && ok "verdict=bad" || no "verdict 不是 bad"
contains "$out" 'unconfigured' && ok "reasons 里有 unconfigured" || no "reasons 里没有 unconfigured"
if have python3; then
  printf '%s' "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin);assert d["schema"]=="dev-backup.status/1";assert d["verdict"]=="bad";assert any(r["code"]=="unconfigured" for r in d["reasons"])' 2>/dev/null \
    && ok "未配置时的 JSON 合法且自洽" || no "未配置时的 JSON 不合法"
fi
env -u DEV_BACKUP_DEST "$BIN" --config "$W/conf/empty.conf" --status >/dev/null 2>&1
eq "人读 --status 同样是用法/配置错误（2）" "$?" "2"

hdr "20 E 归属标记 .dev-backup-owner（别的工作区的产物：不列、不删、不写）"
FOREIGN_ID="ffffffffffff"
for rel in repos/other snapshots/other configs/other; do
  mkdir -p "$DEV_BACKUP_DEST/$rel"
  printf '%s\n' "$FOREIGN_ID" >"$DEV_BACKUP_DEST/$rel/.dev-backup-owner"
  printf 'x\n' >"$DEV_BACKUP_DEST/$rel/whatever.bin"
done
all_owned=1
for rel in repos/demo snapshots/scratch; do
  [ -f "$DEV_BACKUP_DEST/$rel/.dev-backup-owner" ] || all_owned=0
done
eq "备份时给自己的目标目录写了归属标记" "$all_owned" "1"
js="$("$BIN" --status --json 2>/dev/null)"; rc=$?
eq "--status --json 退出码（多出 foreign 目录不影响本工作区判定）" "$rc" "0"
orph_line="$(jline "$js" orphans)"
contains "$orph_line" '[]' && ok "① foreign 目录不进 orphans[]（它们不是残留）" \
  || no "① foreign 目录被当成残留：${orph_line}"
contains "$orph_line" 'other' && no "① orphans[] 里出现了 other" || ok "① orphans[] 里没有 other"
out="$("$BIN" --status 2>&1)"
contains "$out" '属于别的工作区' && ok "② 人读输出里出现「属于别的工作区」" || no "② 人读输出没提别的工作区"
"$BIN" --prune-orphans >/dev/null 2>&1; eq "--prune-orphans（dry-run）退出码" "$?" "0"
kept=1; for rel in repos/other snapshots/other configs/other; do [ -d "$DEV_BACKUP_DEST/$rel" ] || kept=0; done
eq "③ dry-run 不删 foreign 目录" "$kept" "1"
"$BIN" --prune-orphans --apply >/dev/null 2>&1; eq "③ --prune-orphans --apply 退出码" "$?" "0"
kept=1; for rel in repos/other snapshots/other configs/other; do [ -d "$DEV_BACKUP_DEST/$rel" ] || kept=0; done
eq "③ --apply 之后 foreign 目录仍在" "$kept" "1"
# ④ 抹掉标记 → 变成 unowned → 才会被列出并清掉
for rel in repos/other snapshots/other configs/other; do rm -f "$DEV_BACKUP_DEST/$rel/.dev-backup-owner"; done
orph_line="$(jline "$("$BIN" --status --json 2>/dev/null)" orphans)"
missing=""
for rel in repos/other snapshots/other configs/other; do
  contains "$orph_line" "$rel" || missing="${missing} ${rel}"
done
[ -z "$missing" ] && ok "④ unowned 目录被列为残留（可清）" || no "④ unowned 目录没被列为残留：${missing}"
"$BIN" --prune-orphans --apply >/dev/null 2>&1; eq "④ 清理 unowned 残留退出码" "$?" "0"
gone=1; for rel in repos/other snapshots/other configs/other; do [ -d "$DEV_BACKUP_DEST/$rel" ] && gone=0; done
eq "④ unowned 目录被清掉" "$gone" "1"
# ⑤ 自己的目标目录被写成别的工作区 ID：本轮拒绝写入 + 整轮退出 1
own="$(cat "$DEV_BACKUP_DEST/repos/demo/.dev-backup-owner" 2>/dev/null)"
[ -n "$own" ] || own="unknown-own-id"
printf '%s\n' "$FOREIGN_ID" >"$DEV_BACKUP_DEST/repos/demo/.dev-backup-owner"
# 先造一个新提交：若不拒绝，这一轮本该为它打出新 bundle —— 于是「拒绝写入」是可证的
printf 'foreign\n' >>"$R/f.txt"
git -C "$R" add -A
git -C "$R" commit -qm "chore: foreign guard"
newhead="$(git -C "$R" rev-parse HEAD)"
"$BIN" --trigger=selftest >/dev/null 2>&1; eq "⑤ 目标目录属于别的工作区时整轮退出 1" "$?" "1"
if ls "$DEV_BACKUP_DEST/repos/demo"/*-"${newhead:0:12}".bundle >/dev/null 2>&1; then
  no "⑤ 明明拒绝了写入，却还是写出了新产物（${newhead:0:12}）"
else
  ok "⑤ 被拒绝时没往那个目标写入任何新产物"
fi
[ -f "$DEV_BACKUP_LOGDIR/last-failure" ] && ok "⑤ 写了 last-failure" || no "⑤ 没写 last-failure"
grep -q '属于别的工作区' "$DEV_BACKUP_LOGDIR/backup.log" 2>/dev/null \
  && ok "⑤ 日志里有拒绝写入的原因" || no "⑤ 日志里没有拒绝写入的原因"
printf '%s\n' "$own" >"$DEV_BACKUP_DEST/repos/demo/.dev-backup-owner"
run; eq "⑤ 恢复自己的归属标记后恢复退出 0" "$?" "0"
ls "$DEV_BACKUP_DEST/repos/demo"/*-"${newhead:0:12}".bundle >/dev/null 2>&1 \
  && ok "⑤ 恢复归属后新提交被正常备份" || no "⑤ 恢复归属后新提交仍没被备份"
[ -f "$DEV_BACKUP_LOGDIR/last-failure" ] && no "⑤ 失败信号没被成功的一轮清掉" || ok "⑤ 成功的一轮清掉了 last-failure"

hdr "21 F schedule（只跑 --dry-run，绝不真装）"
# 只比较目录清单的指纹：本机真实装过的 plist 不该被这次自测碰到
la_hash() { ls -1 "$HOME/Library/LaunchAgents" 2>/dev/null | sha_stdin; }
LA_BEFORE="$(la_hash)"
LABEL="com.dev-backup.selftest.$$"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
[ -e "$PLIST" ] && no "测试开始前就存在同名 plist：${PLIST}" || ok "测前无同名 plist（不会覆盖真实任务）"
# F1 launchd：plist 内容必须显式带 --daily / --trigger=launchd，且指向 --program
out="$("$BIN" schedule install --dry-run --kind launchd --label "$LABEL" --at 07:30 --program "$W/fake-prog" 2>&1)"; rc=$?
eq "① schedule install --dry-run --kind launchd 退出码" "$rc" "0"
contains "$out" '<string>--daily</string>' && ok "① plist 显式带 --daily" || no "① plist 缺 --daily"
contains "$out" '--trigger=launchd' && ok "① plist 带 --trigger=launchd" || no "① plist 缺 --trigger=launchd"
contains "$out" "<string>$LABEL</string>" && ok "① plist 用了 --label" || no "① plist 没用 --label"
contains "$out" "$W/fake-prog" && ok "① plist 用了 --program" || no "① plist 没用 --program"
# F2 cron：受管区块必须有哨兵行，安装才能整块替换
if have crontab; then
  out="$("$BIN" schedule install --dry-run --kind cron --at 07:30 2>&1)"; rc=$?
  eq "② schedule install --dry-run --kind cron 退出码" "$rc" "0"
  contains "$out" '>>> dev-backup >>>' && ok "② cron 区块有起始哨兵行" || no "② cron 区块缺起始哨兵"
  contains "$out" '<<< dev-backup <<<' && ok "② cron 区块有结束哨兵行" || no "② cron 区块缺结束哨兵"
  contains "$out" '--daily --trigger=cron' && ok "② cron 行带 --daily --trigger=cron" || no "② cron 行参数不对"
else
  skip "cron 区块检查（本机没有 crontab 命令）"
fi
# F3 平台默认：macOS 默认 launchd，其他默认 cron
out="$("$BIN" schedule install --dry-run --label "$LABEL" --at 07:30 2>&1)"
if [ "$(uname -s)" = "Darwin" ]; then
  contains "$out" '<plist version="1.0">' && ok "③ macOS 默认走 launchd（打印 plist）" || no "③ macOS 默认没走 launchd"
elif have crontab; then
  contains "$out" '>>> dev-backup >>>' && ok "③ 非 macOS 默认走 cron（打印受管区块）" || no "③ 非 macOS 默认没走 cron"
else
  skip "非 macOS 默认走 cron 的输出检查（本机没有 crontab 命令）"
fi
# F4 非法时间：必须按「用法错误」退出 2，且不许写任何东西
cron_before="$(crontab -l 2>/dev/null || true)"
"$BIN" schedule install --dry-run --label "$LABEL" --at 25:00 >/dev/null 2>&1; rc=$?
eq "④ --at 25:00（非法时间）退出码" "$rc" "2"
[ -e "$PLIST" ] && no "④ 非法时间的 dry-run 写了 plist" || ok "④ 非法时间没写 plist"
eq "④ 非法时间没动 crontab" "$(crontab -l 2>/dev/null || true)" "$cron_before"
"$BIN" schedule install --dry-run --label "$LABEL" --at 7:5x >/dev/null 2>&1
eq "④ --at 7:5x（非数字）退出码" "$?" "2"
# F5 schedule status / uninstall 在任何情况下都不许崩（uninstall 只跑 --dry-run）
"$BIN" schedule status >/dev/null 2>&1; eq "⑤ schedule status 退出码" "$?" "0"
"$BIN" schedule status --kind launchd >/dev/null 2>&1; eq "⑤ schedule status --kind launchd 退出码" "$?" "0"
"$BIN" schedule status --kind cron >/dev/null 2>&1; eq "⑤ schedule status --kind cron 退出码" "$?" "0"
"$BIN" schedule uninstall --dry-run --kind launchd --label "$LABEL" >/dev/null 2>&1
eq "⑤ schedule uninstall --dry-run --kind launchd 退出码" "$?" "0"
if have crontab; then
  "$BIN" schedule uninstall --dry-run --kind cron >/dev/null 2>&1
  eq "⑤ schedule uninstall --dry-run --kind cron 退出码" "$?" "0"
else
  skip "schedule uninstall（cron）dry-run（本机没有 crontab 命令）"
fi
"$BIN" schedule bogus >/dev/null 2>&1; eq "⑤ 未知动作退出码" "$?" "2"
"$BIN" schedule install --kind bogus --dry-run >/dev/null 2>&1; eq "⑤ 未知 --kind 退出码" "$?" "2"
LA_AFTER="$(la_hash)"
eq "⑥ 全程 --dry-run 没碰 ~/Library/LaunchAgents（目录清单指纹）" "$LA_AFTER" "$LA_BEFORE"

hdr "22 G 版本一致性（--version == package.json）"
# 取第一个以数字开头的词：版本行是「dev-backup 1.0.0（契约 dev-backup.status/1）」，
# 全角括号与 awk 的字段切分不兼容，不能用 awk '{print $2}'
v_cli="$("$BIN" --version 2>/dev/null | head -1 | sed -n 's/^[^0-9]*\([0-9][0-9.]*\).*$/\1/p')"
v_pkg="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO/package.json" | head -1)"
[ -n "$v_cli" ] && ok "--version 打印了版本号（${v_cli}）" || no "--version 没打印版本号"
eq "CLI 版本 == package.json 的 version" "$v_cli" "$v_pkg"
case "$v_cli" in
  [0-9]*.[0-9]*.[0-9]*) ok "版本号形如 x.y.z" ;;
  *) no "版本号不是 x.y.z：${v_cli}" ;;
esac

hdr "23 H --prune-orphans 删除失败必须退出 1"
if [ "$(id -u)" = "0" ]; then
  skip "--prune-orphans 删除失败用例（以 root 运行，拿不到 EACCES）"
else
  mkdir -p "$DEV_BACKUP_DEST/repos/ghost-ro"
  printf 'x' >"$DEV_BACKUP_DEST/repos/ghost-ro/x.bundle"
  chmod 500 "$DEV_BACKUP_DEST/repos/ghost-ro"
  "$BIN" --prune-orphans --apply >/dev/null 2>&1; rc=$?
  eq "--apply 遇到删不掉的残留时退出码" "$rc" "1"
  [ -d "$DEV_BACKUP_DEST/repos/ghost-ro" ] && ok "删不掉的残留仍在（没有假装成功）" \
    || no "报了 1 但残留并不在（退出码解释不通）"
  chmod 700 "$DEV_BACKUP_DEST/repos/ghost-ro" 2>/dev/null
  rm -rf "$DEV_BACKUP_DEST/repos/ghost-ro"
  "$BIN" --prune-orphans --apply >/dev/null 2>&1; eq "清掉只读残留后恢复退出 0" "$?" "0"
fi

hdr "24 平台相关（mdls 上传探测 / 通知 / FDA 探针）"
UNAME_S="$(uname -s)"
# 24a mdls：只有 macOS 有；其他平台引擎必须明确回 unknown-nomdls，而不是假装「已上传」
if [ "$UNAME_S" = "Darwin" ] && have mdls; then
  ups="$("$BIN" --status --json 2>/dev/null | grep -o '"upload": "[^"]*"' | sed 's/.*: "//; s/"$//' | sort -u | tr '\n' ' ')"
  case "$ups" in
    *unknown-nomdls*) no "macOS 上不该出现 unknown-nomdls（mdls 分支没生效）：${ups}" ;;
    *) ok "mdls 上传探测生效（token：${ups}）" ;;
  esac
else
  skip "mdls 上传探测（macOS 专有）"
fi
# 24b 通知：用桩顶替平台工具（不弹真窗口），验证失败会通知、NO_NOTIFY=1 不会。
# 两个名字都放桩：notify() 先看 osascript 再看 notify-send，桩齐了就不受平台差异影响
if [ "$UNAME_S" = "Darwin" ]; then NOTIFY_TOOL="osascript"; else NOTIFY_TOOL="notify-send"; fi
STUBDIR="$W/stubbin"; mkdir -p "$STUBDIR"
for t in osascript notify-send; do
  cat >"$STUBDIR/$t" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${NOTIFY_LOG:-/dev/null}"
exit 0
STUBEOF
  chmod +x "$STUBDIR/$t"
done
: >"$W/notify.log"
PATH="$STUBDIR:$PATH" NOTIFY_LOG="$W/notify.log" DEV_BACKUP_NO_NOTIFY=0 \
  DEV_BACKUP_DEST="$W/no-such-parent/backup" "$BIN" --trigger=selftest >/dev/null 2>&1; rc=$?
eq "失败时退出码仍是 1（通知不改变语义）" "$rc" "1"
[ -s "$W/notify.log" ] && ok "失败时走了通知路径（${NOTIFY_TOOL}）" || no "失败时没走通知路径"
contains "$(cat "$W/notify.log")" '失败' && ok "通知内容里有失败原因" || no "通知内容里没有失败原因"
: >"$W/notify.log"
PATH="$STUBDIR:$PATH" NOTIFY_LOG="$W/notify.log" DEV_BACKUP_NO_NOTIFY=1 \
  DEV_BACKUP_DEST="$W/no-such-parent/backup" "$BIN" --trigger=selftest >/dev/null 2>&1
[ -s "$W/notify.log" ] && no "NO_NOTIFY=1 时仍然发了通知" || ok "NO_NOTIFY=1 时不发通知"
rm -f "$DEV_BACKUP_LOGDIR/last-failure"
# 24c FDA 探针：macOS 隐私保护下读不到已有产物时必须说清楚，且 --verify --fix 不许删东西
if [ "$UNAME_S" != "Darwin" ]; then
  skip "FDA 探针（macOS 隐私保护专有）"
elif [ "$(id -u)" = "0" ]; then
  skip "FDA 探针（以 root 运行读得到任何文件）"
else
  FDA_DEST="$W/fda-dest"
  mkdir -p "$FDA_DEST/manifests"
  printf 'x\n' >"$FDA_DEST/manifests/20260101T000000Z-daily.tsv"
  out="$(DEV_BACKUP_DEST="$FDA_DEST" "$BIN" --status 2>&1)"
  case "$out" in
    *完全磁盘访问权限*) no "产物可读时不该报 FDA 提示" ;;
    *) ok "产物可读时不误报 FDA" ;;
  esac
  chmod 000 "$FDA_DEST/manifests/20260101T000000Z-daily.tsv"
  out="$(DEV_BACKUP_DEST="$FDA_DEST" "$BIN" --status 2>&1)"; rc=$?
  eq "读不到产物时 --status 退出码" "$rc" "1"
  case "$out" in
    *完全磁盘访问权限*) ok "--status 给出可操作的 FDA 提示（而不是误报成落后/没备份）" ;;
    *) no "--status 没给出 FDA 提示，会把人误导到「备份坏了」" ;;
  esac
  out="$(DEV_BACKUP_DEST="$FDA_DEST" "$BIN" --verify --fix 2>&1)"; rc=$?
  eq "读不到产物时 --verify --fix 退出码" "$rc" "1"
  eq "读不到产物时 --fix 不许删产物" "$(ls -1 "$FDA_DEST/manifests" | wc -l | tr -d ' ')" "1"
  case "$out" in
    *未删除任何产物*) ok "明确说了「未删除任何产物」" ;;
    *) no "没说明是否删除，无法判断是否误删" ;;
  esac
  chmod 644 "$FDA_DEST/manifests/20260101T000000Z-daily.tsv"
fi

printf '\n== 自测结果：%d 项通过，%d 项失败，%d 项跳过\n' "$pass" "$fail" "$skipped"
printf '   （临时目录已清理：%s）\n' "$W"
[ "$fail" -eq 0 ] || exit 1
exit 0
