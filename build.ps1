$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Work = Join-Path $Root 'build'
$Dist = Join-Path $Root 'dist'
$Stage = Join-Path $Work 'module'
$Zip = Join-Path $Dist 'WxPayMonitor-magisk.zip'

Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Work,$Dist | Out-Null
Remove-Item -Force (Join-Path $Dist 'WxPayMonitor.apk') -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $Dist 'WxPayMonitor.apk.idsig') -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force (Join-Path $Root 'module') $Stage

Get-ChildItem $Stage -Filter *.sh -Recurse | ForEach-Object {
  $text = [IO.File]::ReadAllText($_.FullName).Replace("`r`n", "`n")
  [IO.File]::WriteAllText($_.FullName, $text, [Text.UTF8Encoding]::new($false))
}

Remove-Item -Force $Zip -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $Zip
Get-FileHash -Algorithm SHA256 $Zip | Format-Table Path,Hash -AutoSize
Write-Host "Built pure Magisk module (no APK): $Zip"
