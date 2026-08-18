#!/bin/sh
set -e

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_app="$script_dir/Artifacts/LocalBuild/McBopomofo.app"
source_executable="$source_app/Contents/MacOS/McBopomofo"
destination_dir="$HOME/Library/Input Methods"
destination_app="$destination_dir/McBopomofo.app"
backup_dir="$HOME/McBopomofo Backups"
backup_app=

if [ ! -d "$source_app" ]; then
    echo "找不到建置產物：$source_app" >&2
    echo "請先在專案根目錄執行：zsh LocalBuild/build.sh" >&2
    exit 1
fi

if [ ! -x "$source_executable" ]; then
    echo "建置產物缺少可執行檔：$source_executable" >&2
    exit 1
fi

"$source_executable" --self-check
/usr/bin/codesign --verify --deep --strict --verbose=2 "$source_app"
source_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$source_app/Contents/Info.plist")
echo "準備安裝 McBopomofo build $source_version"

mkdir -p "$destination_dir"
mkdir -p "$backup_dir"

/usr/bin/killall McBopomofo 2>/dev/null || true

if [ -e "$destination_app" ]; then
    backup_app="$backup_dir/McBopomofo-backup-$(date '+%Y%m%dT%H%M%S').app"
    mv "$destination_app" "$backup_app"
fi

/usr/bin/ditto "$source_app" "$destination_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$destination_app"

if ! "$destination_app/Contents/MacOS/McBopomofo" install; then
    echo "輸入法已複製，但自動註冊失敗；登出再登入後由系統重新掃描。" >&2
fi
/usr/bin/killall TextInputMenuAgent 2>/dev/null || true

echo "McBopomofo 已複製完成"
if [ -n "$backup_app" ]; then
    echo "原有版本備份：$backup_app"
fi
echo "請完整登出 macOS 並重新登入，再切換至小麥注音。"
