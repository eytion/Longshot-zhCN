# 安装游戏内菜单汉化
# 把本补丁的 longshot_vk.dll 复制到 Longshot 游戏文件夹的 bin\ 下（原文件自动备份）
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir

function Say($msg) { Write-Host $msg }
function Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Fail($msg) { Write-Host $msg -ForegroundColor Red; Read-Host '按回车退出' | Out-Null; exit 1 }

# ---------- 找到补丁里的新 DLL ----------
$candidates = @(
    (Join-Path $scriptDir 'game\longshot_vk.dll'),
    (Join-Path $root 'game\longshot_vk.dll'),
    (Join-Path $root 'dist\game\longshot_vk.dll'),
    (Join-Path (Split-Path -Parent $root) 'game\longshot_vk.dll')
)
$newDll = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $newDll) { Fail "找不到 game\longshot_vk.dll。请把本补丁解压后完整运行（不要只复制 .bat 文件）。" }

# ---------- 找到游戏文件夹 ----------
$gameFolder = $null
$buildsJson = Join-Path $env:LOCALAPPDATA 'LongshotLauncher\builds.json'
if (Test-Path -LiteralPath $buildsJson) {
    try {
        $b = Get-Content -LiteralPath $buildsJson -Raw -Encoding UTF8 | ConvertFrom-Json
        $rows = @($b.builds)
        $pick = $rows | Where-Object { $_.default } | Select-Object -First 1
        if (-not $pick) { $pick = $rows | Select-Object -Last 1 }
        if ($pick -and (Test-Path -LiteralPath (Join-Path $pick.folder 'bin\longshot.exe'))) { $gameFolder = $pick.folder }
    } catch {}
}
if (-not $gameFolder -and (Test-Path -LiteralPath 'C:\Games\Longshot\stable\v3.1.1\bin\longshot.exe')) {
    $gameFolder = 'C:\Games\Longshot\stable\v3.1.1'
}
if (-not $gameFolder) {
    Warn '没有自动找到游戏文件夹。'
    $gameFolder = (Read-Host '请粘贴游戏文件夹路径（里面有 bin\longshot.exe 的那一层，例如 C:\Games\Longshot\stable\v3.1.1）').Trim('"', ' ')
}
if (-not (Test-Path -LiteralPath (Join-Path $gameFolder 'bin\longshot.exe'))) {
    Fail "这个文件夹里没有 bin\longshot.exe：$gameFolder"
}

# ---------- 版本提示 ----------
$versionFile = Join-Path $gameFolder 'longshot_version.txt'
if (Test-Path -LiteralPath $versionFile) {
    $ver = (Select-String -LiteralPath $versionFile -Pattern '^version=(.+)$').Matches.Groups[1].Value
    if ($ver -and $ver.Trim() -ne 'v3.1.1') {
        Warn "注意：这个游戏版本是 $ver，本补丁是为 v3.1.1 制作的，可能不适用。"
        if ((Read-Host '仍要继续吗？(y/N)').Trim().ToLower() -ne 'y') { exit 1 }
    }
}

# ---------- 游戏是否在运行 ----------
$running = Get-Process -Name longshot -ErrorAction SilentlyContinue
if ($running) {
    Warn '检测到 Longshot 游戏正在运行，请先退出游戏。'
    if ((Read-Host '已经关闭了吗？现在继续？(y/N)').Trim().ToLower() -ne 'y') { exit 1 }
}

# ---------- 备份并复制 ----------
$target = Join-Path $gameFolder 'bin\longshot_vk.dll'
$backup = $target + '.zhCN-backup'
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $target -Destination $backup -Force
    Say "已备份原文件：$backup"
} else {
    Say "原文件备份已存在：$backup"
}
Copy-Item -LiteralPath $newDll -Destination $target -Force
Say ''
Say '✅ 游戏内菜单汉化安装完成。'
Say "   游戏文件夹：$gameFolder"
Say '   启动游戏后按 Insert 打开菜单即可看到中文。'
Say ''
Read-Host '按回车退出' | Out-Null
