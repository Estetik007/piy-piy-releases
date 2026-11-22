$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'Programs\piy-piy'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\piy-piy'

function Install([string] $file, [int] $expectedCode) {
    $run = Start-Process $file -PassThru -Wait -ArgumentList '/S'
    if ($run.ExitCode -ne $expectedCode) { throw "$file exited with $($run.ExitCode)" }
}

$updater = (Resolve-Path 'release-files/piy-piy-setup-0.1.12-x64.exe').Path
$fullSetup = (Resolve-Path 'release-files/piy-piy-full-0.1.12-x64.exe').Path
Install $updater 1
if (Test-Path (Join-Path $root 'piy-piy-launcher.exe')) { throw 'The updater performed a fresh install' }
Install $fullSetup 0
if ((Get-ItemProperty $key).DisplayVersion -ne '0.1.12' -or
    -not (Test-Path (Join-Path $root 'versions\0.1.10\piy-piy.pck'))) {
    throw 'The full installer is missing the current offline game'
}
Write-Host 'Fresh installation includes game 0.1.10 and launcher 0.1.12'
Install (Join-Path $root 'uninstall.exe') 0
for ($attempt = 0; $attempt -lt 40 -and (Test-Path $root); $attempt++) {
    Start-Sleep -Milliseconds 250
}
if (Test-Path $root) { throw 'Full installation cleanup did not finish' }

$olderSetup = Join-Path $env:RUNNER_TEMP 'piy-piy-setup-0.1.11-x64.exe'
Invoke-WebRequest 'https://github.com/Estetik007/piy-piy-releases/releases/download/v0.1.11/piy-piy-setup-0.1.11-x64.exe' -OutFile $olderSetup
if ((Get-FileHash $olderSetup).Hash -ne '236cad72e2d559796ae39fd494c03a872f9148ce42fb0e30205abf737ac6e05b') { throw 'Unexpected 0.1.11 installer' }
Install $olderSetup 0
$installedVersion = Join-Path $root 'versions\0.1.11'
$oldVersion = Join-Path $root 'versions\0.1.9'
Copy-Item $installedVersion $oldVersion -Recurse
$save = Join-Path $env:APPDATA 'Godot\app_userdata\piy-piy\update-test.txt'
New-Item (Split-Path $save) -ItemType Directory -Force | Out-Null
Set-Content $save 'keep this save'
$gameHashes = Get-ChildItem $installedVersion -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash

Install $updater 0
$after = Get-ChildItem $installedVersion -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash
if (($gameHashes -join ',') -ne ($after -join ',')) { throw 'Launcher update changed installed game files' }
$versions = Get-ChildItem (Join-Path $root 'versions') -Directory
if ($versions.Count -ne 1 -or $versions[0].Name -ne '0.1.11' -or (Test-Path $oldVersion)) {
    throw "Unexpected remaining game versions: $($versions.Name)"
}
if ((Get-Content $save) -ne 'keep this save') { throw 'Save did not survive the launcher update' }
if ((Get-ItemProperty $key).DisplayVersion -ne '0.1.12') { throw 'The launcher did not update' }
Write-Host 'Existing game assets and save are unchanged. Older game build removed.'
