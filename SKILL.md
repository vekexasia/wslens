---
name: wslens
description: Inspect and drive Windows GUI apps from WSL. Use when you or the user need to see, screenshot, click, type into, launch, resize, or close a Windows application window, or to verify Windows-side UI state (screensaver, monitors, foreground window) from a WSL session.
---

# wslens

`wslens` is a CLI that lets WSL sessions observe and control Windows top-level windows. Use it to close the feedback loop when code running in WSL opens or affects a Windows app: launch it, screenshot it, click/type into it, verify the result, close it.

Requires `wslens` in PATH and `powershell.exe` reachable from WSL.

## Commands

### Observe

```bash
# list visible top-level windows (idx, hwnd, pid, process, title, bounds, state)
wslens list [--all] [--json] [--title REGEX] [--process REGEX]

# position, size, and state of one window
wslens bounds <target> [--json]

# current foreground window
wslens active [--json]

# monitors with bounds and working area
wslens monitors [--json]

# screenshot one window to PNG
wslens capture <target> [-o PATH] [--restore] [--json]

# screenshot the whole virtual desktop (all monitors) to PNG
wslens screen [-o PATH] [--json]

# record a window or the desktop to MKV/MP4 via ffmpeg
wslens record start <target|screen> [-o PATH] [--fps N] [--json]
wslens record stop [--json]

# serialize global foreground/input across agents
wslens lease acquire <target> [--ttl SECONDS] [--json]
wslens lease release <token> [--json]
```

### Arrange

```bash
# set window size (and optionally position)
wslens resize <target> <width> <height> [--x X] [--y Y] [--restore] [--activate] [--json]

# set window position
wslens move <target> <x> <y> [--restore] [--activate] [--json]

# bring window to foreground
wslens focus <target> [--lease TOKEN] [--json]
```

### Interact

```bash
# left-click at screen coords, or window-relative with --relative
wslens click <target> <x> <y> [--relative] [--restore] [--activate] [--lease TOKEN] [--json]

# left-drag from one point to another
wslens drag <target> <x1> <y1> <x2> <y2> [--relative] [--restore] [--activate] [--lease TOKEN] [--json]

# send key chords in SendKeys syntax (^l = Ctrl+L, {ENTER}, ...)
wslens key <target> <sendkeys> [--restore] [--activate] [--lease TOKEN] [--json]

# type literal text (pasted via clipboard)
wslens type <target> <text> [--restore] [--activate] [--lease TOKEN] [--json]
```

### Lifecycle

```bash
# start a Windows exe, document, or URI
wslens launch <command-or-uri> [args...] [--json]

# ask window to close (WM_CLOSE)
wslens close <target> [--json]
```

### Session state

```bash
# is a screensaver running?
wslens screensaver [--json]

# dismiss the screensaver (cannot unlock a locked session)
wslens wake [--json]
```

Targets: `idx:N` (from `list`), bare `N`, `0xHWND`, `hwnd:0xHWND`, `title:REGEX`, `process:REGEX`.

## Rules for agents

- Always pass `--json`; 
- Before multi-step input, acquire an input lease: `token=$(wslens lease acquire <target> --json | jq -r .token)`, pass `--lease "$token"`, then release it.
- Before clicking or typing, `resize` the window to a known size and use `--relative --activate` so coordinates are window-relative and input lands in the right app.
- Capture a screenshot before and after an interaction; read the image to verify the click/type had the intended effect. Never assume an input worked.
- `key` uses WinForms SendKeys syntax: `^` Ctrl, `%` Alt, `+` Shift, `{ENTER}`, `{TAB}`, e.g. `wslens key title:Chrome '^l' --activate`.
- `type` pastes via clipboard (clobbers the Windows clipboard).
- `launch` handles exes, documents, and URIs; URI launches may return `pid: null`.
- `wake` only dismisses the screensaver. `screensaver_dismissed: true` says nothing about lock state; a locked workstation cannot be unlocked.
- Output paths for `capture`/`screen`/`record start` accept WSL paths (`-o artifacts/shot.png`); conversion is handled by the wrapper.
- Use `record start <target> -o artifacts/demo.mkv --json` before a flow and `record stop --json` after it when the user needs a video artifact.

## Gotchas

If interaction seem to not go through it might be because of screensaver or because the window is in another active desktop. 

