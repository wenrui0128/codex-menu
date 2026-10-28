#!/bin/bash
# Install a verified release without sudo, launching, or changing Codex data.
set -euo pipefail

repository='wenrui0128/codex-menu'
asset='CodexMenu-macos-universal.zip'
tag=''
install_dir="$HOME/Applications"
download_dir=''
work_dir=''
stage_dir=''
destination=''

fail() { printf 'Codex Menu: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'USAGE'
Usage: bash install.sh [--version v0.5.2] [--dir DIR] [--download-only DIR]

  --version TAG        Download this release (default: latest stable release).
  --dir DIR            Install here (default: $HOME/Applications; no sudo).
  --download-only DIR  Save the ZIP and checksum file only; do not install.
  --help               Show this help.

The app is never started automatically. Quit an existing Codex Menu before
installing an update. Conversation data and settings are kept in place.
USAGE
}
cleanup() {
    # Restore the previous app if installation was interrupted between renames.
    if [[ -n "$stage_dir" && -d "$stage_dir/previous.app" && ! -e "$destination" ]]; then
        mv "$stage_dir/previous.app" "$destination" || true
    fi
    [[ -z "$stage_dir" ]] || rm -rf -- "$stage_dir"
    [[ -z "$work_dir" ]] || rm -rf -- "$work_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version|--dir|--download-only)
            [[ $# -ge 2 && -n "$2" ]] || fail "Missing value for $1"
            case "$1" in
                --version) tag="$2" ;;
                --dir) install_dir="$2" ;;
                --download-only) download_dir="$2" ;;
            esac
            shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown argument: $1 (see --help)" ;;
    esac
done
[[ "$(uname -s)" == Darwin ]] || fail 'macOS 13 or later is required.'
case "$(uname -m)" in arm64|x86_64) ;; *) fail 'Unsupported CPU architecture.' ;; esac
os_version="$(sw_vers -productVersion)"
[[ "${os_version%%.*}" -ge 13 ]] || fail 'macOS 13 or later is required.'
for utility in curl shasum ditto plutil codesign unzip awk; do
    command -v "$utility" >/dev/null || fail "Required utility is missing: $utility"
done
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-menu-download.XXXXXX")"
fetch() {
    curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
        --tlsv1.2 --retry 3 --connect-timeout 15 --max-time 180 --output "$2" "$1"
}
if [[ -z "$tag" ]]; then
    fetch "https://api.github.com/repos/$repository/releases/latest" "$work_dir/release.json"
    tag="$(plutil -extract tag_name raw -o - "$work_dir/release.json")"
fi
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid stable release tag: $tag"
base_url="https://github.com/$repository/releases/download/$tag"
printf 'Downloading Codex Menu %s (Apple Silicon + Intel)…\n' "$tag"
fetch "$base_url/$asset" "$work_dir/$asset"
fetch "$base_url/SHA256SUMS" "$work_dir/SHA256SUMS"
expected="$(awk -v asset="$asset" '$2 == asset { print $1 }' "$work_dir/SHA256SUMS")"
[[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || fail 'Missing or invalid release checksum.'
actual="$(shasum -a 256 "$work_dir/$asset" | awk '{ print $1 }')"
[[ "$actual" == "$expected" ]] || fail 'SHA-256 mismatch; nothing was installed.'
printf 'SHA-256 verified.\n'

if [[ -n "$download_dir" ]]; then
    mkdir -p -- "$download_dir"
    cp "$work_dir/$asset" "$download_dir/$asset"
    cp "$work_dir/SHA256SUMS" "$download_dir/SHA256SUMS"
    printf 'Downloaded only (not installed): %s/%s\n' "$download_dir" "$asset"
    exit 0
fi

# Never replace an app while it is running, or terminate it on the user's behalf.
if pgrep -x CodexMenu >/dev/null; then
    fail 'Quit Codex Menu from its menu, then run the installer again. Nothing was installed.'
fi
if ! unzip -Z -1 "$work_dir/$asset" | awk '
    /^\// || /(^|\/)\.\.(\/|$)/ { exit 1 }
    index($0, "Codex Menu.app/") != 1 && $0 != "Codex Menu.app" { exit 1 }
'; then
    fail 'Unexpected archive paths; nothing was installed.'
fi
ditto -x -k "$work_dir/$asset" "$work_dir/extracted"
extracted_app="$work_dir/extracted/Codex Menu.app"
[[ -d "$extracted_app" && ! -L "$extracted_app" ]] || fail 'The archive does not contain the expected app.'
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$extracted_app/Contents/Info.plist")" == 'local.tao.codex-menu' ]] || fail 'Unexpected app identity.'
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$extracted_app/Contents/Info.plist")" == "${tag#v}" ]] || fail 'App version does not match the release tag.'
codesign --verify --deep --strict "$extracted_app" || fail 'App signature verification failed.'
mkdir -p -- "$install_dir"
install_dir="$(cd "$install_dir" && pwd)"
[[ -w "$install_dir" ]] || fail 'Install directory is not writable; choose --dir instead of sudo.'
destination="$install_dir/Codex Menu.app"
if [[ -e "$destination" || -L "$destination" ]]; then
    [[ -d "$destination" && ! -L "$destination" ]] || fail 'The destination is not a regular app directory.'
    [[ "$(plutil -extract CFBundleIdentifier raw -o - "$destination/Contents/Info.plist")" == 'local.tao.codex-menu' ]] || fail 'A different app already exists at the destination.'
fi
stage_dir="$(mktemp -d "$install_dir/.CodexMenu-install.XXXXXX")"
ditto --norsrc --noextattr "$extracted_app" "$stage_dir/new.app"
codesign --verify --deep --strict "$stage_dir/new.app"
if [[ -e "$destination" ]]; then mv "$destination" "$stage_dir/previous.app"; fi
mv "$stage_dir/new.app" "$destination"
printf 'Installed %s to %s\n' "$tag" "$destination"
printf 'Start when ready:\n  open %q\n' "$destination"
