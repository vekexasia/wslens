# winctl

`winctl` lists, captures, moves, resizes, focuses, and closes Windows top-level windows from WSL.

It is a small Bash wrapper plus a PowerShell backend that calls Windows APIs through `user32.dll`.

## Requirements

- WSL on Windows
- `powershell.exe` available in the WSL `PATH`
- `wslpath` and `realpath`

## Install

```bash
./install.sh
```

This installs:

- `~/.local/bin/winctl`
- `~/.local/share/winctl/winctl.ps1`

Make sure `~/.local/bin` is in your `PATH`.

## Usage

```text
winctl list [--all] [--json] [--title REGEX] [--process REGEX]
winctl bounds <target> [--json]
winctl capture <target> [-o PATH] [--restore] [--json]
winctl resize <target> <width> <height> [--x X] [--y Y] [--restore] [--activate] [--json]
winctl move <target> <x> <y> [--restore] [--activate] [--json]
winctl focus <target>
winctl close <target> [--json]
```

Targets:

```text
idx:N             window index from `winctl list`
N                 same as idx:N if N matches a listed index
0xHWND            window handle, e.g. 0x8032E
hwnd:0xHWND       explicit window handle
title:REGEX       first listed window whose title matches REGEX
process:REGEX     first listed window whose process matches REGEX
```

Examples:

```bash
winctl list
winctl capture idx:16 -o shot.png
winctl resize 16 1200 800
winctl resize 0x8032E 1200 800 --x 100 --y 80
winctl move title:Spotify 50 50
winctl close title:Spotify
```
