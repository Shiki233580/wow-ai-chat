$ErrorActionPreference='Stop'
throw 'Isolated development version: installation into the game is disabled. Online1.18.20 is untouched.'
try {
 $c=Get-Content (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if(-not $c.gameExe -or -not (Test-Path -LiteralPath $c.gameExe -PathType Leaf)){throw 'Run setup.bat first'}
 $root=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $c.gameExe) 'Interface\AddOns'))
 $target=[IO.Path]::GetFullPath((Join-Path $root 'DaFeiYu'));$source=Join-Path $PSScriptRoot 'addon\DaFeiYu'
 if(-not $target.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Target is outside AddOns'}
 if(Test-Path -LiteralPath $target){
  $backup=Join-Path $PSScriptRoot ('backups\DaFeiYu-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
  New-Item -ItemType Directory -Path (Split-Path $backup) -Force|Out-Null
  Copy-Item -LiteralPath $target -Destination $backup -Recurse
  Write-Host "Backup: $backup"
 }
 New-Item -ItemType Directory -Path $target -Force|Out-Null
 Get-ChildItem -LiteralPath $source -File|ForEach-Object {
  $dest=Join-Path $target $_.Name;Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
  if((Get-FileHash -LiteralPath $_.FullName).Hash -ne (Get-FileHash -LiteralPath $dest).Hash){throw "Hash mismatch: $dest"}
 }
 Write-Host "Installed and verified: $target"
 Write-Host 'Enable DaFeiYu in game and /reload. Permission denied? Run this installer as Administrator.'
} catch {Write-Error $_;exit 1}
