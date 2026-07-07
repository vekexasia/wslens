$ErrorActionPreference = 'Stop'

$dest = if ($env:WSLENS_INSTALL_DIR) { $env:WSLENS_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'wslens' }
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot 'src\wslens.ps1') (Join-Path $dest 'wslens.ps1')
Copy-Item -Force (Join-Path $PSScriptRoot 'bin\wslens.cmd') (Join-Path $dest 'wslens.cmd')

Write-Host "Installed wslens:"
Write-Host "  $(Join-Path $dest 'wslens.cmd')"
Write-Host "  $(Join-Path $dest 'wslens.ps1')"
if ((($env:Path -split ';') | Where-Object { $_ -eq $dest }).Count -eq 0) {
  Write-Host ""
  Write-Host "Add it to your user PATH, e.g.:"
  Write-Host "  [Environment]::SetEnvironmentVariable('Path', `$env:Path + ';$dest', 'User')"
}
