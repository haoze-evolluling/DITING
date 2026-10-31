#Requires -Version 7.3
# Rebuild the tunnel AARs from the Go sources in this directory (gomobile bind).
# PowerShell 7.3+ (pwsh) only: native argument passing is unambiguous there.
#
# Three artifacts, selected automatically by android/app/build.gradle.kts:
#   arm64 (default, phones) -> android/app/libs/tunnel-arm64.aar  committed
#   x64   (x86_64 emulator) -> android/app/libs/tunnel-x64.aar    on demand
#   all   (dual ABI)        -> android/app/libs/tunnel-all.aar    on demand,
#                              bundled by debug APKs (phones + emulator)
#
# Usage:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File build_aar.ps1 [-Arch arm64|x64|all]
# Details and troubleshooting: docs/development/aar-build-notes.md
param(
    [ValidateSet('arm64', 'x64', 'all')]
    [string]$Arch = 'arm64'
)

$ErrorActionPreference = 'Stop'
$moduleDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $moduleDir

# --- Locate the Android SDK and a JDK (javac compiles gomobile's Java wrapper) ---
if (-not $env:ANDROID_HOME -or -not (Test-Path $env:ANDROID_HOME)) {
    foreach ($candidate in @("$env:LOCALAPPDATA\Android\Sdk", 'D:\Androidsdk')) {
        if (Test-Path $candidate) { $env:ANDROID_HOME = $candidate; break }
    }
}
if (-not $env:ANDROID_HOME -or -not (Test-Path $env:ANDROID_HOME)) {
    throw 'ANDROID_HOME is not set and no Android SDK was found in the usual locations.'
}
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME

if (-not $env:JAVA_HOME -or -not (Test-Path "$env:JAVA_HOME\bin\javac.exe")) {
    foreach ($candidate in @(
        'C:\Program Files\Android\Android Studio\jbr',
        "$env:LOCALAPPDATA\Programs\Android Studio\jbr"
    )) {
        if (Test-Path "$candidate\bin\javac.exe") { $env:JAVA_HOME = $candidate; break }
    }
}
if (-not $env:JAVA_HOME -or -not (Test-Path "$env:JAVA_HOME\bin\javac.exe")) {
    throw 'No JDK with javac found (tried JAVA_HOME and the Android Studio JBR). Set JAVA_HOME.'
}
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

if (-not (Get-Command gomobile -ErrorAction SilentlyContinue)) {
    throw 'gomobile not installed; run: go install golang.org/x/mobile/cmd/gomobile@latest'
}

# gomobile's temp project cannot read this repo's VCS status, so stamping must be off.
$env:GOFLAGS = '-buildvcs=false'

function Invoke-GomobileBind {
    param([string]$Target, [string]$Output)
    Write-Host "[INFO] ANDROID_HOME = $env:ANDROID_HOME"
    Write-Host "[INFO] JAVA_HOME    = $env:JAVA_HOME"
    Write-Host "[INFO] target       = $Target"
    Write-Host "[INFO] output       = $Output"

    & gomobile bind "-target=$Target" -androidapi 28 -trimpath '-ldflags=-s -w' -o $Output .
    if ($LASTEXITCODE -ne 0) { throw "gomobile bind failed (target=$Target, exit $LASTEXITCODE)." }
    Write-Host "[DONE] $Output"
}

$libsDir = Join-Path $moduleDir '..\android\app\libs'
switch ($Arch) {
    # Comma-separated targets put both ABIs into one AAR.
    'arm64' { Invoke-GomobileBind -Target 'android/arm64' -Output (Join-Path $libsDir 'tunnel-arm64.aar') }
    'x64'   { Invoke-GomobileBind -Target 'android/amd64' -Output (Join-Path $libsDir 'tunnel-x64.aar') }
    'all'   { Invoke-GomobileBind -Target 'android/arm64,android/amd64' -Output (Join-Path $libsDir 'tunnel-all.aar') }
}
