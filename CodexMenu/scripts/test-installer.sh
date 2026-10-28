#!/bin/bash
# Downloads only into a temporary folder. Never installs or starts an app.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
installer="$project_dir/../install.sh"
release_dir="$project_dir/release/v$(cat "$project_dir/VERSION")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-menu-installer-test.XXXXXX")"
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
cat > "$test_dir/bin/curl" <<'MOCK'
#!/bin/bash
set -euo pipefail
output=''
while [[ $# -gt 0 ]]; do
    case "$1" in --output) output="$2"; shift 2 ;; *) url="$1"; shift ;; esac
done
case "$url" in
    */releases/latest) printf '{"tag_name":"v0.5.2"}' > "$output" ;;
    */CodexMenu-macos-universal.zip)
        cp "$TEST_RELEASE_DIR/CodexMenu-macos-universal.zip" "$output"
        if [[ "${TEST_TAMPER:-0}" == 1 ]]; then printf 'tampered' >> "$output"; fi ;;
    */SHA256SUMS) cp "$TEST_RELEASE_DIR/SHA256SUMS" "$output" ;;
    *) exit 1 ;;
esac
MOCK
chmod +x "$test_dir/bin/curl"
export PATH="$test_dir/bin:$PATH" TEST_RELEASE_DIR="$release_dir"
bash -n "$installer"
bash "$installer" --dir "$test_dir/must-not-install" --download-only "$test_dir/downloaded"
cmp "$release_dir/CodexMenu-macos-universal.zip" "$test_dir/downloaded/CodexMenu-macos-universal.zip"
[[ ! -e "$test_dir/must-not-install" ]]
if TEST_TAMPER=1 bash "$installer" --download-only "$test_dir/tampered" > "$test_dir/tampered.log" 2>&1; then
    printf 'FAIL: corrupted archive was accepted\n' >&2; exit 1
fi
[[ "$(cat "$test_dir/tampered.log")" == *'SHA-256 mismatch'* ]]
[[ ! -e "$test_dir/tampered" ]]
if bash "$installer" --version '../invalid' --download-only "$test_dir/invalid" > "$test_dir/invalid.log" 2>&1; then
    printf 'FAIL: invalid tag was accepted\n' >&2; exit 1
fi
[[ "$(cat "$test_dir/invalid.log")" == *'Invalid stable release tag'* ]]
[[ ! -e "$test_dir/invalid" ]]
printf 'PASS: latest download, checksum rejection and invalid-tag rejection; nothing installed.\n'
