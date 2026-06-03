# wslens

![wslens hero: WSL code inspected through a lens into Windows application windows](assets/wslens-hero.png)

`wslens` lets WSL scripts list, capture, move, resize, focus, and close Windows top-level windows.

It is useful when a tool runs inside WSL but the application under test opens in Windows user space. For example, a coding agent can launch a Windows app, inspect its windows, take screenshots, resize it into a known shape, focus it, and close it again from the WSL side.

That closes the feedback loop for agentic development: the harness can see the result of what it changed instead of relying only on logs, build output, or the user describing the UI.

`wslens` is a small Bash wrapper plus a PowerShell backend that calls Windows APIs through `user32.dll`.

## Requirements

- WSL on Windows
- `powershell.exe` available in the WSL `PATH`
- `wslpath` and `realpath`

## Install

```bash
./install.sh
```

This installs:

- `~/.local/bin/wslens`
- `~/.local/share/wslens/wslens.ps1`

Make sure `~/.local/bin` is in your `PATH`.

## Usage

```text
wslens list [--all] [--json] [--title REGEX] [--process REGEX]
wslens bounds <target> [--json]
wslens capture <target> [-o PATH] [--restore] [--json]
wslens resize <target> <width> <height> [--x X] [--y Y] [--restore] [--activate] [--json]
wslens move <target> <x> <y> [--restore] [--activate] [--json]
wslens focus <target>
wslens close <target> [--json]
```

Targets:

```text
idx:N             window index from `wslens list`
N                 same as idx:N if N matches a listed index
0xHWND            window handle, e.g. 0x8032E
hwnd:0xHWND       explicit window handle
title:REGEX       first listed window whose title matches REGEX
process:REGEX     first listed window whose process matches REGEX
```

Examples:

```bash
wslens list
wslens capture idx:16 -o shot.png
wslens resize 16 1200 800
wslens resize 0x8032E 1200 800 --x 100 --y 80
wslens move title:Spotify 50 50
wslens close title:Spotify
```

## Agent development workflow

A typical loop from WSL looks like this:

```bash
# Start or rebuild the app from WSL, even if it opens a Windows window.
npm run dev

# Find the window the app opened.
wslens list --process "chrome|msedge|electron"

# Put it in a predictable position and size before inspecting it.
wslens resize title:MyApp 1400 900 --x 80 --y 80 --activate

# Capture the current UI into the WSL working directory.
wslens capture title:MyApp -o artifacts/myapp.png

# Close it when the run is done.
wslens close title:MyApp
```

This is especially handy for coding harnesses and other automation running inside WSL. The agent can make a code change, run the app, capture the Windows UI, inspect the screenshot, and iterate without needing manual screenshots or copy-pasted descriptions.
