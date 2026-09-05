#!/bin/sh
set -eu

usage() {
    cat <<'HELP'
用法：./install.sh [--skip-build | --check | --help]

  不加參數       建置最新版、驗證、備份並安裝到目前使用者的系統目錄
  --skip-build   驗證並安裝既有建置產物
  --check        建置並驗證，不更動已安裝的輸入法
  --help         顯示說明

不需要 sudo。安裝完成後，請登出 macOS 再登入。
此為 Apple Silicon、macOS 14 以上的本機開發版；OpenCC 與字元資訊查詢使用本機替代實作。
HELP
}

verify_bundle() {
    if [ ! -x "$1/Contents/MacOS/McBopomofo" ]; then
        echo "找不到有效的建置產物：$1" >&2
        return 1
    fi
    /usr/bin/codesign --verify --deep --strict "$1"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist" >/dev/null
}

build_if_needed() {
    if [ "$2" != '--skip-build' ]; then
        echo '正在建置目前工作區的最新版小麥注音……'
        /bin/zsh "$1/LocalBuild/build.sh"
    fi
}

check_existing_build() {
    if [ "$2" = '--skip-build' ]; then
        "$1/Contents/MacOS/McBopomofo" --self-check
    fi
}

backup_existing_bundle() {
    if [ -e "$1" ]; then
        echo "備份原有版本：$2"
        mv "$1" "$2"
    fi
}

restore_backup() {
    if [ -d "$1" ]; then
        mv "$1" "$2"
        echo '已還原原有版本。' >&2
    fi
}

restore_missing_destination() {
    if [ ! -e "$1" ]; then
        restore_backup "$2" "$1"
    fi
}

cleanup_install() {
    restore_missing_destination "$2" "$3"
    rm -rf "$1"
}

activate_bundle() {
    backup_existing_bundle "$2" "$3"
    if ! mv "$1" "$2"; then
        echo '替換輸入法失敗。' >&2
        restore_backup "$3" "$2"
        return 1
    fi
}

register_bundle() {
    if ! "$1/Contents/MacOS/McBopomofo" install; then
        echo '輸入法已安裝，但自動註冊失敗；請登出再登入，讓系統重新掃描。' >&2
    fi
}

report_backup() {
    if [ -d "$1" ]; then
        echo "原有版本備份：$1"
    fi
}

install_bundle() (
    source_app=$1
    destination_dir=$2
    backup_root=$3
    mkdir -p "$destination_dir" "$backup_root"
    stage_dir=$(mktemp -d "$destination_dir/.McBopomofo-install.XXXXXX")
    destination_app="$destination_dir/McBopomofo.app"
    backup_app=
    trap 'cleanup_install "$stage_dir" "$destination_app" "$backup_app"' EXIT
    trap 'exit 1' HUP INT TERM

    # Prepare and verify the replacement before stopping the running input method.
    /usr/bin/ditto "$source_app" "$stage_dir/McBopomofo.app"
    verify_bundle "$stage_dir/McBopomofo.app"
    backup_dir=$(mktemp -d "$backup_root/$(TZ=Asia/Taipei date '+%Y%m%dT%H%M%S%z')-XXXXXX")
    backup_app="$backup_dir/McBopomofo.app"

    /usr/bin/killall McBopomofo 2>/dev/null || true
    activate_bundle "$stage_dir/McBopomofo.app" "$destination_app" "$backup_app"
    register_bundle "$destination_app"
    report_backup "$backup_app"
    echo "已安裝：$destination_app"
    echo '請完整登出 macOS 並重新登入，再切換至小麥注音。'
    echo '混合輸入及個人化學習可在小麥注音的偏好設定中啟用。'
)

run_install() {
    build_if_needed "$1" "$2"
    verify_bundle "$1/Artifacts/LocalBuild/McBopomofo.app"
    check_existing_build "$1/Artifacts/LocalBuild/McBopomofo.app" "$2"
    if [ "$2" = '--check' ]; then
        echo '建置與驗證完成，尚未安裝到系統。'
        return
    fi
    install_bundle "$1/Artifacts/LocalBuild/McBopomofo.app" \
        "$HOME/Library/Input Methods" "$HOME/McBopomofo Backups"
}

main() {
    if [ "$#" -gt 1 ]; then
        usage >&2
        return 2
    fi
    case "${1:-}" in
        --help|-h) usage ;;
        ''|--skip-build|--check)
            run_install "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)" "${1:-}"
            ;;
        *) usage >&2; return 2 ;;
    esac
}

main "$@"
