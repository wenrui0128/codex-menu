#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_png="$project_dir/Resources/AppIcon.png"
icon_output="${1:-$project_dir/.build/app-icon/AppIcon.icns}"
[[ -f "$source_png" ]] || { print -u2 "Missing app icon: $source_png"; exit 1; }
mkdir -p "$(dirname "$icon_output")"
icon_output="$(cd "$(dirname "$icon_output")" && pwd)/$(basename "$icon_output")"
icon_tmp="$(mktemp -d "$(dirname "$icon_output")/.app-icon.XXXXXX")"
trap 'rm -rf "$icon_tmp"' EXIT
iconset="$icon_tmp/AppIcon.iconset"
mkdir -p "$iconset"

# Include standard and Retina representations for every macOS app-icon size.
for points in 16 32 128 256 512; do
    for scale in 1 2; do
        pixels=$((points * scale))
        suffix=''
        (( scale == 1 )) || suffix='@2x'
        target="$iconset/icon_${points}x${points}${suffix}.png"
        if (( pixels == 1024 )); then
            cp "$source_png" "$target"
        else
            sips -z "$pixels" "$pixels" "$source_png" --out "$target" >/dev/null
        fi
    done
done
iconutil -c icns "$iconset" --output "$icon_output"
print "已生成应用图标：$icon_output"
