param(
    [switch]$Debug
)

$ErrorActionPreference = 'Stop'
$flutterProject = Join-Path $PSScriptRoot '..\DITING-Flutter'
$outputDirectory = Join-Path $PSScriptRoot 'flutter_frontend\dist'
$mode = 'release'
if ($Debug.IsPresent) { $mode = 'debug' }

Push-Location $flutterProject
try {
    Write-Host ">>> 构建谛听 Flutter 桌面 UI ($mode)"
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get 失败' }

    flutter build web "--$mode" `
        --target lib/desktop/main.dart `
        --output $outputDirectory `
        --base-href / `
        --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw 'Flutter 桌面 UI 构建失败' }
}
finally {
    Pop-Location
}
