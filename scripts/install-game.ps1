# 安装游戏内菜单汉化
# 做法：不替换整个 DLL，而是把译名写进**你这台电脑上原本那份** bin\longshot_vk.dll
#       （只追加一个 .zhcn 节存放译文 + 改语言表里的指针，代码段一个字节都不动）
#       这样不会出现“补丁里的 DLL 和你的游戏构建不匹配”导致的崩溃。
param([string]$GameFolder, [switch]$Quiet)
$ErrorActionPreference = 'Stop'

function Say($m) { if (-not $Quiet) { Write-Host $m } }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Fail($m) {
    Write-Host $m -ForegroundColor Red
    if ($Quiet) { throw $m }
    Read-Host '按回车退出' | Out-Null; exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir

# ---------- 找游戏文件夹 ----------
if (-not $GameFolder) {
    $buildsJson = Join-Path $env:LOCALAPPDATA 'LongshotLauncher\builds.json'
    if (Test-Path -LiteralPath $buildsJson) {
        try {
            $b = Get-Content -LiteralPath $buildsJson -Raw -Encoding UTF8 | ConvertFrom-Json
            $rows = @($b.builds)
            $pick = $rows | Where-Object { $_.default } | Select-Object -First 1
            if (-not $pick) { $pick = $rows | Select-Object -Last 1 }
            if ($pick -and (Test-Path -LiteralPath (Join-Path $pick.folder 'bin\longshot.exe'))) { $GameFolder = $pick.folder }
        } catch {}
    }
}
if (-not $GameFolder) {
    foreach ($c in @('C:\Games\Longshot\stable\v3.1.1', 'C:\Game\LongShot\stable\v3.1.1')) {
        if (Test-Path -LiteralPath (Join-Path $c 'bin\longshot.exe')) { $GameFolder = $c; break }
    }
}
if (-not $GameFolder) {
    Warn '没有自动找到游戏文件夹。'
    $GameFolder = (Read-Host '请粘贴游戏文件夹路径（里面有 bin\longshot.exe 的那一层，例如 C:\Games\Longshot\stable\v3.1.1）').Trim('"', ' ')
}
$exe = Join-Path $GameFolder 'bin\longshot.exe'
if (-not (Test-Path -LiteralPath $exe)) { Fail "这个文件夹里没有 bin\longshot.exe：$GameFolder" }

# ---------- 版本提示 ----------
$versionFile = Join-Path $GameFolder 'longshot_version.txt'
if (Test-Path -LiteralPath $versionFile) {
    $ver = (Select-String -LiteralPath $versionFile -Pattern '^version=(.+)$').Matches.Groups[1].Value
    if ($ver -and $ver.Trim() -ne 'v3.1.1') {
        Warn "注意：这个游戏版本是 $ver，本补丁是为 v3.1.1 制作的，可能不适用。"
        if (-not $Quiet -and (Read-Host '仍要继续吗？(y/N)').Trim().ToLower() -ne 'y') { exit 1 }
    }
}

# ---------- 游戏是否在运行 ----------
if (Get-Process -Name longshot -ErrorAction SilentlyContinue) {
    Warn '检测到 Longshot 游戏正在运行，请先退出游戏。'
    if (-not $Quiet -and (Read-Host '已经关闭了吗？现在继续？(y/N)').Trim().ToLower() -ne 'y') { exit 1 }
}

# ---------- 先把可能装过的“别人打包的 DLL”换回原版 ----------
$dll = Join-Path $GameFolder 'bin\longshot_vk.dll'
$backup = $dll + '.zhCN-backup'
if (-not (Test-Path -LiteralPath $dll)) { Fail "找不到 $dll" }

function Test-HasZhcn([string]$path) {
    try {
        $b = [System.IO.File]::ReadAllBytes($path)
        $pe = [BitConverter]::ToUInt32($b, 0x3C)
        $n = [BitConverter]::ToUInt16($b, $pe + 6)
        $o = [BitConverter]::ToUInt16($b, $pe + 20)
        $s = $pe + 24 + $o
        for ($i = 0; $i -lt $n; $i++) {
            $nm = ([System.Text.Encoding]::ASCII.GetString($b, $s + $i * 40, 8)).TrimEnd([char]0)
            if ($nm -eq '.zhcn') { return $true }
        }
    } catch {}
    return $false
}

if (Test-Path -LiteralPath $backup) {
    $hCur = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    $hBak = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
    if ($hCur -ne $hBak) {
        Copy-Item -LiteralPath $backup -Destination $dll -Force
        Say '已先把 DLL 还原成补丁前的原版（避免旧补丁残留）。'
    } else {
        Say 'DLL 已经是原版（和备份一致）。'
    }
} elseif (Test-HasZhcn $dll) {
    Fail @'
这个 DLL 已经带着别的汉化补丁，而且没有原版备份，无法安全地在它上面继续装。
请先用启动器的「重新构建」把游戏恢复成官方文件，然后再运行本补丁。
'@
}

# ---------- 把译名写进这个 DLL ----------
$list = $null
foreach ($c in @((Join-Path $root '自定义翻译.txt'), (Join-Path $scriptDir '自定义翻译.txt'), (Join-Path $root '官方译名.txt'))) {
    if (Test-Path -LiteralPath $c) { $list = $c; break }
}
if (-not $list) { Fail '找不到 自定义翻译.txt（请把整个补丁文件夹一起解压，不要只复制 .bat）' }

$patch = Join-Path $scriptDir 'apply-custom-names.ps1'
if (-not (Test-Path -LiteralPath $patch)) { Fail "找不到 $patch（补丁文件不完整，请重新解压）" }

& $patch -GameFolder $GameFolder -ListFile $list -Quiet

# ---------- 结果 ----------
$fi = Get-Item -LiteralPath $dll
$hash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
Say ''
Say '✅ 游戏内菜单汉化安装完成。'
Say ("   游戏文件夹： " + $GameFolder)
Say ("   DLL： " + $fi.Length + " 字节  SHA-256 " + $hash.Substring(0, 16) + "...")
Say '   启动游戏后按 Insert 打开菜单即可看到中文；想改译名请编辑 自定义翻译.txt 再运行「应用自定义翻译.bat」。'
Say ''
if (-not $Quiet) { Read-Host '按回车退出' | Out-Null }
