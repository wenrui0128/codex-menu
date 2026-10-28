#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p .build/scenario-renderer
sources=(Sources/CodexMenu/*.swift)
sources=("${(@)sources:#Sources/CodexMenu/main.swift}")
swiftc -O -module-cache-path .build/clang-module-cache \
    "${sources[@]}" scripts/render-scenarios/main.swift \
    -lsqlite3 -o .build/scenario-renderer/render
.build/scenario-renderer/render "${1:-$project_dir/review-scenarios}"
