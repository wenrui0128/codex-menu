#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-module-cache"
output_dir="$project_dir/dist"
universal=false
while (( $# )); do
    case "$1" in
        --universal) universal=true; shift ;;
        --output-dir)
            (( $# >= 2 )) || { print -u2 'Missing --output-dir value'; exit 1; }
            output_dir="$2"; shift 2 ;;
        --help)
            print 'Usage: zsh scripts/build.sh [--universal] [--output-dir DIR]'
            exit 0 ;;
        *) print -u2 "Unknown argument: $1"; exit 1 ;;
    esac
done
version="$(<VERSION)"
build_number="$(<BUILD_NUMBER)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build_number" =~ ^[0-9]+$ ]] || {
    print -u2 'Invalid VERSION or BUILD_NUMBER'; exit 1
}
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

app_dir="$output_dir/Codex Menu.app"
mkdir -p "$app_dir/Contents/MacOS"
common_args=(--disable-sandbox --cache-path "$project_dir/.build/cache"
    --config-path "$project_dir/.build/config" --security-path "$project_dir/.build/security"
    -c release -debug-info-format none)
if $universal; then
    binaries=()
    for architecture in arm64 x86_64; do
        arch_args=(--triple "$architecture-apple-macosx13.0" --scratch-path "$project_dir/.build/release-$architecture")
        swift build "${common_args[@]}" "${arch_args[@]}"
        bin_dir="$(swift build "${common_args[@]}" "${arch_args[@]}" --show-bin-path)"
        binaries+=("$bin_dir/CodexMenu")
    done
    lipo -create "${binaries[@]}" -output "$app_dir/Contents/MacOS/CodexMenu"
    for architecture in arm64 x86_64; do
        lipo "$app_dir/Contents/MacOS/CodexMenu" -verify_arch "$architecture"
    done
else
    swift build "${common_args[@]}"
    bin_dir="$(swift build "${common_args[@]}" --show-bin-path)"
    cp "$bin_dir/CodexMenu" "$app_dir/Contents/MacOS/CodexMenu"
fi
chmod 755 "$app_dir/Contents/MacOS/CodexMenu"
cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Codex Menu</string>
    <key>CFBundleDisplayName</key><string>Codex Menu</string>
    <key>CFBundleIdentifier</key><string>local.tao.codex-menu</string>
    <key>CFBundleExecutable</key><string>CodexMenu</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$build_number</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
mkdir -p "$app_dir/Contents/Resources"
cp THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp ../LICENSE "$app_dir/Contents/Resources/LICENSE"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
print "已构建：$app_dir"
