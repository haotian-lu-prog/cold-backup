#!/usr/bin/env bash
# 静态检查：不跑备份，只查源码、契约与版本号的一致性。任何平台都能跑，秒级完成。
# 这里每一条都对应一个**真实踩过的坑**，不是形式主义。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
BIN="$ROOT/bin/cold-backup"
PKG="$ROOT/package.json"
DOC="$ROOT/docs/compatibility.md"
pass=0; fail=0
ok() { printf '   ✓ %s\n' "$*"; pass=$((pass + 1)); }
no() { printf '   ✗ %s\n' "$*"; fail=$((fail + 1)); }
hdr() { printf '\n== %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

[ -f "$BIN" ] || { printf '✗ 找不到 %s\n' "$BIN" >&2; exit 2; }

hdr "1 语法"
for f in bin/cold-backup install.sh test/lint.sh test/selftest.sh test/frozen-clock.sh; do
  [ -f "$ROOT/$f" ] || { no "缺文件：$f"; continue; }
  if out="$(bash -n "$ROOT/$f" 2>&1)"; then ok "$f 语法通过"; else no "$f 语法错误：$out"; fi
done
[ -x "$BIN" ] && ok "bin/cold-backup 可执行位已设" || no "bin/cold-backup 缺可执行位"
case "$(head -1 "$BIN")" in '#!/usr/bin/env bash') ok "shebang 是 /usr/bin/env bash" ;; *) no "shebang 不对：$(head -1 "$BIN")" ;; esac

hdr "2 bash 3.2 兼容（macOS 系统 bash 就是 3.2）"
if hits="$(grep -nE 'declare[[:space:]]+-A|(^|[^A-Za-z_])mapfile|(^|[^A-Za-z_])readarray|local[[:space:]]+-n|\$\{[A-Za-z_][A-Za-z0-9_]*\^\^|\$\{[A-Za-z_][A-Za-z0-9_]*,,|&>>|;;&' "$BIN")"; then
  no "用了 bash 4+ 专有语法："; printf '%s\n' "$hits" | head -5
else
  ok "没有 bash 4 专有语法（declare -A / mapfile / \${x^^} / local -n / &>>）"
fi

# 变量后面紧跟中文（全角字符）时，bash 3.2 会把那些字节吃进变量名 → set -u 下直接中止。
# 本机踩过这个坑（`out "$PROG $VERSION（契约 …）"`，还有本文件自己）。
# 行内 `#` 之后的部分当注释跳过：判据是「匹配位置在 # 之后」。
multibyte_lint() { # $1=文件
  have perl || return 0
  perl -ne 'next if /^\s*#/;
            while (/\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/g) {
              my $st = $-[0]; my $h = index($_,"#");
              next if $h >= 0 && $h < $st;
              print "$ARGV:$.: $_"; last;
            }' "$1"
}

if have perl; then
  mb_hits=""
  for f in bin/cold-backup install.sh test/lint.sh test/selftest.sh test/frozen-clock.sh; do
    [ -f "$ROOT/$f" ] || continue
    h="$(multibyte_lint "$ROOT/$f")"
    [ -n "$h" ] && mb_hits="${mb_hits}${h}
"
  done
  if [ -n "$mb_hits" ]; then
    no "变量后紧跟全角字符（bash 3.2 会把全角吃进变量名，必须写 \${var}）："
    printf '%s' "$mb_hits" | head -5
  else
    ok "没有「变量后紧跟全角字符」的写法（5 个脚本都查了）"
  fi
else
  printf '   - 跳过：没有 perl，无法查「变量后紧跟全角字符」\n'
fi

hdr "3 版本与契约一致性"
ver_bin="$(sed -n 's/^VERSION="\([^"]*\)".*/\1/p' "$BIN" | head -1)"
ver_pkg="$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$PKG" | head -1)"
[ -n "$ver_bin" ] || no "bin/cold-backup 里找不到 VERSION"
[ "$ver_bin" = "$ver_pkg" ] && ok "版本号一致（${ver_bin}）" || no "版本号不一致：bin=${ver_bin} package.json=${ver_pkg}"

schema_bin="$(sed -n 's/^SCHEMA="\([^"]*\)".*/\1/p' "$BIN" | head -1)"
[ "$schema_bin" = "cold-backup.status/1" ] && ok "schema 常量是 $schema_bin" || no "schema 常量异常：$schema_bin"
if [ -f "$DOC" ]; then
  grep -qF "$schema_bin" "$DOC" && ok "docs/compatibility.md 写明了该契约" || no "docs/compatibility.md 里找不到 $schema_bin"
else
  no "缺少 docs/compatibility.md（下游消费者要照它对接）"
fi

hdr "4 公开包里不许出现本机私有路径"
for pat in 'haotian' 'com\.haotianlu' '/Users/lu' 'OneDrive-Personal' '~/.claude' '~/.codex' '~/.dsh' '_shared/bin'; do
  if hits="$(grep -nE "$pat" "$BIN")"; then
    no "bin/cold-backup 里出现私有路径/标识（${pat}）："; printf '%s\n' "$hits" | head -3
  fi
done
[ "$fail" -eq 0 ] && ok "没有个人路径、个人 label、个人 home 约定" || true

hdr "5 默认值必须是「不认识陌生人的 home」"
grep -q 'CONFIGS_SPEC="\$(cfg COLD_BACKUP_CONFIGS CONFIGS "" "off")"' "$BIN" \
  && ok "配置白名单默认 off" || no "配置白名单默认值不是 off（公开 CLI 不许去 tar 陌生人的 home）"
grep -q 'DEST="\$(cfg COLD_BACKUP_DEST DEST "\$OPT_DEST" "")"' "$BIN" \
  && ok "备份目标默认留空（必须显式配置）" || no "备份目标默认值不是空"

hdr "6 CLI 冒烟（不写任何文件）"
tmpconf="$ROOT/.lint-no-such-config"
out="$(COLD_BACKUP_CONFIG="$tmpconf" "$BIN" --version 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--version 退出码 0" || no "--version 退出码 $rc"
printf '%s' "$out" | grep -qF "$ver_bin" && ok "--version 打印的版本与源码一致" || no "--version 没打印版本号：$out"
[ -e "$tmpconf" ] && { no "--version 竟然创建了配置文件"; rm -f "$tmpconf"; } || ok "--version 没创建任何文件"

out="$(COLD_BACKUP_CONFIG="$tmpconf" "$BIN" --help 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--help 退出码 0" || no "--help 退出码 $rc"
for kw in --status --verify --daily --restore-drill --init schedule; do
  printf '%s' "$out" | grep -qF -- "$kw" && ok "--help 提到 $kw" || no "--help 没提到 $kw"
done

# `--init` 的输出里曾经用过反引号包裹命令名，结果被 shell 当命令替换执行
# （`bin/cold-backup: line N: cold-backup: command not found`）。用 stderr 干净与否兜住这类问题。
initconf="$ROOT/.lint-init-probe.conf"
init_err="$(COLD_BACKUP_CONFIG="$tmpconf" "$BIN" --config "$initconf" --init --dry-run 2>&1 >/dev/null)"
if [ -n "$init_err" ]; then
  no "--init --dry-run 往 stderr 写了东西（反引号被当命令替换了？）：${init_err}"
else
  ok "--init --dry-run stderr 干净"
fi
if [ -e "$initconf" ]; then no "--init --dry-run 竟然写了文件"; rm -f "$initconf"; else ok "--init --dry-run 没写文件"; fi
# 真机上踩到过：`--init --dry-run` 会在**真实**日志目录里建一个 `tmp/` —— 自测于是污染了
# 用户的 ~/Library/Logs，也让「dry-run 无副作用」这句话不成立。用临时 LOGDIR 钉住它。
probe_logdir="$ROOT/.lint-init-logdir-probe"
rm -rf "$probe_logdir"
COLD_BACKUP_LOGDIR="$probe_logdir" COLD_BACKUP_CONFIG="$tmpconf" \
  "$BIN" --config "$initconf" --init --dry-run >/dev/null 2>&1
if [ -e "$probe_logdir" ]; then
  no "--init --dry-run 建了日志目录（dry-run 不该有任何副作用）"; rm -rf "$probe_logdir"
else
  ok "--init --dry-run 没建日志目录"
fi

hdr "7 未配置时的 JSON 必须合法（下游解析它，不能是半截）"
json="$(COLD_BACKUP_CONFIG="$tmpconf" "$BIN" --status --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && ok "未配置时 --status --json 退出码 2" || no "未配置时退出码应为 2，实得 $rc"
if have python3; then
  if printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="cold-backup.status/1"; assert d["verdict"] in ("ok","bad"); assert any(r["code"]=="unconfigured" for r in d["reasons"])' 2>/dev/null; then
    ok "JSON 可被 python3 解析，且 schema/verdict/reasons 都自洽"
  else
    no "未配置时的 JSON 解析失败或字段不对"
  fi
else
  printf '   - 跳过：没有 python3\n'
fi

hdr "8 README 与文档"
for f in README.md README.en.md docs/compatibility.md docs/scheduling.md docs/restore.md docs/decisions.md AGENTS.md HANDOFF.md; do
  [ -s "$ROOT/$f" ] && ok "有 $f" || no "缺 $f"
done
grep -q 'cold-backup.status/1' "$ROOT/README.md" && ok "README 指向契约文档" || no "README 没提契约"

printf '\n== 静态检查结果：%s 项通过，%s 项失败\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
