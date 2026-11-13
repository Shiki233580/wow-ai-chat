$ErrorActionPreference='Stop'
try {
 $c=Get-Content (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if(-not $c.character -or -not $c.gameExe -or -not (Test-Path -LiteralPath $c.gameExe -PathType Leaf)){throw 'Run setup.bat first'}
 if(-not $env:DEEPSEEK_API_KEY -and -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $c.credentialFile))){throw 'Missing API key; run setup.bat'}
 Start-Process -FilePath (Join-Path $PSScriptRoot 'WhaleChat.exe') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
} catch {Write-Error $_;exit 1}
