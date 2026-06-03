#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${WSLENS_BIN_DIR:-$HOME/.local/bin}"
share_dir="${WSLENS_SHARE_DIR:-$HOME/.local/share/wslens}"

install -d "$bin_dir" "$share_dir"
install -m 0755 "$repo_dir/bin/wslens" "$bin_dir/wslens"
install -m 0644 "$repo_dir/src/wslens.ps1" "$share_dir/wslens.ps1"

cat <<MSG
Installed wslens:
  $bin_dir/wslens
  $share_dir/wslens.ps1

Make sure $bin_dir is in PATH.
MSG
