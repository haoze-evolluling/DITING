<#
.SYNOPSIS
    谛听 (DITING) 统一版本号管理脚本

.DESCRIPTION
    一键同步修改或查看电脑端 (Windows) 所有组件、安装包、脚本与前端配置的版本号。
    支持自动更新:
      1. Windows/main.go
      2. Windows/cmd/service/main.go
      3. Windows/cmd/gui/main.go
      4. scripts/build-windows.ps1
      5. Windows/build/windows/installer/project.nsi
      6. Windows/build/windows/installer/wails_tools.nsh
      7. Windows/wails.json
      8. Windows/frontend/package.json
      9. Windows/frontend/package.json.md5 (自动重算哈希)
     10. Windows/frontend/src/api/mock.ts

.PARAMETER Version
    目标版本号 (如 1.3.0, 1.4.0, v1.4.0)

.PARAMETER Show
    查看当前各模块所记录的版本号，不执行修改

.PARAMETER DryRun
    预览即将修改的文件与变更内容，不写入磁盘

.PARAMETER Verify
    修改完成后自动运行 Go 测试与前端编译校验

.PARAMETER Commit
    修改并验证后自动按照 Conventional Commits 提交 Git

.EXAMPLE
    .\scripts\set-version.ps1 -Show
    .\scripts\set-version.ps1 1.4.0
    .\scripts\set-version.ps1 1.4.0 -DryRun
    .\scripts\set-version.ps1 1.4.0 -Verify
    .\scripts\set-version.ps1 1.4.0 -Verify -Commit
#>

[CmdletBinding(DefaultParameterSetName = "Update")]
param (
    [Parameter(Position = 0, ParameterSetName = "Update", Mandatory = $false)]
    [string]$Version,

    [Parameter(ParameterSetName = "Show", Mandatory = $true)]
    [switch]$Show,

    [Parameter(ParameterSetName = "Update")]
    [switch]$DryRun,

    [Parameter(ParameterSetName = "Update")]
    [switch]$Verify,

    [Parameter(ParameterSetName = "Update")]
    [switch]$Commit
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# --- 路径解析 ---
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if ($scriptDir) { $scriptDir = (Resolve-Path $scriptDir).Path } else { $scriptDir = $pwd.Path }
$rootDir = (Resolve-Path (Join-Path $scriptDir "..")).Path
$windowsDir = Join-Path $rootDir "Windows"
$frontendDir = Join-Path $windowsDir "frontend"

# --- 目标文件配置 ---
$fileMap = @(
    @{ Name = "Windows 主程序"; Path = (Join-Path $windowsDir "main.go"); Type = "go" },
    @{ Name = "特权服务"; Path = (Join-Path $windowsDir "cmd\service\main.go"); Type = "go" },
    @{ Name = "GUI 调试入口"; Path = (Join-Path $windowsDir "cmd\gui\main.go"); Type = "go" },
    @{ Name = "构建脚本"; Path = (Join-Path $rootDir "scripts\build-windows.ps1"); Type = "ps1" },
    @{ Name = "NSIS 主配置"; Path = (Join-Path $windowsDir "build\windows\installer\project.nsi"); Type = "nsi" },
    @{ Name = "NSIS 工具宏"; Path = (Join-Path $windowsDir "build\windows\installer\wails_tools.nsh"); Type = "nsh" },
    @{ Name = "Wails 配置"; Path = (Join-Path $windowsDir "wails.json"); Type = "wails" },
    @{ Name = "前端 package.json"; Path = (Join-Path $frontendDir "package.json"); Type = "pkg" },
    @{ Name = "前端 Mock 数据"; Path = (Join-Path $frontendDir "src\api\mock.ts"); Type = "mock" }
)

function Read-FileUtf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-FileUtf8([string]$Path, [string]$Content) {
    if ($Path -match '\.(ps1|nsi|nsh)$') {
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
    } else {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    }
}

function Get-CurrentFileVersion($item) {
    if (-not (Test-Path $item.Path)) { return "文件不存在" }
    $content = Read-FileUtf8 $item.Path
    switch ($item.Type) {
        "go" {
            if ($content -match '(?m)^\s*Version\s*=\s*"([^"]+)"') { return $Matches[1] }
        }
        "ps1" {
            if ($content -match '\[string\]\$Version\s*=\s*"([^"]+)"') { return $Matches[1] }
        }
        "nsi" {
            if ($content -match '!define INFO_PRODUCTVERSION\s+"([^"]+)"') { return $Matches[1] }
        }
        "nsh" {
            if ($content -match '!define INFO_PRODUCTVERSION\s+"([^"]+)"') { return $Matches[1] }
        }
        "wails" {
            if ($content -match '"productVersion":\s*"([^"]+)"') { return $Matches[1] }
        }
        "pkg" {
            if ($content -match '"version":\s*"([^"]+)"') { return $Matches[1] }
        }
        "mock" {
            if ($content -match "mockStatus:\s*StatusResponse\s*=\s*\{[\s\S]*?version:\s*'([^']+)'") { return $Matches[1] }
        }
    }
    return "未知"
}

# --- 查看模式 (-Show) ---
if ($Show) {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  谛听 (DITING) 电脑端版本号状态概览" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    foreach ($item in $fileMap) {
        $ver = Get-CurrentFileVersion $item
        $rel = $item.Path.Replace("$rootDir\", "")
        Write-Host ("  {0,-16} : {1,-10} ({2})" -f $item.Name, $ver, $rel) -ForegroundColor White
    }
    Write-Host "============================================================`n" -ForegroundColor Cyan
    exit 0
}

# --- 检查输入版本号与交互式引导 ---
$isInteractive = $false
if (-not $Version -and -not $Show) {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  谛听 (DITING) 电脑端版本号状态概览" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    foreach ($item in $fileMap) {
        $ver = Get-CurrentFileVersion $item
        $rel = $item.Path.Replace("$rootDir\", "")
        Write-Host ("  {0,-16} : {1,-10} ({2})" -f $item.Name, $ver, $rel) -ForegroundColor White
    }
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    $inputVal = Read-Host "请输入目标版本号 (如 1.4.0，直接回车退出)"
    if ([string]::IsNullOrWhiteSpace($inputVal)) {
        Write-Host "已取消操作。`n" -ForegroundColor Yellow
        exit 0
    }
    $Version = $inputVal.Trim()
    $isInteractive = $true
}

$cleanVer = $Version.Trim() -replace '^[vV]', ''
if ($cleanVer -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
    Write-Host "错误: 版本号 '$Version' 格式无效，必须遵循语义化版本规范 (例如 1.3.0, 1.4.0-beta.1)" -ForegroundColor Red
    if ($isInteractive) { Read-Host "按回车键退出..." }
    exit 1
}

$parts = ($cleanVer -replace '-.*$', '').Split('.')
while ($parts.Count -lt 3) { $parts += "0" }
$nsisVer = ($parts[0..2] -join '.')

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  谛听 (DITING) 统一版本号更新工具" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  目标版本号 : $cleanVer" -ForegroundColor White
Write-Host "  NSIS 规范版: $nsisVer" -ForegroundColor White
Write-Host "  预览模式   : $(if ($DryRun) { '是 (不写入文件)' } else { '否 (直接修改)' })" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan

$updatedCount = 0

foreach ($item in $fileMap) {
    if (-not (Test-Path $item.Path)) {
        Write-Host "  [跳过] 文件未找到: $($item.Path)" -ForegroundColor Yellow
        continue
    }

    $raw = Read-FileUtf8 $item.Path
    $newContent = $raw
    $oldVer = Get-CurrentFileVersion $item

    switch ($item.Type) {
        "go" {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($raw, '(?m)^(\s*Version\s*=\s*)".*?"', "`$1`"$cleanVer`"")
        }
        "ps1" {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($raw, 'DITING-release-v[0-9.]+(?:-[a-zA-Z0-9.-]+)?\.exe', "DITING-release-v$cleanVer.exe")
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($newContent, '默认\s+[0-9.]+(?:-[a-zA-Z0-9.-]+)?\s*\(如\s+[0-9.]+(?:-[a-zA-Z0-9.-]+)?\)', "默认 $cleanVer (如 $cleanVer)")
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($newContent, '(\[string\]\$Version\s*=\s*)".*?"', "`$1`"$cleanVer`"")
        }
        "nsi" {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($raw, '!define INFO_PRODUCTVERSION\s+".*?"', "!define INFO_PRODUCTVERSION `"$nsisVer`"")
        }
        "nsh" {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($raw, '(!define INFO_PRODUCTVERSION\s+)".*?"', "`$1`"$nsisVer`"")
        }
        "wails" {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($raw, '("productVersion":\s*)".*?"', "`$1`"$cleanVer`"")
        }
        "pkg" {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($raw, '("version":\s*)".*?"', "`$1`"$cleanVer`"")
        }
        "mock" {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($raw, "(mockStatus:\s*StatusResponse\s*=\s*\{[\s\S]*?version:\s*)'.*?'", "`$1'$cleanVer'")
        }
    }

    $relPath = $item.Path.Replace("$rootDir\", "")
    if ($newContent -ne $raw) {
        if (-not $DryRun) {
            Write-FileUtf8 $item.Path $newContent
        }
        Write-Host ("  ✔ [更新] {0,-16}: {1} -> {2} ({3})" -f $item.Name, $oldVer, $cleanVer, $relPath) -ForegroundColor Green
        $updatedCount++
    } else {
        Write-Host ("  - [保持] {0,-16}: 已是 {1} ({2})" -f $item.Name, $cleanVer, $relPath) -ForegroundColor DarkGray
    }
}

# --- 自动同步 package.json.md5 ---
$pkgPath = Join-Path $frontendDir "package.json"
$md5Path = Join-Path $frontendDir "package.json.md5"
if (Test-Path $pkgPath) {
    if (-not $DryRun) {
        $pkgHash = (Get-FileHash -Path $pkgPath -Algorithm MD5).Hash.ToLower()
        Write-FileUtf8 $md5Path $pkgHash
        Write-Host "  ✔ [哈希] 前端 package.json.md5 已同步: $pkgHash" -ForegroundColor Green
    } else {
        Write-Host "  ✔ [哈希] 前端 package.json.md5 将在更新后自动重新计算" -ForegroundColor DarkGray
    }
}

Write-Host "`n版本号同步完成！共更新 $updatedCount 处文件。`n" -ForegroundColor Cyan

# --- 校验流程 (-Verify) ---
if ($Verify -and -not $DryRun) {
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "  正在运行全自动验证套件..." -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow

    Write-Host "[1/3] 正在执行 Go 单元测试..." -ForegroundColor DarkGray
    Push-Location $windowsDir
    try {
        & go test ./...
        if ($LASTEXITCODE -ne 0) { throw "Go 测试失败" }
        Write-Host "  ✔ Go 单元测试通过" -ForegroundColor Green
    } finally { Pop-Location }

    Write-Host "[2/3] 正在验证前端构建..." -ForegroundColor DarkGray
    Push-Location $frontendDir
    try {
        & npm run build
        if ($LASTEXITCODE -ne 0) { throw "前端构建失败" }
        Write-Host "  ✔ 前端构建校验通过" -ForegroundColor Green
    } finally { Pop-Location }

    Write-Host "[3/3] 正在执行代码规范与大文件扫描..." -ForegroundColor DarkGray
    & python (Join-Path $rootDir "scripts\check_large_files.py")
    if ($LASTEXITCODE -ne 0) { throw "大文件检查未通过" }
    Write-Host "  ✔ 文件规范检查通过" -ForegroundColor Green

    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  全部验证套件 100% 通过！" -ForegroundColor Green
    Write-Host "============================================================`n" -ForegroundColor Green
}

# --- 提交流程 (-Commit) ---
if ($Commit -and -not $DryRun) {
    Write-Host "正在自动提交更改至 Git..." -ForegroundColor Cyan
    git -C $rootDir add Windows/ scripts/build-windows.ps1 scripts/set-version.ps1
    $commitMsg = "build(windows): 统一电脑端软件版本号为 $cleanVer"
    git -C $rootDir commit -m $commitMsg
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✔ Git 提交完成: $commitMsg" -ForegroundColor Green
    } else {
        Write-Host "  ℹ 无新增变更需要提交" -ForegroundColor Yellow
    }
}

if ($isInteractive) {
    Write-Host ""
    Read-Host "按回车键退出..."
}
