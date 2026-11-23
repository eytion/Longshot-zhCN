# 安装启动器汉化
# 把本补丁的 LongshotLauncher.exe 复制到启动器安装目录（原文件自动备份）
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir

function Say($msg) { Write-Host $msg }
function Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Fail($msg) { Write-Host $msg -ForegroundColor Red; Read-Host '按回车退出' | Out-Null; exit 1 }

# ---------- 找到补丁里的新启动器 ----------
$candidates = @(
    (Join-Path $scriptDir 'launcher\LongshotLauncher.exe'),
    (Join-Path $root 'launcher\LongshotLauncher.exe'),
    (Join-Path $root 'dist\launcher\LongshotLauncher.exe'),
    (Join-Path (Split-Path -Parent $root) 'launcher\LongshotLauncher.exe')
)
$newExe = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $newExe) { Fail "找不到 launcher\LongshotLauncher.exe。请把本补丁解压后完整运行。" }

# ---------- 找到已安装的启动器 ----------
$target = $null
$search = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\LongshotLauncher\LongshotLauncher.exe'),
    (Join-Path $env:LOCALAPPDATA 'LongshotLauncher\LongshotLauncher.exe'),
    (Join-Path $env:PROGRAMFILES 'LongshotLauncher\LongshotLauncher.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'LongshotLauncher\LongshotLauncher.exe')
)
foreach ($p in $search) {
    if ($p -and (Test-Path -LiteralPath $p)) { $target = $p; break }
}
if (-not $target) {
    # 从开始菜单/桌面快捷方式里找
    foreach ($shortcutDir in @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:USERPROFILE 'Desktop'))) {
        if (-not (Test-Path -LiteralPath $shortcutDir)) { continue }
        $lnk = Get-ChildItem -LiteralPath $shortcutDir -Filter '*Longshot*' -ErrorAction SilentlyContinue |
               Where-Object { $_.Extension -in '.lnk', '.url' } | Select-Object -First 1
        if ($lnk) {
            try {
                $sh = New-Object -ComObject WScript.Shell
                $t = $sh.CreateShortcut($lnk.FullName).TargetPath
                if ($t -and (Test-Path -LiteralPath $t) -and (Split-Path -Leaf $t) -eq 'LongshotLauncher.exe') { $target = $t; break }
            } catch {}
        }
    }
}
if (-not $target) {
    Warn '没有找到已安装的 Longshot Launcher。'
    $target = (Read-Host '请粘贴 LongshotLauncher.exe 的完整路径').Trim('"', ' ')
}
if (-not (Test-Path -LiteralPath $target)) { Fail "文件不存在：$target" }

# ---------- 版本提示 ----------
$oldVer = (Get-Item -LiteralPath $target).VersionInfo.ProductVersion
$newVer = (Get-Item -LiteralPath $newExe).VersionInfo.ProductVersion
if ($oldVer -and $newVer -and $oldVer -ne $newVer) {
    Warn "注意：已安装的启动器版本是 $oldVer，本补丁的启动器是 $newVer（为 v1.2.0 制作）。"
    Warn '装上去相当于把启动器换成本补丁的版本；官方若已更新，请先不要使用本项。'
    if ((Read-Host '仍要继续吗？(y/N)').Trim().ToLower() -ne 'y') { exit 1 }
}

# ---------- 启动器是否在运行 ----------
$running = Get-Process -Name LongshotLauncher -ErrorAction SilentlyContinue
if ($running) {
    Warn 'Longshot Launcher 正在运行，请先完全关闭它（右键任务栏图标 → 退出）。'
    if ((Read-Host '已经关闭了吗？现在继续？(y/N)').Trim().ToLower() -ne 'y') { exit 1 }
}

# ---------- 备份并复制 ----------
$backup = $target + '.zhCN-backup'
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $target -Destination $backup -Force
    Say "已备份原文件：$backup"
} else {
    Say "原文件备份已存在：$backup"
}
Copy-Item -LiteralPath $newExe -Destination $target -Force
Say ''
Say '✅ 启动器汉化安装完成。'
Say "   启动器：$target"
Say '   重新打开启动器，界面即为中文。'
Say ''
Read-Host '按回车退出' | Out-Null
