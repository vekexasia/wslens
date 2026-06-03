#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${WINCTL_BIN_DIR:-$HOME/.local/bin}"
share_dir="${WINCTL_SHARE_DIR:-$HOME/.local/share/winctl}"

install -d "$bin_dir" "$share_dir"
install -m 0755 "$repo_dir/bin/winctl" "$bin_dir/winctl"
install -m 0644 "$repo_dir/src/winctl.ps1" "$share_dir/winctl.ps1"

cat <<MSG
Installed winctl:
  $bin_dir/winctl
  $share_dir/winctl.ps1

Make sure $bin_dir is in PATH.
MSG
