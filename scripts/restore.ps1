# 还原原版文件（撤销本补丁）
$ErrorActionPreference = 'Stop'
function Say($msg) { Write-Host $msg }
function Warn($msg) { Write-Host $msg -ForegroundColor Yellow }

$restored = 0

# ---------- 游戏 DLL ----------
$buildsJson = Join-Path $env:LOCALAPPDATA 'LongshotLauncher\builds.json'
$gameFolders = @()
if (Test-Path -LiteralPath $buildsJson) {
    try {
        $b = Get-Content -LiteralPath $buildsJson -Raw -Encoding UTF8 | ConvertFrom-Json
        $gameFolders = @($b.builds | ForEach-Object { $_.folder })
    } catch {}
}
if (Test-Path -LiteralPath 'C:\Games\Longshot\stable\v3.1.1\bin\longshot.exe') { $gameFolders += 'C:\Games\Longshot\stable\v3.1.1' }
if (-not $gameFolders -or $gameFolders.Count -eq 0) {
    $gameFolders = @((Read-Host '请粘贴游戏文件夹路径（可留空跳过）').Trim('"', ' ')) | Where-Object { $_ }
}
$running = Get-Process -Name longshot -ErrorAction SilentlyContinue
if ($running) { Warn '游戏正在运行，请先退出后再还原。' }

foreach ($folder in ($gameFolders | Select-Object -Unique)) {
    if (-not $folder) { continue }
    $target = Join-Path $folder 'bin\longshot_vk.dll'
    $backup = $target + '.zhCN-backup'
    if (Test-Path -LiteralPath $backup) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Say "已还原游戏文件：$target"
        $restored++
    }
}

# ---------- 启动器 ----------
$launcherDirs = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\LongshotLauncher'),
    (Join-Path $env:LOCALAPPDATA 'LongshotLauncher'),
    (Join-Path $env:PROGRAMFILES 'LongshotLauncher'),
    (Join-Path ${env:ProgramFiles(x86)} 'LongshotLauncher')
)
foreach ($dir in $launcherDirs) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
    $target = Join-Path $dir 'LongshotLauncher.exe'
    $backup = $target + '.zhCN-backup'
    if (Test-Path -LiteralPath $backup) {
        $p = Get-Process -Name LongshotLauncher -ErrorAction SilentlyContinue
        if ($p) { Warn '启动器正在运行，请先关闭后再还原启动器。'; continue }
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Say "已还原启动器：$target"
        $restored++
    }
}

if ($restored -eq 0) { Say '没有找到本补丁的备份文件，无需还原。' }
else { Say ''; Say "✅ 已还原 $restored 个文件。"; Say '   如果是通过重新构建游戏/重新安装启动器覆盖的，原版本来就已经回来了。' }
Say ''
Read-Host '按回车退出' | Out-Null
