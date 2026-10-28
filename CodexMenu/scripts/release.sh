#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
version="$(<VERSION)"
release_dir="$project_dir/release/v$version"
mkdir -p "$release_dir"
# A separate output directory keeps the running development app untouched.
zsh scripts/build.sh --universal --output-dir "$release_dir/bundle"
app_dir="$release_dir/bundle/Codex Menu.app"
asset='CodexMenu-macos-universal.zip'
ditto -c -k --keepParent --norsrc --noextattr --noqtn "$app_dir" "$release_dir/$asset"
cp ../install.sh "$release_dir/install.sh"
cp ../LICENSE "$release_dir/LICENSE"
cp THIRD_PARTY_NOTICES.md "$release_dir/THIRD_PARTY_NOTICES.md"
(
    cd "$release_dir"
    shasum -a 256 "$asset" install.sh LICENSE THIRD_PARTY_NOTICES.md > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)
print "发布附件：$release_dir"
