$ErrorActionPreference='Stop'
try {
 $path=Join-Path $PSScriptRoot 'config.json'
 if(-not (Test-Path -LiteralPath $path)){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config.example.json') -Destination $path}
 $c=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
 if($c.character){if((Read-Host 'Existing config detected. Overwrite? Type YES') -cne 'YES'){exit 0}}
 $game=(Read-Host 'Full path to Wow.exe').Trim().Trim('"')
 if(-not (Test-Path -LiteralPath $game -PathType Leaf) -or [IO.Path]::GetFileName($game) -ine 'Wow.exe'){throw 'Invalid Wow.exe path'}
 $character=(Read-Host 'Character-Realm (exact in-game full name)').Trim()
 if(-not $character -or $character -notmatch '.+-.+'){throw 'Use Character-Realm, including the realm'}
 $secret=Read-Host 'Your DeepSeek API key (hidden); leave blank to use DEEPSEEK_API_KEY environment variable' -AsSecureString
 $key=[Net.NetworkCredential]::new('',$secret).Password
 if($key){
  if($key -notmatch '^sk-[A-Za-z0-9_-]+$'){throw 'Expected a DeepSeek sk- API key'}
  [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'credentials.yaml'),"refs:`n  DEEPSEEK_API_KEY: `"$key`"`n",[Text.UTF8Encoding]::new($false))
 } elseif(-not $env:DEEPSEEK_API_KEY){throw 'No API key provided or available in the environment'}
 $key=$null;$secret.Dispose()
 $c.gameExe=[IO.Path]::GetFullPath($game);$c.character=$character;$c.hotkey='';$c.paused=$false
 [IO.File]::WriteAllText($path,($c|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 Write-Host 'Configured. Run install-addon.bat, then run.bat. Keep credentials.yaml private.'
} catch {Write-Error $_;exit 1}
