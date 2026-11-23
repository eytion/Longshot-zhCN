# 应用自定义名词翻译：把 自定义翻译.txt 的译名写进 bin\longshot_vk.dll
# 做法：给 DLL 追加一个新的 PE 节（.zhcn）存放译文，再把语言表里对应条目的指针指向它（秒级，无需重新编译）
param([string]$GameFolder, [string]$ListFile)
$ErrorActionPreference = 'Stop'

function Say($m) { Write-Host $m }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Fail($m) { Write-Host $m -ForegroundColor Red; Read-Host '按回车退出' | Out-Null; exit 1 }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
if (-not $ListFile) {
    foreach ($c in @((Join-Path $root '自定义翻译.txt'), (Join-Path $scriptDir '自定义翻译.txt'))) {
        if (Test-Path -LiteralPath $c) { $ListFile = $c; break }
    }
}
if (-not $ListFile -or -not (Test-Path -LiteralPath $ListFile)) { Fail '找不到 自定义翻译.txt（请放在与 .bat 同一个文件夹）' }

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
if (-not $GameFolder -and (Test-Path -LiteralPath 'C:\Games\Longshot\stable\v3.1.1\bin\longshot.exe')) { $GameFolder = 'C:\Games\Longshot\stable\v3.1.1' }
if (-not $GameFolder) { $GameFolder = (Read-Host '请粘贴游戏文件夹路径（包含 bin\longshot.exe 的那层）').Trim('"', ' ') }
$dll = Join-Path $GameFolder 'bin\longshot_vk.dll'
if (-not (Test-Path -LiteralPath $dll)) { Fail "找不到 $dll" }
$running = Get-Process -Name longshot -ErrorAction SilentlyContinue
if ($running) { Warn '游戏正在运行，请先退出游戏。'; if ((Read-Host '继续？(y/N)').Trim().ToLower() -ne 'y') { exit 1 } }

# ---------- 解析 PE ----------
$bytes = [System.IO.File]::ReadAllBytes($dll)
$latin = [System.Text.Encoding]::GetEncoding(28591)
$textBytes = $latin.GetString($bytes)

$pe = [BitConverter]::ToUInt32($bytes, 0x3C)
$numSec = [BitConverter]::ToUInt16($bytes, $pe + 6)
$optSize = [BitConverter]::ToUInt16($bytes, $pe + 20)
$optOff = $pe + 24
$imgBase = [BitConverter]::ToUInt64($bytes, $optOff + 24)
$secAlign = [BitConverter]::ToUInt32($bytes, $optOff + 32)
$fileAlign = [BitConverter]::ToUInt32($bytes, $optOff + 36)
$sizeOfImage = [BitConverter]::ToUInt32($bytes, $optOff + 56)
$secStart = $optOff + $optSize

function Get-Sections {
    $list = @()
    for ($i = 0; $i -lt $numSec; $i++) {
        $o = $secStart + $i * 40
        $list += [pscustomobject]@{
            Index = $i; Off = $o
            Name  = [System.Text.Encoding]::ASCII.GetString($bytes, $o, 8).TrimEnd([char]0)
            VSize = [BitConverter]::ToUInt32($bytes, $o + 8)
            VA    = [BitConverter]::ToUInt32($bytes, $o + 12)
            RSize = [BitConverter]::ToUInt32($bytes, $o + 16)
            RPtr  = [BitConverter]::ToUInt32($bytes, $o + 20)
        }
    }
    return $list
}
$secs = Get-Sections

function RvaToOff([uint32]$rva) {
    foreach ($s in $secs) {
        if ($rva -ge $s.VA -and $rva -lt ($s.VA + $s.VSize)) {
            $d = $rva - $s.VA
            if ($d -lt $s.RSize) { return [int]($s.RPtr + $d) }
        }
    }
    return -1
}
function OffToRva([int]$off) {
    foreach ($s in $secs) {
        if ($off -ge $s.RPtr -and $off -lt ($s.RPtr + $s.RSize)) { return [uint32]($s.VA + ($off - $s.RPtr)) }
    }
    return 0
}
function ReadCString([uint32]$rva) {
    $o = RvaToOff $rva
    if ($o -lt 0) { return $null }
    $e = $o
    while ($e -lt $bytes.Length -and $bytes[$e] -ne 0 -and ($e - $o) -lt 400) { $e++ }
    return [System.Text.Encoding]::UTF8.GetString($bytes, $o, $e - $o)
}

# ---------- 找中文语言表 ----------
function FindTable([string]$code) {
    $rv = @()
    $idx = 0
    while (($idx = $textBytes.IndexOf($code, $idx)) -ge 0) { $r = OffToRva $idx; if ($r -gt 0) { $rv += $r }; $idx++ }
    foreach ($rva in $rv) {
        $tgt = [BitConverter]::GetBytes([uint64]($imgBase + $rva))
        $pat = $latin.GetString($tgt)
        $pos = 0
        while (($pos = $textBytes.IndexOf($pat, $pos)) -ge 0) {
            if (($pos % 8) -eq 0 -and ($pos + 32) -lt $bytes.Length) {
                $entriesPtr = [BitConverter]::ToUInt64($bytes, $pos + 16)
                $count = [BitConverter]::ToUInt32($bytes, $pos + 24)
                if ($entriesPtr -gt $imgBase -and $count -ge 100 -and $count -le 20000) {
                    $eo = RvaToOff ([uint32]($entriesPtr - $imgBase))
                    if ($eo -ge 0 -and ($eo + 16 * $count) -le $bytes.Length) {
                        $en = ReadCString ([uint32]([BitConverter]::ToUInt64($bytes, $eo) - $imgBase))
                        if ($en -and $en.Length -ge 2 -and $en -match '^[\x20-\x7e]+$') {
                            return [pscustomobject]@{ Code = $code; EntriesRva = [uint32]($entriesPtr - $imgBase); Count = [int]$count }
                        }
                    }
                }
            }
            $pos++
        }
    }
    return $null
}
$tables = @()
foreach ($code in @('zh-Hans', 'zh-Hant')) {
    $t = FindTable $code
    if ($t) { $tables += $t; Say "找到 $code 表：$($t.Count) 条" } else { Warn "没有找到 $code 表" }
}
if ($tables.Count -eq 0) { Fail '这个 DLL 里没有中文翻译表——请先安装汉化补丁（安装游戏汉化.bat）。' }

# ---------- 读自定义翻译 ----------
$rawText = [System.IO.File]::ReadAllText($ListFile, [System.Text.Encoding]::UTF8)
if ($rawText.Contains([string][char]0xFFFD)) { $rawText = [System.Text.Encoding]::GetEncoding(936).GetString([System.IO.File]::ReadAllBytes($ListFile)) }
$items = @()
foreach ($line in ($rawText -split "`r?`n")) {
    $l = $line.Trim()
    if ($l -eq '' -or $l.StartsWith('#')) { continue }
    $p = $l.IndexOf('=')
    if ($p -lt 1) { continue }
    $k = $l.Substring(0, $p).Trim(); $v = $l.Substring($p + 1).Trim()
    if ($k -ne '' -and $v -ne '') { $items += [pscustomobject]@{ Key = $k; Value = $v } }
}
Say "自定义条目：$($items.Count) 条"
if ($items.Count -eq 0) { Say '没有要修改的内容。'; Read-Host '按回车退出' | Out-Null; exit 0 }

# ---------- 准备 .zhcn 节 ----------
$limit = 0x4000
$existing = $secs | Where-Object { $_.Name -eq '.zhcn' }
if ($existing) {
    $secVA = $existing.VA; $secRPtr = $existing.RPtr; $secRSize = $existing.RSize
    Say "复用已有 .zhcn 节（$secRSize 字节）"
    [Array]::Clear($bytes, $secRPtr, $secRSize)
} else {
    $hdrEnd = $secStart + 40 * $numSec
    $firstRaw = ($secs | Sort-Object RPtr | Select-Object -First 1).RPtr
    if (($firstRaw - $hdrEnd) -lt 40) { Fail 'DLL 头部空间不足，无法追加新节。' }
    $secRSize = $limit
    $secVA = [uint32](([math]::Ceiling($sizeOfImage / $secAlign)) * $secAlign)
    $fileLen = $bytes.Length
    $secRPtr = [uint32](([math]::Ceiling($fileLen / $fileAlign)) * $fileAlign)
    $newLen = [int]$secRPtr + $secRSize
    $nb = New-Object byte[] $newLen
    [Array]::Copy($bytes, 0, $nb, 0, $bytes.Length)
    $bytes = $nb
    $o = $hdrEnd
    $nameBytes = [System.Text.Encoding]::ASCII.GetBytes('.zhcn')
    [Array]::Copy($nameBytes, 0, $bytes, $o, 5)
    [BitConverter]::GetBytes([uint32]$secRSize).CopyTo($bytes, $o + 8)
    [BitConverter]::GetBytes([uint32]$secVA).CopyTo($bytes, $o + 12)
    [BitConverter]::GetBytes([uint32]$secRSize).CopyTo($bytes, $o + 16)
    [BitConverter]::GetBytes([uint32]$secRPtr).CopyTo($bytes, $o + 20)
    [BitConverter]::GetBytes([uint32]0).CopyTo($bytes, $o + 24)
    [BitConverter]::GetBytes([uint32]0).CopyTo($bytes, $o + 28)
    [BitConverter]::GetBytes([uint16]0).CopyTo($bytes, $o + 32)
    [BitConverter]::GetBytes([uint16]0).CopyTo($bytes, $o + 34)
    [BitConverter]::GetBytes([uint32]0x40000040).CopyTo($bytes, $o + 36)
    [BitConverter]::GetBytes([uint16]($numSec + 1)).CopyTo($bytes, $pe + 6)
    [BitConverter]::GetBytes([uint32]($secVA + $secRSize)).CopyTo($bytes, $optOff + 56)
    $numSec = $numSec + 1
    $secs = Get-Sections
    Say "已追加 .zhcn 节：VA 0x$('{0:X}' -f $secVA)  容量 $secRSize 字节"
}

# ---------- 写入译文 ----------
$cursor = $secRPtr
$end = $secRPtr + $secRSize
$map = @{}
$applied = 0
$unknown = @()
foreach ($it in $items) {
    if (-not $map.ContainsKey($it.Value)) {
        $vb = [System.Text.Encoding]::UTF8.GetBytes($it.Value)
        if (($cursor + $vb.Length + 1) -gt $end) { Fail '自定义文本太多，超出容量（请减少条目或缩短译名）。' }
        [Array]::Copy($vb, 0, $bytes, $cursor, $vb.Length)
        $bytes[$cursor + $vb.Length] = 0
        $map[$it.Value] = [uint64]($imgBase + $secVA + ($cursor - $secRPtr))
        $cursor += $vb.Length + 1
    }
    $newPtr = $map[$it.Value]
    $found = $false
    foreach ($t in $tables) {
        $eo = RvaToOff $t.EntriesRva
        for ($n = 0; $n -lt $t.Count; $n++) {
            $slot = $eo + $n * 16
            $enPtr = [BitConverter]::ToUInt64($bytes, $slot)
            if ($enPtr -gt $imgBase) {
                $en = ReadCString ([uint32]($enPtr - $imgBase))
                if ($en -eq $it.Key) {
                    [BitConverter]::GetBytes([uint64]$newPtr).CopyTo($bytes, $slot + 8)
                    $found = $true
                    break
                }
            }
        }
    }
    if ($found) { $applied++ } else { $unknown += $it.Key }
}

# ---------- 备份 + 写盘 ----------
$backup = $dll + '.zhCN-backup'
if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $dll -Destination $backup -Force; Say "已备份原文件：$backup" }
$tmp = $dll + '.new'
[System.IO.File]::WriteAllBytes($tmp, $bytes)
Move-Item -LiteralPath $tmp -Destination $dll -Force

# ---------- 校验 ----------
$chk = [System.IO.File]::ReadAllBytes($dll)
$bad = 0
foreach ($it in $items) {
    if (-not $map.ContainsKey($it.Value)) { continue }
    $rva = [uint32]($map[$it.Value] - $imgBase)
    $foundOff = -1
    foreach ($s in $secs) { if ($rva -ge $s.VA -and $rva -lt ($s.VA + $s.RSize)) { $foundOff = [int]($s.RPtr + ($rva - $s.VA)) } }
    if ($foundOff -lt 0) { $bad++; continue }
    $e2 = $foundOff; while ($e2 -lt $chk.Length -and $chk[$e2] -ne 0) { $e2++ }
    $s2 = [System.Text.Encoding]::UTF8.GetString($chk, $foundOff, $e2 - $foundOff)
    if ($s2 -ne $it.Value) { $bad++ }
}

Say ''
Say "✅ 完成：修改了 $applied 条译名（DLL 新增 .zhcn 节存放译文）。"
if ($bad -gt 0) { Warn "校验有 $bad 条不一致，请把 DLL 从 .zhCN-backup 还原后重试。" }
if ($unknown.Count -gt 0) {
    Warn "以下 $($unknown.Count) 条在 DLL 里找不到对应英文名（英文那侧是不是改了？）："
    $unknown | Select-Object -First 20 | ForEach-Object { Warn "   $_" }
}
Say '   游戏里重开一次 Insert 菜单即可看到；把译名改回原样再运行即可恢复。'
Say ''
Read-Host '按回车退出' | Out-Null
