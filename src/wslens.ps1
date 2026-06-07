$ErrorActionPreference = 'Stop'

$script:CwdWin = (Get-Location).Path

function Show-Usage {
@'
wslens: list, capture, and manipulate Windows top-level windows from WSL

Usage:
  wslens list [--all] [--json] [--title REGEX] [--process REGEX]
  wslens bounds <target> [--json]
  wslens capture <target> [-o PATH] [--restore] [--json]
  wslens resize <target> <width> <height> [--x X] [--y Y] [--restore] [--activate] [--json]
  wslens move <target> <x> <y> [--restore] [--activate] [--json]
  wslens focus <target> [--json]
  wslens close <target> [--json]

Targets:
  idx:N             window index from `wslens list`
  N                 same as idx:N if N matches a listed index
  0xHWND            window handle, e.g. 0x8032E
  hwnd:0xHWND       explicit window handle
  title:REGEX       first listed window whose title matches REGEX
  process:REGEX     first listed window whose process matches REGEX

Examples:
  wslens list
  wslens capture idx:16 -o shot.png
  wslens resize 16 1200 800
  wslens resize 0x8032E 1200 800 --x 100 --y 80
  wslens move title:Spotify 50 50
  wslens close title:Spotify
'@
}

# Raise a terminating error carrying an explicit process exit code. The
# top-level dispatcher reads Exception.Data['ExitCode'] to set the real exit
# status. Using throw (not Write-Error + exit) keeps the code honoured and
# makes Fail testable when the script is dot-sourced.
function Fail([string]$Message, [int]$Code = 1) {
  $err = New-Object System.Exception($Message)
  $err.Data['ExitCode'] = $Code
  throw $err
}

# Validate a user-supplied regular expression before it reaches -match, so a
# malformed pattern fails cleanly instead of surfacing a raw .NET exception.
function Assert-ValidRegex([string]$Pattern) {
  try {
    [void][System.Text.RegularExpressions.Regex]::new($Pattern)
  } catch {
    Fail "Invalid regular expression: $Pattern"
  }
}

function Strip-InternalArgs([object[]]$InputArgs) {
  $list = New-Object 'System.Collections.Generic.List[string]'
  foreach ($a in $InputArgs) { [void]$list.Add([string]$a) }
  for ($i = 0; $i -lt $list.Count; $i++) {
    if ($list[$i] -eq '--cwd-win') {
      if ($i + 1 -ge $list.Count) { Fail 'Missing value for --cwd-win' }
      $script:CwdWin = $list[$i + 1]
      $list.RemoveAt($i + 1)
      $list.RemoveAt($i)
      $i--
    }
  }
  return @($list.ToArray())
}

Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class WinCtlNative {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll")]
  public static extern bool SetProcessDPIAware();

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool IsWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool IsIconic(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool IsZoomed(IntPtr hWnd);

  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, int nFlags);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
"@

# Named Win32 constants used below.
$script:SW_RESTORE          = 9
$script:PW_RENDERFULLCONTENT = 2
$script:SWP_NOSIZE          = 0x0001
$script:SWP_NOZORDER        = 0x0004
$script:SWP_NOACTIVATE      = 0x0010
$script:WM_CLOSE            = 0x0010

[void][WinCtlNative]::SetProcessDPIAware()

function Parse-Int([string]$Value, [string]$Name) {
  $n = 0
  if (-not [int]::TryParse($Value, [ref]$n)) { Fail "Invalid ${Name}: $Value" }
  return $n
}

function Parse-HwndValue([string]$Value) {
  $s = $Value
  if ($s.StartsWith('hwnd:', [System.StringComparison]::OrdinalIgnoreCase)) { $s = $s.Substring(5) }
  if ($s.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
    try {
      return [Convert]::ToInt64($s.Substring(2), 16)
    } catch {
      Fail "Invalid HWND: $Value"
    }
  }
  $n = 0L
  if (-not [Int64]::TryParse($s, [ref]$n)) { Fail "Invalid HWND: $Value" }
  return $n
}

function Get-State([IntPtr]$Hwnd) {
  if ([WinCtlNative]::IsIconic($Hwnd)) { return 'minimized' }
  if ([WinCtlNative]::IsZoomed($Hwnd)) { return 'maximized' }
  return 'normal'
}

# Single source of truth for extracting a window's properties from an HWND.
# Both the EnumWindows listing callback and the direct-HWND resolver use this.
function Get-WindowInfo([IntPtr]$Hwnd) {
  $sb = New-Object System.Text.StringBuilder 2048
  [void][WinCtlNative]::GetWindowText($Hwnd, $sb, $sb.Capacity)
  $title = $sb.ToString()

  [uint32]$procId = 0
  [void][WinCtlNative]::GetWindowThreadProcessId($Hwnd, [ref]$procId)
  $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue

  $rect = New-Object WinCtlNative+RECT
  $rectOk = [WinCtlNative]::GetWindowRect($Hwnd, [ref]$rect)
  if ($rectOk) {
    $x = $rect.Left
    $y = $rect.Top
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
  } else {
    $x = 0
    $y = 0
    $width = 0
    $height = 0
  }

  return [pscustomobject]@{
    Hwnd = ('0x{0:X}' -f $Hwnd.ToInt64())
    HwndValue = $Hwnd.ToInt64()
    Pid = $procId
    Process = if ($proc) { $proc.ProcessName } else { '?' }
    Title = $title
    X = $x
    Y = $y
    Width = $width
    Height = $height
    State = Get-State $Hwnd
    Visible = [WinCtlNative]::IsWindowVisible($Hwnd)
  }
}

function Get-WindowObjectFromHwnd([IntPtr]$Hwnd, [int]$Idx) {
  $info = Get-WindowInfo $Hwnd
  return ($info | Add-Member -NotePropertyName Idx -NotePropertyValue $Idx -Force -PassThru)
}

function Get-Windows([bool]$IncludeAll) {
  $rows = New-Object 'System.Collections.Generic.List[object]'
  $cb = [WinCtlNative+EnumWindowsProc]{
    param([IntPtr]$hwnd, [IntPtr]$lparam)

    $info = Get-WindowInfo $hwnd
    if (-not $IncludeAll -and (-not $info.Visible -or [string]::IsNullOrWhiteSpace($info.Title))) {
      return $true
    }
    [void]$rows.Add($info)
    return $true
  }

  [void][WinCtlNative]::EnumWindows($cb, [IntPtr]::Zero)

  $idx = 0
  @($rows | Sort-Object Process, Title, HwndValue | ForEach-Object {
    $idx++
    $_ | Add-Member -NotePropertyName Idx -NotePropertyValue $idx -Force -PassThru
  })
}

function Resolve-Target([string]$Target, [bool]$IncludeAll) {
  $windows = @(Get-Windows $IncludeAll)

  if ($Target.StartsWith('idx:', [System.StringComparison]::OrdinalIgnoreCase)) {
    $idx = Parse-Int $Target.Substring(4) 'index'
    $match = $windows | Where-Object { $_.Idx -eq $idx } | Select-Object -First 1
    if (-not $match) { Fail "No listed window at index $idx" }
    return $match
  }

  if ($Target.StartsWith('title:', [System.StringComparison]::OrdinalIgnoreCase)) {
    $pattern = $Target.Substring(6)
    Assert-ValidRegex $pattern
    $match = $windows | Where-Object { $_.Title -match $pattern } | Select-Object -First 1
    if (-not $match) { Fail "No listed window title matches: $pattern" }
    return $match
  }

  if ($Target.StartsWith('process:', [System.StringComparison]::OrdinalIgnoreCase)) {
    $pattern = $Target.Substring(8)
    Assert-ValidRegex $pattern
    $match = $windows | Where-Object { $_.Process -match $pattern } | Select-Object -First 1
    if (-not $match) { Fail "No listed window process matches: $pattern" }
    return $match
  }

  if ($Target.StartsWith('hwnd:', [System.StringComparison]::OrdinalIgnoreCase) -or $Target.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
    $value = Parse-HwndValue $Target
    $hwnd = [IntPtr]$value
    if (-not [WinCtlNative]::IsWindow($hwnd)) { Fail "No window exists for HWND $('0x{0:X}' -f $value)" }
    $match = $windows | Where-Object { $_.HwndValue -eq $value } | Select-Object -First 1
    if ($match) { return $match }
    return Get-WindowObjectFromHwnd $hwnd 0
  }

  if ($Target -match '^\d+$') {
    $idx = Parse-Int $Target 'index'
    $match = $windows | Where-Object { $_.Idx -eq $idx } | Select-Object -First 1
    if ($match) { return $match }

    $value = Parse-HwndValue $Target
    $hwnd = [IntPtr]$value
    if ([WinCtlNative]::IsWindow($hwnd)) { return Get-WindowObjectFromHwnd $hwnd 0 }
  }

  Fail "Could not resolve target: $Target"
}

function Get-ArgValue([string[]]$Items, [ref]$Index, [string]$Name) {
  if ($Index.Value + 1 -ge $Items.Count) { Fail "Missing value for $Name" }
  $Index.Value++
  return $Items[$Index.Value]
}

function Select-DisplayColumns($Items) {
  $Items | Select-Object Idx,Hwnd,Pid,Process,Title,X,Y,Width,Height,State,Visible
}

function Write-Table($Items) {
  $Items | Format-Table -AutoSize | Out-String -Width 300 | Write-Host -NoNewline
}

function Get-DefaultCapturePath($Win) {
  $name = 'window-{0}-{1}.png' -f $Win.Idx, ($Win.Hwnd -replace ':', '')
  return [System.IO.Path]::Combine($script:CwdWin, $name)
}

function Capture-Window($Win, [string]$OutputPath, [bool]$RestoreFirst) {
  $hwnd = [IntPtr]$Win.HwndValue
  if ($RestoreFirst -and [WinCtlNative]::IsIconic($hwnd)) { [void][WinCtlNative]::ShowWindow($hwnd, $script:SW_RESTORE) }

  $rect = New-Object WinCtlNative+RECT
  if (-not [WinCtlNative]::GetWindowRect($hwnd, [ref]$rect)) {
    Fail "GetWindowRect failed for $($Win.Hwnd): $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
  }

  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -le 0 -or $height -le 0) { Fail "Invalid window bounds for $($Win.Hwnd): ${width}x${height}" }

  $dir = [System.IO.Path]::GetDirectoryName($OutputPath)
  if (-not [string]::IsNullOrWhiteSpace($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }

  $bmp = New-Object System.Drawing.Bitmap $width, $height
  try {
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $gfx.GetHdc()
    $ok = $false
    try {
      $ok = [WinCtlNative]::PrintWindow($hwnd, $hdc, $script:PW_RENDERFULLCONTENT)
    } finally {
      $gfx.ReleaseHdc($hdc)
      $gfx.Dispose()
    }
    $bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $bmp.Dispose()
  }

  $file = Get-Item -LiteralPath $OutputPath
  return [pscustomobject]@{
    Hwnd = $Win.Hwnd
    PrintWindowOk = $ok
    Width = $width
    Height = $height
    Bytes = $file.Length
    Path = $file.FullName
  }
}

function Set-WindowBounds($Win, [int]$X, [int]$Y, [int]$Width, [int]$Height, [bool]$RestoreFirst, [bool]$Activate) {
  $hwnd = [IntPtr]$Win.HwndValue
  if ($RestoreFirst -and [WinCtlNative]::IsIconic($hwnd)) { [void][WinCtlNative]::ShowWindow($hwnd, $script:SW_RESTORE) }

  $flags = $script:SWP_NOZORDER
  if (-not $Activate) { $flags = $flags -bor $script:SWP_NOACTIVATE }
  $ok = [WinCtlNative]::SetWindowPos($hwnd, [IntPtr]::Zero, $X, $Y, $Width, $Height, [uint32]$flags)
  if (-not $ok) { Fail "SetWindowPos failed for $($Win.Hwnd): $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
  return Get-WindowObjectFromHwnd $hwnd $Win.Idx
}

function Close-Window($Win) {
  $hwnd = [IntPtr]$Win.HwndValue
  $ok = [WinCtlNative]::PostMessage($hwnd, [uint32]$script:WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
  if (-not $ok) { Fail "PostMessage(WM_CLOSE) failed for $($Win.Hwnd): $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
  return [pscustomobject]@{
    Hwnd = $Win.Hwnd
    ClosePosted = $ok
  }
}

function Focus-Window($Win) {
  $hwnd = [IntPtr]$Win.HwndValue
  if ([WinCtlNative]::IsIconic($hwnd)) { [void][WinCtlNative]::ShowWindow($hwnd, $script:SW_RESTORE) }
  $ok = [WinCtlNative]::SetForegroundWindow($hwnd)
  return [pscustomobject]@{
    Hwnd = $Win.Hwnd
    Focused = $ok
  }
}

function Invoke-Wslens([string[]]$Argv) {
  $cmd = $Argv[0].ToLowerInvariant()
  $cmdArgs = @()
  if ($Argv.Count -gt 1) { $cmdArgs = @($Argv[1..($Argv.Count - 1)]) }

  switch ($cmd) {
    'list' {
      $includeAll = $false
      $json = $false
      $titleFilter = $null
      $processFilter = $null

      for ($i = 0; $i -lt $cmdArgs.Count; $i++) {
        switch -Regex ($cmdArgs[$i]) {
          '^--all$' { $includeAll = $true; continue }
          '^--json$' { $json = $true; continue }
          '^--title$' { $titleFilter = Get-ArgValue $cmdArgs ([ref]$i) '--title'; continue }
          '^--process$' { $processFilter = Get-ArgValue $cmdArgs ([ref]$i) '--process'; continue }
          default { Fail "Unknown list option: $($cmdArgs[$i])" }
        }
      }

      $wins = @(Get-Windows $includeAll)
      if ($titleFilter) { Assert-ValidRegex $titleFilter; $wins = @($wins | Where-Object { $_.Title -match $titleFilter }) }
      if ($processFilter) { Assert-ValidRegex $processFilter; $wins = @($wins | Where-Object { $_.Process -match $processFilter }) }

      if ($json) {
        $wins | ConvertTo-Json -Depth 5
      } else {
        Write-Table (Select-DisplayColumns $wins)
      }
      break
    }

    'bounds' {
      if ($cmdArgs.Count -lt 1) { Fail 'Usage: wslens bounds <target> [--json]' }
      $target = $cmdArgs[0]
      $json = $false
      for ($i = 1; $i -lt $cmdArgs.Count; $i++) {
        switch ($cmdArgs[$i]) {
          '--json' { $json = $true }
          default { Fail "Unknown bounds option: $($cmdArgs[$i])" }
        }
      }
      $win = Resolve-Target $target $false
      if ($json) { Select-DisplayColumns @($win) | ConvertTo-Json -Depth 5 } else { Write-Table (Select-DisplayColumns @($win)) }
      break
    }

    'capture' {
      if ($cmdArgs.Count -lt 1) { Fail 'Usage: wslens capture <target> [-o PATH] [--restore] [--json]' }
      $target = $cmdArgs[0]
      $output = $null
      $restore = $false
      $json = $false

      for ($i = 1; $i -lt $cmdArgs.Count; $i++) {
        $a = $cmdArgs[$i]
        if ($a -eq '-o' -or $a -eq '--output') {
          $output = Get-ArgValue $cmdArgs ([ref]$i) $a
        } elseif ($a.StartsWith('--output=', [System.StringComparison]::OrdinalIgnoreCase)) {
          $output = $a.Substring(9)
        } elseif ($a -eq '--restore') {
          $restore = $true
        } elseif ($a -eq '--json') {
          $json = $true
        } else {
          Fail "Unknown capture option: $a"
        }
      }

      $win = Resolve-Target $target $false
      if (-not $output) { $output = Get-DefaultCapturePath $win }
      $result = Capture-Window $win $output $restore
      if ($json) { $result | ConvertTo-Json -Depth 5 } else { $result | Format-List }
      break
    }

    'resize' {
      if ($cmdArgs.Count -lt 3) { Fail 'Usage: wslens resize <target> <width> <height> [--x X] [--y Y] [--restore] [--activate] [--json]' }
      $target = $cmdArgs[0]
      $width = Parse-Int $cmdArgs[1] 'width'
      $height = Parse-Int $cmdArgs[2] 'height'
      $x = $null
      $y = $null
      $restore = $false
      $activate = $false
      $json = $false

      for ($i = 3; $i -lt $cmdArgs.Count; $i++) {
        switch ($cmdArgs[$i]) {
          '--x' { $x = Parse-Int (Get-ArgValue $cmdArgs ([ref]$i) '--x') 'x' }
          '--y' { $y = Parse-Int (Get-ArgValue $cmdArgs ([ref]$i) '--y') 'y' }
          '--restore' { $restore = $true }
          '--activate' { $activate = $true }
          '--json' { $json = $true }
          default { Fail "Unknown resize option: $($cmdArgs[$i])" }
        }
      }

      if ($width -le 0 -or $height -le 0) { Fail 'Width and height must be positive' }
      $win = Resolve-Target $target $false
      if ($null -eq $x) { $x = [int]$win.X }
      if ($null -eq $y) { $y = [int]$win.Y }
      $after = Set-WindowBounds $win $x $y $width $height $restore $activate
      if ($json) { $after | ConvertTo-Json -Depth 5 } else { Write-Table (Select-DisplayColumns @($after)) }
      break
    }

    'move' {
      if ($cmdArgs.Count -lt 3) { Fail 'Usage: wslens move <target> <x> <y> [--restore] [--activate] [--json]' }
      $target = $cmdArgs[0]
      $x = Parse-Int $cmdArgs[1] 'x'
      $y = Parse-Int $cmdArgs[2] 'y'
      $restore = $false
      $activate = $false
      $json = $false

      for ($i = 3; $i -lt $cmdArgs.Count; $i++) {
        switch ($cmdArgs[$i]) {
          '--restore' { $restore = $true }
          '--activate' { $activate = $true }
          '--json' { $json = $true }
          default { Fail "Unknown move option: $($cmdArgs[$i])" }
        }
      }

      $win = Resolve-Target $target $false
      $after = Set-WindowBounds $win $x $y ([int]$win.Width) ([int]$win.Height) $restore $activate
      if ($json) { $after | ConvertTo-Json -Depth 5 } else { Write-Table (Select-DisplayColumns @($after)) }
      break
    }

    'close' {
      if ($cmdArgs.Count -lt 1) { Fail 'Usage: wslens close <target> [--json]' }
      $target = $cmdArgs[0]
      $json = $false

      for ($i = 1; $i -lt $cmdArgs.Count; $i++) {
        switch ($cmdArgs[$i]) {
          '--json' { $json = $true }
          default { Fail "Unknown close option: $($cmdArgs[$i])" }
        }
      }

      $win = Resolve-Target $target $false
      $result = Close-Window $win
      if ($json) { $result | ConvertTo-Json -Depth 5 } else { $result | Format-List }
      break
    }

    'focus' {
      if ($cmdArgs.Count -lt 1) { Fail 'Usage: wslens focus <target> [--json]' }
      $target = $cmdArgs[0]
      $json = $false

      for ($i = 1; $i -lt $cmdArgs.Count; $i++) {
        switch ($cmdArgs[$i]) {
          '--json' { $json = $true }
          default { Fail "Unknown focus option: $($cmdArgs[$i])" }
        }
      }

      $win = Resolve-Target $target $false
      $result = Focus-Window $win
      if ($json) { $result | ConvertTo-Json -Depth 5 } else { $result | Format-List }
      break
    }

    default {
      Show-Usage
      Fail "Unknown command: $cmd"
    }
  }
}

# Only dispatch when executed as a script (e.g. powershell -File). When the
# file is dot-sourced (tests), just define the functions above.
if ($MyInvocation.InvocationName -ne '.') {
  try {
    $argv = @(Strip-InternalArgs $args)
    if ($argv.Count -eq 0 -or $argv[0] -eq '--help' -or $argv[0] -eq '-h' -or $argv[0] -eq 'help') {
      Show-Usage
      exit 0
    }
    Invoke-Wslens $argv
  } catch {
    $code = 1
    if ($null -ne $_.Exception.Data['ExitCode']) { $code = [int]$_.Exception.Data['ExitCode'] }
    [Console]::Error.WriteLine('wslens: ' + $_.Exception.Message)
    exit $code
  }
}
