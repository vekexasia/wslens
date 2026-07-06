$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\src\wslens.ps1')

Describe 'Parse-HwndValue' {
  It 'parses 0x hex' {
    Parse-HwndValue '0x10' | Should Be 16
  }
  It 'parses hwnd: prefix with hex' {
    Parse-HwndValue 'hwnd:0x1F' | Should Be 31
  }
  It 'parses decimal' {
    Parse-HwndValue '255' | Should Be 255
  }
  It 'fails cleanly on bad hex (#6)' {
    { Parse-HwndValue '0xZZ' } | Should Throw
  }
  It 'bad hex throws Wslens failure carrying exit code (#6/#5)' {
    $code = 0
    try { Parse-HwndValue '0xZZ' } catch { $code = $_.Exception.Data['ExitCode'] }
    $code | Should Be 1
  }
  It 'fails cleanly on garbage' {
    { Parse-HwndValue 'nothex' } | Should Throw
  }
}

Describe 'Fail exit code (#5)' {
  It 'throws an exception that carries the requested exit code' {
    $code = 0
    try { Fail 'boom' 7 } catch { $code = $_.Exception.Data['ExitCode'] }
    $code | Should Be 7
  }
  It 'defaults exit code to 1' {
    $code = 0
    try { Fail 'boom' } catch { $code = $_.Exception.Data['ExitCode'] }
    $code | Should Be 1
  }
}

Describe 'Assert-ValidRegex (#2)' {
  It 'accepts a valid pattern' {
    { Assert-ValidRegex 'chrome|edge' } | Should Not Throw
  }
  It 'rejects an invalid pattern with a clean failure' {
    { Assert-ValidRegex '[' } | Should Throw
  }
  It 'invalid pattern carries exit code' {
    $code = 0
    try { Assert-ValidRegex '(' } catch { $code = $_.Exception.Data['ExitCode'] }
    $code | Should Be 1
  }
}

Describe 'Get-WindowInfo dedup (#7)' {
  It 'is defined as the single window-extraction helper' {
    (Get-Command Get-WindowInfo -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
  }
  It 'returns the expected property shape for a real top-level window' {
    $win = @(Get-Windows $false)[0]
    $win | Should Not BeNullOrEmpty
    $info = Get-WindowInfo ([IntPtr]$win.HwndValue)
    $names = $info.PSObject.Properties.Name
    foreach ($p in 'Hwnd','HwndValue','Pid','Process','Title','X','Y','Width','Height','State','Visible') {
      $names -contains $p | Should Be $true
    }
  }
}

Describe 'Get-Windows listing' {
  It 'returns indexed rows' {
    $wins = @(Get-Windows $false)
    $wins.Count | Should BeGreaterThan 0
    $wins[0].Idx | Should Be 1
  }
}

Describe 'Get-Monitors' {
  It 'returns at least one screen with a primary' {
    $mons = @(Get-Monitors)
    $mons.Count | Should BeGreaterThan 0
    @($mons | Where-Object { $_.Primary }).Count | Should Be 1
    $names = $mons[0].PSObject.Properties.Name
    foreach ($p in 'DeviceName','Primary','X','Y','Width','Height','WorkX','WorkY','WorkWidth','WorkHeight') {
      $names -contains $p | Should Be $true
    }
  }
}

Describe 'Get-ForegroundWindowObject' {
  It 'returns a window object with Hwnd when a foreground window exists' {
    if ([WinCtlNative]::GetForegroundWindow() -eq [IntPtr]::Zero) { return }
    $win = Get-ForegroundWindowObject
    $win.Hwnd | Should Not BeNullOrEmpty
  }
}

Describe 'Input coordinate helpers' {
  It 'keeps absolute coordinates unchanged' {
    $win = [pscustomobject]@{ X = 100; Y = 50 }
    $p = Get-WindowPoint $win 10 20 $false
    $p.X | Should Be 10
    $p.Y | Should Be 20
  }
  It 'converts relative window coordinates to screen coordinates' {
    $win = [pscustomobject]@{ X = 100; Y = 50 }
    $p = Get-WindowPoint $win 10 20 $true
    $p.X | Should Be 110
    $p.Y | Should Be 70
  }
}

Describe 'Quote-ProcessArg' {
  It 'leaves simple args alone' {
    Quote-ProcessArg 'desktop' | Should Be 'desktop'
  }
  It 'quotes args with spaces' {
    Quote-ProcessArg 'title=My App' | Should Be '"title=My App"'
  }
}

Describe 'Input lease' {
  It 'blocks input without matching token while leased' {
    Remove-Item -LiteralPath $script:LeaseStatePath -ErrorAction SilentlyContinue
    $win = [pscustomobject]@{ Title = 'A'; Hwnd = '0x1'; HwndValue = 1; Pid = 1 }
    $lease = New-InputLease $win 30
    { Assert-InputLease $win $null } | Should Throw
    { Assert-InputLease $win 'bad' } | Should Throw
    { Assert-InputLease $win $lease.Token } | Should Not Throw
    Remove-Item -LiteralPath $script:LeaseStatePath -ErrorAction SilentlyContinue
  }
}
