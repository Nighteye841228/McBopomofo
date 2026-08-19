#!/bin/sh
set -e

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
destination_dir="$HOME/Library/Input Methods"
destination_app="$destination_dir/McBopomofo.app"
backup_dir="$HOME/McBopomofo Backups"
backup_app=$(find "$backup_dir" -maxdepth 1 -type d -name 'McBopomofo-backup-*.app' -print 2>/dev/null | sort | tail -n 1)

if [ -z "$backup_app" ] || [ ! -d "$backup_app" ]; then
    echo "找不到可回復的上一版備份：$backup_dir" >&2
    exit 1
fi

/usr/bin/codesign --verify --deep --strict "$backup_app"
mkdir -p "$destination_dir"
/usr/bin/killall McBopomofo 2>/dev/null || true

current_backup="$backup_dir/McBopomofo-rollback-current-$(date '+%Y%m%dT%H%M%S').app"
if [ -e "$destination_app" ]; then
    mv "$destination_app" "$current_backup"
fi
/usr/bin/ditto "$backup_app" "$destination_app"
/usr/bin/codesign --verify --deep --strict "$destination_app"

if ! "$destination_app/Contents/MacOS/McBopomofo" install; then
    echo "上一版已複製，但自動註冊失敗；請登出再登入。" >&2
fi
/usr/bin/killall TextInputMenuAgent 2>/dev/null || true

echo "已回復上一版：$backup_app"
echo "目前版本備份：$current_backup"
echo "請完整登出 macOS 並重新登入，再切換至小麥注音。"
