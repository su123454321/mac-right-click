#!/bin/zsh
set -euo pipefail
package_dir="${0:A:h}"
archive="$package_dir/右键小工具.app.zip"
target_app="$HOME/Applications/右键小工具.app"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp/}rightclick-install.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
/usr/bin/ditto -x -k "$archive" "$staging_dir"
/usr/bin/codesign --verify --deep --strict "$staging_dir/右键小工具.app"
mkdir -p "$HOME/Applications"
if [[ -d "$target_app" ]]; then
    backup_dir="$HOME/Library/Application Support/RightClickTools/Backups"
    mkdir -p "$backup_dir"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$target_app" "$backup_dir/右键小工具-$(date +%Y%m%d-%H%M%S).zip"
fi
/usr/bin/killall -TERM RightClickTools RightClickFinder 2>/dev/null || true
/usr/bin/ditto "$staging_dir/右键小工具.app" "$target_app"
/usr/bin/codesign --verify --deep --strict "$target_app"
/usr/bin/pluginkit -a "$target_app/Contents/PlugIns/RightClickFinder.appex" || true
/usr/bin/open "$target_app"
print "已安装右键小工具 2.1。已有文件不会被改动。"
print "首次安装时，请在应用的 Finder 扩展设置中启用本工具。"
print "若菜单仍是旧版，先关闭再开启本工具的 Finder 扩展。"
read -k 1 "?按任意键关闭安装窗口…"
