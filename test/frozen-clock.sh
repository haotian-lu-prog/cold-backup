#!/usr/bin/env bash
# 冻结时钟跑一遍自测：把产物名里的 UTC 时间戳钉死成同一个值，
# 强制制造「同一秒内为多个提交各备一次」的极端情况。
#
# 为什么需要它：产物名是 `<标签>-<UTC 秒>-<提交前12位>`，只有秒精度。真实机器上
# 「两个提交的产物落在同一秒」是时序巧合（ubuntu runner 够快就会撞上，macOS 不会），
# 于是自测在 CI 上按运气红绿。这个脚本把那**巧合变成常态**：
# 一旦测试里再出现「按文件名取最新」这类假设，这里就会稳定地红，而不是等 CI 抽签。
#
# 用法：bash test/frozen-clock.sh    （参数原样透传给 selftest.sh）
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
FROZEN="20260101T000000Z"
SHIM="$(mktemp -d "${TMPDIR:-/tmp}/cold-backup-frozen.XXXXXX")" || exit 2
trap 'rm -rf "$SHIM"' EXIT

# 只拦截引擎生成产物名用的那一种调用形态；其他（epoch 秒、人读时间）原样透传。
cat >"$SHIM/date" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-u" ] && [ "${2:-}" = "+%Y%m%dT%H%M%SZ" ]; then
  printf '20260101T000000Z\n'
  exit 0
fi
exec /bin/date "$@"
EOF
chmod +x "$SHIM/date"

printf '== 冻结时钟模式：所有产物共用 UTC 时间戳 %s（同一秒并列成为常态）\n' "$FROZEN"
PATH="$SHIM:$PATH" exec bash "$ROOT/test/selftest.sh" "$@"
