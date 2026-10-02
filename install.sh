#!/usr/bin/env bash
# cold-backup 安装脚本（不想用 npm 时用这个）
#
#   ./install.sh              装到 ~/.local/bin
#   PREFIX=/usr/local ./install.sh   装到别处（可能需要 sudo）
#   ./install.sh --uninstall  删掉装进去的那份
#
# 只做三件事：把 bin/cold-backup 复制过去、给可执行位、告诉你怎么开始。
# 不碰 crontab / launchd（那是 `cold-backup schedule install` 的事）。
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SRC="$SRC_DIR/bin/cold-backup"
PREFIX="${PREFIX:-$HOME/.local}"
DEST_DIR="$PREFIX/bin"
DEST="$DEST_DIR/cold-backup"

[ -f "$SRC" ] || { printf '✗ 找不到 %s\n' "$SRC" >&2; exit 2; }

if [ "${1:-}" = "--uninstall" ]; then
  if [ -f "$DEST" ]; then
    rm -f "$DEST" && printf '✓ 已删除 %s\n' "$DEST"
  else
    printf '· 没找到 %s（可能装在别的前缀里）\n' "$DEST"
  fi
  exit 0
fi

mkdir -p "$DEST_DIR" || { printf '✗ 无法创建 %s\n' "$DEST_DIR" >&2; exit 1; }
cp -f "$SRC" "$DEST" || { printf '✗ 复制失败（%s 需要写权限；试试 PREFIX=/usr/local 加 sudo）\n' "$DEST_DIR" >&2; exit 1; }
chmod 755 "$DEST"
printf '✓ 已安装：%s\n' "$DEST"
"$DEST" --version

case ":$PATH:" in
  *":$DEST_DIR:"*) ;;
  *) printf '\n! %s 不在 PATH 里，加一行到你的 shell 配置：\n    export PATH="%s:$PATH"\n' "$DEST_DIR" "$DEST_DIR" ;;
esac

printf '\n下一步：\n'
printf '  1) %s --init        写一份配置文件模板（默认 ~/.config/cold-backup/config）\n' "$DEST"
printf '  2) 改里面的 ROOT 与 DEST，然后跑 %s --status\n' "$DEST"
printf '  3) 装每日任务：%s schedule install\n' "$DEST"
