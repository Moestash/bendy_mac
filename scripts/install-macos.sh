#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 '/Applications/FL Studio 2026.app' [build-directory]" >&2
    exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname -- "$script_dir")"
fl_app="${1%/}"
build_dir="${2:-$project_dir/build-macos}"
source_dir="$build_dir/BENDY"
plugin_root="$fl_app/Contents/Resources/FL/Plugins/Fruity/Generators"
destination="$plugin_root/BENDY"

if [[ ! -d "$plugin_root" ]]; then
    echo "FL Studio's native generator directory was not found in: $fl_app" >&2
    exit 1
fi
if [[ ! -f "$source_dir/BENDY_x64.dylib" || ! -f "$source_dir/Plugin.nfo" ]]; then
    echo "Build BENDY first; the plugin files were not found in: $source_dir" >&2
    exit 1
fi
if /usr/bin/pgrep -f "$fl_app/Contents/MacOS/" >/dev/null; then
    echo "Quit FL Studio before installing BENDY." >&2
    exit 1
fi
if [[ ! -w "$plugin_root" ]]; then
    echo "You need write access to: $plugin_root" >&2
    echo "Run this script with sudo if the FL Studio installation requires administrator access." >&2
    exit 1
fi

/usr/bin/codesign --verify "$source_dir/BENDY_x64.dylib"
if [[ -e "$destination" ]]; then
    backup="$(/usr/bin/mktemp -d "$plugin_root/.BENDY-backup.XXXXXX")"
    /bin/cp -Rp "$destination" "$backup/BENDY"
    echo "Previous installation backed up to: $backup/BENDY"
fi
/bin/mkdir -p "$destination"
/bin/cp "$source_dir/BENDY_x64.dylib" "$source_dir/Plugin.nfo" "$destination/"
echo "Installed BENDY to: $destination"
echo "Open FL Studio and refresh its plugin list to find BENDY."
