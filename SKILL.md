---
name: wslens
description: Inspect and drive Windows GUI apps from WSL. Use when the user asks to see, screenshot, click, type into, launch, resize, or close a Windows application window, or to verify Windows-side UI state (screensaver, monitors, foreground window) from a WSL session.
---

# wslens

`wslens` is a CLI that lets WSL sessions observe and control Windows top-level windows. Use it to close the feedback loop when code running in WSL opens or affects a Windows app: launch it, screenshot it, click/type into it, verify the result, close it.

Requires `wslens` in PATH (installed via `~/git/personale/wslens/install.sh`) and `powershell.exe` reachable from WSL.

## Commands

```text
wslens list [--all] [--json] [--title REGEX] [--process REGEX]
wslens bounds <target> [--json]
wslens capture <target> [-o PATH] [--restore] [--json]
wslens screen [-o PATH] [--json]
wslens resize <target> <width> <height> [--x X] [--y Y] [--restore] [--activate] [--json]
wslens move <target> <x> <y> [--restore] [--activate] [--json]
wslens focus <target> [--json]
wslens click <target> <x> <y> [--relative] [--restore] [--activate] [--json]
wslens drag <target> <x1> <y1> <x2> <y2> [--relative] [--restore] [--activate] [--json]
wslens key <target> <sendkeys> [--restore] [--activate] [--json]
wslens type <target> <text> [--restore] [--activate] [--json]
wslens close <target> [--json]
wslens launch <command-or-uri> [args...] [--json]
wslens active [--json]
wslens monitors [--json]
wslens screensaver [--json]
wslens wake [--json]
```

Targets: `idx:N` (from `list`), bare `N`, `0xHWND`, `hwnd:0xHWND`, `title:REGEX`, `process:REGEX`.

## Rules for agents

- Always pass `--json`; keys are snake_case (`hwnd`, `pid`, `work_width`, `screensaver_running`).
- Before clicking or typing, `resize` the window to a known size and use `--relative --activate` so coordinates are window-relative and input lands in the right app.
- Capture a screenshot before and after an interaction; read the image to verify the click/type had the intended effect. Never assume an input worked.
- `key` uses WinForms SendKeys syntax: `^` Ctrl, `%` Alt, `+` Shift, `{ENTER}`, `{TAB}`, e.g. `wslens key title:Chrome '^l' --activate`.
- `type` pastes via clipboard (clobbers the Windows clipboard).
- `launch` handles exes, documents, and URIs; URI launches may return `pid: null`.
- `wake` only dismisses the screensaver. `screensaver_dismissed: true` says nothing about lock state; a locked workstation cannot be unlocked.
- Output paths for `capture`/`screen` accept WSL paths (`-o artifacts/shot.png`); conversion is handled by the wrapper.

## Typical loop

```bash
wslens launch notepad.exe
wslens list --process notepad --json
wslens resize process:notepad 1200 800 --x 80 --y 80 --activate
wslens type process:notepad 'hello' --activate
wslens capture process:notepad -o artifacts/notepad.png
wslens close process:notepad
```
