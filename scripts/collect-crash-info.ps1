# 收集崩溃信息：把排查需要的东西整理成一个文件夹（只读游戏文件，不改动任何东西）
# 用法：双击 收集崩溃信息.bat，或 powershell -ExecutionPolicy Bypass -File 收集崩溃信息.ps1
param([string]$GameFolder, [switch]$NoPrompt)
$ErrorActionPreference = 'Stop'

function Say($m) { Write-Host $m }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Fail($m) { Write-Host $m -ForegroundColor Red; Read-Host '按回车退出' | Out-Null; exit 1 }

# ---------- 找游戏文件夹 ----------
if ($GameFolder -and (Test-Path -LiteralPath (Join-Path $GameFolder 'bin\longshot.exe'))) {
    # 用调用者给的
} elseif ((Test-Path -LiteralPath (Join-Path (Get-Location).Path 'bin\longshot.exe'))) {
    $GameFolder = (Get-Location).Path
} else {
    $GameFolder = $null
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
    if (-not $GameFolder) {
        foreach ($c in @('C:\Games\Longshot\stable\v3.1.1', 'C:\Game\LongShot\stable\v3.1.1')) {
            if (Test-Path -LiteralPath (Join-Path $c 'bin\longshot.exe')) { $GameFolder = $c; break }
        }
    }
    if (-not $GameFolder) { $GameFolder = (Read-Host '请粘贴游戏文件夹路径（里面有 bin\longshot.exe 的那一层）').Trim('"', ' ') }
}
if (-not (Test-Path -LiteralPath (Join-Path $GameFolder 'bin\longshot.exe'))) { Fail "这个文件夹里没有 bin\longshot.exe：$GameFolder" }

# ---------- 输出文件夹 ----------
$desk = [Environment]::GetFolderPath('Desktop')
if (-not $desk -or -not (Test-Path -LiteralPath $desk)) { $desk = $env:TEMP }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = Join-Path $desk ("Longshot崩溃信息-" + $stamp)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$L = New-Object System.Collections.Generic.List[string]
function Add($s) { $L.Add([string]$s); Write-Host $s }

Add '================ Longshot 崩溃信息摘要 ================'
Add ("生成时间      : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Add ("电脑名        : " + $env:COMPUTERNAME)
Add ("游戏文件夹    : " + $GameFolder)
Add ''

# ---------- 系统 ----------
Add '---------------- 系统 ----------------'
try {
    $os = Get-CimInstance Win32_OperatingSystem
    Add ("Windows       : " + $os.Caption + "  " + $os.Version + " (build " + $os.BuildNumber + ")")
    Add ("内存          : " + [math]::Round($os.TotalVisibleMemorySize / 1MB, 1) + " GB")
} catch { Add ("Windows       : " + [Environment]::OSVersion.VersionString) }
try {
    $cs = Get-CimInstance Win32_ComputerSystem
    Add ("型号          : " + $cs.Manufacturer + " " + $cs.Model)
} catch {}
try {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    Add ("CPU           : " + $cpu.Name + " (" + $cpu.NumberOfLogicalProcessors + " 线程)")
} catch {}
try {
    Get-CimInstance Win32_VideoController | ForEach-Object {
        Add ("显卡          : " + $_.Name + "  驱动 " + $_.DriverVersion)
    }
} catch {}
Add ''

# ---------- 版本 ----------
Add '---------------- 游戏版本 ----------------'
$verFile = Join-Path $GameFolder 'longshot_version.txt'
if (Test-Path -LiteralPath $verFile) { (Get-Content -LiteralPath $verFile -Encoding UTF8) | ForEach-Object { Add ("  " + $_) } } else { Add '  (没有 longshot_version.txt)' }
$langFile = Join-Path $GameFolder 'language.txt'
if (Test-Path -LiteralPath $langFile) {
    $langLines = @(Get-Content -LiteralPath $langFile -Encoding UTF8 | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
    if ($langLines.Count -gt 0) { Add ("language.txt  : " + $langLines[0].Trim()) } else { Add 'language.txt  : (空)' }
}
Add ''

# ---------- DLL 状态 ----------
Add '---------------- 汉化补丁状态（bin\longshot_vk.dll） ----------------'
$dll = Join-Path $GameFolder 'bin\longshot_vk.dll'
if (Test-Path -LiteralPath $dll) {
    $fi = Get-Item -LiteralPath $dll
    $hash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    Add ("大小          : " + $fi.Length + " 字节")
    Add ("修改时间      : " + $fi.LastWriteTime)
    Add ("SHA-256       : " + $hash)
    # 是不是本补丁 v1.3.0 的 DLL / 原版 DLL
    $known = @{
        '42DA5316FB8DB6D2F314F6B00CEB51862C53E58FBD6D4CCB5C2A4BDF178F237E' = '本补丁 v1.3.0（已装官方译名）'
        'E2D9F9341162A4D47E8AAC20488BB27693FCF47878C84E15D472E0B8BDE0B0B4' = '原版 v3.1.1（未改动的干净文件）'
    }
    if ($known.ContainsKey($hash)) { Add ("判定          : " + $known[$hash]) } else { Add '判定          : 不在已知清单里（可能是别的版本/被改过/装的是自定义翻译后的文件）' }
    # PE 里有没有 .zhcn 节
    try {
        $b = [System.IO.File]::ReadAllBytes($dll)
        $pe = [BitConverter]::ToUInt32($b, 0x3C)
        $nSec = [BitConverter]::ToUInt16($b, $pe + 6)
        $optSize = [BitConverter]::ToUInt16($b, $pe + 20)
        $secStart = $pe + 24 + $optSize
        $names = @()
        for ($i = 0; $i -lt $nSec; $i++) {
            $o = $secStart + $i * 40
            $names += ([System.Text.Encoding]::ASCII.GetString($b, $o, 8)).TrimEnd([char]0)
        }
        $hasZhcn = '否'
        if ($names -contains '.zhcn') { $hasZhcn = '是（官方译名已写入）' }
        Add ("节区          : " + ($names -join ' '))
        Add ("有 .zhcn 节   : " + $hasZhcn)
    } catch { Add ("节区          : 解析失败 " + $_.Exception.Message) }
} else { Add '  (找不到 bin\longshot_vk.dll)' }
$bak = $dll + '.zhCN-backup'
if (Test-Path -LiteralPath $bak) {
    $bf = Get-Item -LiteralPath $bak
    Add ("原版备份      : " + $bf.Length + " 字节  SHA-256 " + (Get-FileHash -LiteralPath $bak -Algorithm SHA256).Hash)
} else { Add '原版备份      : 没有（从未装过汉化，或已被还原）' }
Add ''

# ---------- 设置 ----------
Add '---------------- 设置（会影响崩溃的项） ----------------'
$keys = @('debug_tools', 'autosave', 'frame_generation', 'frame_generation_by', 'dlss', 'dlss_model', 'frame_rate_cap', 'robust_buffers', 'skip_opening', 'mouse_camera', 'texture_cache', 'upscale')
$iniIndex = 0
foreach ($ini in @((Join-Path $GameFolder 'longshot_options.ini'), (Join-Path $env:APPDATA 'Longshot\longshot_options.ini'))) {
    $iniIndex++
    Add ("[" + $ini + "]")
    if (Test-Path -LiteralPath $ini) {
        $lines = Get-Content -LiteralPath $ini -Encoding UTF8
        foreach ($k in $keys) {
            $hit = $lines | Where-Object { $_ -match ('^\s*' + [regex]::Escape($k) + '\s*=') } | Select-Object -First 1
            if ($hit) { Add ("  " + $hit.Trim()) } else { Add ("  " + $k + " = (未设置)") }
        }
        $all = $lines | Where-Object { $_ -match '^\s*[A-Za-z_][A-Za-z0-9_:]*\s*=\s*\S' }
        Add ("  (全部设置行 " + $all.Count + " 条，见 设置-" + $iniIndex + ".txt)")
        Set-Content -LiteralPath (Join-Path $outDir ("设置-" + $iniIndex + ".txt")) -Encoding UTF8 -Value ($lines -join "`r`n")
    } else { Add '  (文件不存在)' }
}
Add ''

# ---------- 游戏自己的报告行 ----------
Add '---------------- 游戏自己报告的行（日志开头） ----------------'
$logPath = Join-Path $GameFolder 'logs\longshot_log.txt'
if (Test-Path -LiteralPath $logPath) {
    $head = @(Get-Content -LiteralPath $logPath -Encoding UTF8 -TotalCount 220)
    $picked = @($head | Where-Object { $_ -match 'report:|options: the settings file is|boot: .*memory|^\[hos host\] longshot v|language|run_id' })
    if ($picked.Count -eq 0) { Add '  (没有匹配的行)' } else { $picked | ForEach-Object { Add ("  " + $_) } }
} else { Add '  (没有日志)' }
Add ''

# ---------- 崩溃记录 ----------
Add '---------------- 崩溃记录（bug-reports\pending） ----------------'
$pend = Join-Path $GameFolder 'bug-reports\pending'
$records = @()
if (Test-Path -LiteralPath $pend) { $records = @(Get-ChildItem -LiteralPath $pend -Filter '*.txt' -File | Sort-Object LastWriteTime -Descending) }
if ($records.Count -eq 0) {
    Add '  (没有崩溃记录：说明上次退出是干净的 —— 也就是说没有检测到崩溃，或者崩溃时进程被外部结束)'
} else {
    Add ("  共 " + $records.Count + " 条，最新的 " + [math]::Min(6, $records.Count) + " 条如下：")
    foreach ($r in ($records | Select-Object -First 6)) {
        Add ("  ---- " + $r.Name + "  (" + $r.LastWriteTime + ") ----")
        Copy-Item -LiteralPath $r.FullName -Destination $outDir -Force
        (Get-Content -LiteralPath $r.FullName -Encoding UTF8) | ForEach-Object { Add ("  " + $_) }
    }
}
Add ''

# ---------- 日志结尾 ----------
Add '---------------- 最新日志的结尾（logs\longshot_log.txt） ----------------'
$log = Join-Path $GameFolder 'logs\longshot_log.txt'
if (Test-Path -LiteralPath $log) {
    $lf = Get-Item -LiteralPath $log
    Add ("  文件 " + $log)
    Add ("  大小 " + $lf.Length + " 字节，最后修改 " + $lf.LastWriteTime)
    $tail = @(Get-Content -LiteralPath $log -Encoding UTF8 -Tail 120)
    Add '  ---- 最后 120 行 ----'
    $tail | ForEach-Object { Add ("  " + $_) }
    $crash = @(Select-String -LiteralPath $log -Pattern 'CRASH|crash|exception|fatal|FATAL|device lost|abort|assert' | Select-Object -Last 40)
    Add ''
    Add '  ---- 日志里像崩溃/致命错误的行（最后 40 条） ----'
    if ($crash.Count -eq 0) { Add '  (没有)' } else { $crash | ForEach-Object { Add ("  " + $_.LineNumber + ": " + $_.Line) } }
    Copy-Item -LiteralPath $log -Destination $outDir -Force
} else { Add '  (找不到 logs\longshot_log.txt)' }
Add ''

# ---------- 存档目录（只看名字和大小，不复制内容） ----------
Add '---------------- 存档目录（只列清单） ----------------'
$sw = Join-Path $env:APPDATA 'Longshot\save-work'
if (Test-Path -LiteralPath $sw) {
    Get-ChildItem -LiteralPath $sw -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        Add ("  " + $_.Length.ToString().PadLeft(8) + "  " + $_.LastWriteTime + "  " + $_.FullName.Substring($sw.Length))
    }
} else { Add '  (没有 save-work)' }
Add ''
Add '================ 摘要结束 ================'
Add ''
Add '把这个文件夹里的 崩溃摘要.txt（和 bug-reports 的 txt）发给维护者即可。'

$summaryPath = Join-Path $outDir '崩溃摘要.txt'
[System.IO.File]::WriteAllText($summaryPath, ($L -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))

Write-Host ''
Write-Host ('已生成：' + $summaryPath) -ForegroundColor Green
Write-Host ('文件夹：' + $outDir) -ForegroundColor Green
Write-Host ''
Write-Host '下一步：打开这个文件夹，把 崩溃摘要.txt 的内容发过来（文件很小，直接打开复制粘贴即可）。' -ForegroundColor Yellow
Write-Host ''
if (-not $NoPrompt) {
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $outDir + '"') | Out-Null } catch {}
    Read-Host '按回车退出' | Out-Null
}
