# Builds Freely NGO for Windows and zips the result.
# Needs: Flutter (Windows desktop enabled), Visual Studio 2022 with "Desktop development with C++",
#        and Windows Developer Mode (Settings > System > For developers) so that plugins can be linked.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

flutter config --enable-windows-desktop | Out-Null
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build windows --release

$out = Join-Path $PSScriptRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $out 'FreelyNGO.exe'))) { throw "FreelyNGO.exe was not produced in $out" }
$zip = Join-Path $PSScriptRoot 'build\Freely-NGO-Windows.zip'
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip
Write-Host "Done. Run: $out\FreelyNGO.exe"
Write-Host "Zip to share: $zip  (unzip anywhere and run FreelyNGO.exe)"
