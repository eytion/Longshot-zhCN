# 把译名写进游戏自己的 bin\longshot_vk.dll
# 原理：在里面追加/复用一个 .zhcn 节存放中文，改翻译表条目的 text 指针（中文长度不限）；
#       翻译表里没有的英文名，再退回“就地改写 DLL 里硬编码的字符串 / 改指向它的指针”。
# 代码段一个字节都不动，所以不会和别的构建不匹配。
param([string]$GameFolder, [string]$ListFile, [switch]$Quiet)
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
if (-not $GameFolder) {
    foreach ($c in @('C:\Games\Longshot\stable\v3.1.1', 'C:\Game\LongShot\stable\v3.1.1')) {
        if (Test-Path -LiteralPath (Join-Path $c 'bin\longshot.exe')) { $GameFolder = $c; break }
    }
}
if (-not $GameFolder) { $GameFolder = (Read-Host '请粘贴游戏文件夹路径（包含 bin\longshot.exe 的那层）').Trim('"', ' ') }
$dll = Join-Path $GameFolder 'bin\longshot_vk.dll'
if (-not (Test-Path -LiteralPath $dll)) { Fail "找不到 $dll" }
if (Get-Process -Name longshot -ErrorAction SilentlyContinue) {
    Warn '游戏正在运行，请先退出游戏。'
    if (-not $Quiet -and (Read-Host '继续？(y/N)').Trim().ToLower() -ne 'y') { exit 1 }
}

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
    while ($e -lt $bytes.Length -and $bytes[$e] -ne 0 -and ($e - $o) -lt 500) { $e++ }
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
                if ($entriesPtr -gt $imgBase -and $count -ge 50 -and $count -le 20000) {
                    $eo = RvaToOff ([uint32]($entriesPtr - $imgBase))
                    if ($eo -ge 0 -and ($eo + 16 * $count) -le $bytes.Length) {
                        $en = ReadCString ([uint32]([BitConverter]::ToUInt64($bytes, $eo) - $imgBase))
                        if ($en -and $en.Length -ge 2 -and $en -match '^[\x20-\x7e]+$') {
                            return [pscustomobject]@{ Code = $code; EntriesOff = [int]$eo; Count = [int]$count }
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
if ($tables.Count -eq 0) { Fail '这个 DLL 里没有中文语言表——它可能不是 Longshot v3.1.1 的 bin\longshot_vk.dll（或者版本不对）。' }

# ---------- 读译名表 ----------
$rawText = [System.IO.File]::ReadAllText($ListFile, [System.Text.Encoding]::UTF8)
if ($rawText.Contains([string][char]0xFFFD)) { $rawText = [System.Text.Encoding]::GetEncoding(936).GetString([System.IO.File]::ReadAllBytes($ListFile)) }
$items = @()
$seen = @{}
foreach ($line in ($rawText -split "`r?`n")) {
    $l = $line.Trim()
    if ($l -eq '' -or $l.StartsWith('#')) { continue }
    $p = $l.IndexOf('=')
    if ($p -lt 1) { continue }
    $k = $l.Substring(0, $p).Trim(); $v = $l.Substring($p + 1).Trim()
    if ($k -eq '' -or $v -eq '') { continue }
    if ($seen.ContainsKey($k)) { continue }
    $seen[$k] = 1
    $items += [pscustomobject]@{ Key = $k; Value = $v; Bytes = $null }
}
foreach ($it in $items) { $it.Bytes = [System.Text.Encoding]::UTF8.GetBytes($it.Value) }
Say "译名条目：$($items.Count) 条"

# ---------- 建索引：英文 → 条目槽位 ----------
$index = @{}
foreach ($t in $tables) {
    for ($n = 0; $n -lt $t.Count; $n++) {
        $slot = $t.EntriesOff + $n * 16
        $enPtr = [BitConverter]::ToUInt64($bytes, $slot)
        if ($enPtr -le $imgBase) { continue }
        $en = ReadCString ([uint32]($enPtr - $imgBase))
        if (-not $en) { continue }
        $mapKey = $t.Code + '|' + $en
        if (-not $index.ContainsKey($mapKey)) { $index[$mapKey] = New-Object System.Collections.ArrayList }
        [void]$index[$mapKey].Add($slot)
    }
}
Say "翻译表里可匹配的英文条目：$($index.Count) 个键"

# ---------- 算出 .zhcn 需要多大 ----------
$uniqValues = @{}
foreach ($it in $items) { if (-not $uniqValues.ContainsKey($it.Value)) { $uniqValues[$it.Value] = $it.Bytes.Length + 1 } }
$needed = 0
foreach ($v in $uniqValues.Values) { $needed += $v }
$want = [int]([math]::Ceiling(($needed + 64) / 4096.0) * 4096)
if ($want -lt 4096) { $want = 4096 }

# ---------- 准备 .zhcn 节 ----------
$existing = $secs | Where-Object { $_.Name -eq '.zhcn' }
if ($existing) {
    $secVA = $existing.VA
    $secRPtr = $existing.RPtr
    $secRSize = $existing.RSize
    if ($want -gt $secRSize) {
        if (($secRPtr + $secRSize) -ne $bytes.Length) { Fail '.zhcn 节后面还有别的数据，无法扩容；请先用 还原原版.bat 还原再重试。' }
        $newSize = [int]([math]::Ceiling($want / 4096.0) * 4096)
        $nb = New-Object byte[] ($bytes.Length + ($newSize - $secRSize))
        [Array]::Copy($bytes, 0, $nb, 0, $bytes.Length)
        $bytes = $nb
        $secRSize = $newSize
        [BitConverter]::GetBytes([uint32]$secRSize).CopyTo($bytes, $existing.Off + 8)
        [BitConverter]::GetBytes([uint32]$secRSize).CopyTo($bytes, $existing.Off + 16)
        [BitConverter]::GetBytes([uint32]($secVA + $secRSize)).CopyTo($bytes, $optOff + 56)
        $secs = Get-Sections
        Say "把 .zhcn 节扩到 $secRSize 字节（译名变多了）"
    }
    [Array]::Clear($bytes, $secRPtr, $secRSize)
    # 上次补丁留下的、这次清单里没有的指针：改回英文原文，避免变成空白
    $lo = [uint64]($imgBase + $secVA)
    $hi = [uint64]($imgBase + $secVA + $secRSize)
    foreach ($t in $tables) {
        for ($n = 0; $n -lt $t.Count; $n++) {
            $slot = $t.EntriesOff + $n * 16
            $zhPtr = [BitConverter]::ToUInt64($bytes, $slot + 8)
            if ($zhPtr -ge $lo -and $zhPtr -lt $hi) {
                $enPtr = [BitConverter]::ToUInt64($bytes, $slot)
                if ($enPtr -gt $imgBase) { [BitConverter]::GetBytes([uint64]$enPtr).CopyTo($bytes, $slot + 8) }
            }
        }
    }
} else {
    $hdrEnd = $secStart + 40 * $numSec
    $firstRaw = ($secs | Sort-Object RPtr | Select-Object -First 1).RPtr
    if (($firstRaw - $hdrEnd) -lt 40) { Fail 'DLL 头部空间不足，无法追加新节。' }
    $secRSize = $want
    $secVA = [uint32](([math]::Ceiling($sizeOfImage / $secAlign)) * $secAlign)
    $secRPtr = [uint32](([math]::Ceiling($bytes.Length / $fileAlign)) * $fileAlign)
    $newLen = [int]$secRPtr + $secRSize
    $nb = New-Object byte[] $newLen
    [Array]::Copy($bytes, 0, $nb, 0, $bytes.Length)
    $bytes = $nb
    $o = $hdrEnd
    [Array]::Copy([System.Text.Encoding]::ASCII.GetBytes('.zhcn'), 0, $bytes, $o, 5)
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

# ---------- 写译文 + 改指针 ----------
$cursor = $secRPtr
$end = $secRPtr + $secRSize
$ptrMap = @{}
$appliedItems = 0
$appliedSlots = 0
$unknown = @()
foreach ($it in $items) {
    $slots = @()
    foreach ($t in $tables) {
        $k = $t.Code + '|' + $it.Key
        if ($index.ContainsKey($k)) { $slots += $index[$k] }
    }
    if ($slots.Count -eq 0) { $unknown += $it; continue }
    if (-not $ptrMap.ContainsKey($it.Value)) {
        if (($cursor + $it.Bytes.Length + 1) -gt $end) { Fail '译名总长度超出 .zhcn 容量（请减少条目或缩短译名）。' }
        [Array]::Copy($it.Bytes, 0, $bytes, $cursor, $it.Bytes.Length)
        $bytes[$cursor + $it.Bytes.Length] = 0
        $ptrMap[$it.Value] = [uint64]($imgBase + $secVA + ($cursor - $secRPtr))
        $cursor += $it.Bytes.Length + 1
    }
    $newPtr = $ptrMap[$it.Value]
    foreach ($slot in $slots) { [BitConverter]::GetBytes([uint64]$newPtr).CopyTo($bytes, $slot + 8) }
    $appliedItems++
    $appliedSlots += $slots.Count
}

# ---------- 不在翻译表里的名字：就地改写 / 改指针 ----------
$literalDone = @()
$ptrDone = @()
$literalTooLong = @()
if ($unknown.Count -gt 0) {
    $latinAll = $latin.GetString($bytes)
    $tableRanges = @()
    foreach ($t in $tables) { $tableRanges += , @($t.EntriesOff, ($t.EntriesOff + 16 * $t.Count)) }

    $relocSet = @{}
    if ([BitConverter]::ToUInt16($bytes, $optOff) -eq 0x20B) {
        $dirBase = $optOff + 112
        $relocRva = [BitConverter]::ToUInt32($bytes, $dirBase + 5 * 8)
        $relocSize = [BitConverter]::ToUInt32($bytes, $dirBase + 5 * 8 + 4)
        $ro = RvaToOff $relocRva
        if ($ro -ge 0 -and $relocSize -gt 0) {
            $pp = $ro
            $endRel = $ro + $relocSize
            while ($pp -lt $endRel -and ($pp + 8) -le $bytes.Length) {
                $page = [BitConverter]::ToUInt32($bytes, $pp)
                $blk = [BitConverter]::ToUInt32($bytes, $pp + 4)
                if ($blk -le 0) { break }
                $qq = $pp + 8
                while ($qq -lt ($pp + $blk) -and ($qq + 2) -le $bytes.Length) {
                    $e = [BitConverter]::ToUInt16($bytes, $qq)
                    if (($e -shr 12) -eq 10) { $relocSet[($page + ($e -band 0xFFF))] = 1 }
                    $qq += 2
                }
                $pp += $blk
            }
        }
    }

    foreach ($it in $unknown) {
        $key = $it.Key
        if ($key.Length -gt 48) { $literalTooLong += ("{0}（太长，且不在翻译表里）" -f $key); continue }
        $vb = $it.Bytes
        $needleLen = $key.Length
        $pos = 0
        $shortHits = 0
        $longHits = 0
        $candidates = @()
        while (($pos = $latinAll.IndexOf($key, $pos, [System.StringComparison]::Ordinal)) -ge 0) {
            $endp = $pos + $needleLen
            $inTable = $false
            foreach ($r in $tableRanges) { if ($pos -ge $r[0] -and $pos -lt $r[1]) { $inTable = $true; break } }
            if (-not $inTable -and $endp -lt $bytes.Length -and $bytes[$endp] -eq 0 -and ($pos -eq 0 -or $bytes[$pos - 1] -eq 0)) {
                if ($vb.Length -le $needleLen) {
                    [Array]::Copy($vb, 0, $bytes, $pos, $vb.Length)
                    $bytes[$pos + $vb.Length] = 0
                    $shortHits++
                } else {
                    $r = OffToRva $pos
                    if ($r -gt 0) { $candidates += [uint64]($imgBase + $r) }
                }
            }
            $pos++
        }
        if ($shortHits -gt 0) { $literalDone += ("{0} → {1}（就地改 {2} 处）" -f $key, $it.Value, $shortHits); continue }
        if ($candidates.Count -gt 0 -and $ptrMap.ContainsKey($it.Value)) {
            $newPtr2 = $ptrMap[$it.Value]
            foreach ($cand in $candidates) {
                $pat = $latin.GetString([BitConverter]::GetBytes($cand))
                $j = 0
                while (($j = $latinAll.IndexOf($pat, $j, [System.StringComparison]::Ordinal)) -ge 0) {
                    if (($j % 8) -eq 0) {
                        $slotRva = OffToRva $j
                        if ($slotRva -gt 0 -and $relocSet.ContainsKey($slotRva)) {
                            [BitConverter]::GetBytes([uint64]$newPtr2).CopyTo($bytes, $j)
                            $longHits++
                        }
                    }
                    $j++
                }
            }
        }
        if ($longHits -gt 0) { $ptrDone += ("{0} → {1}（改指针 {2} 处）" -f $key, $it.Value, $longHits) }
        elseif ($candidates.Count -eq 0) { $literalTooLong += ("{0} = {1}（这份 DLL 里找不到这个英文名）" -f $key, $it.Value) }
        else { $literalTooLong += ("{0} = {1}（原名 {2} 字节，中文 {3} 字节，且没有可改的指针）" -f $key, $it.Value, $needleLen, $vb.Length) }
    }
}

# ---------- 备份 + 写盘 ----------
$backup = $dll + '.zhCN-backup'
if (-not (Test-Path -LiteralPath $backup)) {
    if ($existing) {
        Warn '这个 DLL 已经带着补丁、却没有原版备份：现在无法自动生成原版备份。'
        Warn '建议：先用启动器的「重新构建」把游戏恢复成官方文件，再重新运行安装。'
    } else {
        Copy-Item -LiteralPath $dll -Destination $backup -Force
        Say "已备份原文件：$backup"
    }
}
$tmp = $dll + '.new'
[System.IO.File]::WriteAllBytes($tmp, $bytes)
Move-Item -LiteralPath $tmp -Destination $dll -Force

# ---------- 校验 ----------
$chk = [System.IO.File]::ReadAllBytes($dll)
$bad = 0
foreach ($v in $ptrMap.Keys) {
    $rva = [uint32]($ptrMap[$v] - $imgBase)
    $fo = RvaToOff $rva
    if ($fo -lt 0) { $bad++; continue }
    $e2 = $fo; while ($e2 -lt $chk.Length -and $chk[$e2] -ne 0) { $e2++ }
    $s2 = [System.Text.Encoding]::UTF8.GetString($chk, $fo, $e2 - $fo)
    if ($s2 -ne $v) { $bad++ }
}

Say ''
Say "✅ 完成：翻译表里替换 $appliedItems 条（$appliedSlots 个条目）；就地改写 $($literalDone.Count) 条；改指针 $($ptrDone.Count) 条。"
if ($bad -gt 0) { Warn "校验有 $bad 条不一致，请用 .zhCN-backup 还原后重试。" }
if ($literalDone.Count -gt 0 -and -not $Quiet) {
    Say '就地改写：'
    $literalDone | Select-Object -First 10 | ForEach-Object { Say "   $_" }
}
if ($ptrDone.Count -gt 0 -and -not $Quiet) {
    Say '改指针：'
    $ptrDone | Select-Object -First 10 | ForEach-Object { Say "   $_" }
}
if ($literalTooLong.Count -gt 0) {
    Warn "以下 $($literalTooLong.Count) 条没能应用（这份 DLL 的翻译表里没有，也不是能改的硬编码字符串）："
    $literalTooLong | Select-Object -First 15 | ForEach-Object { Warn "   $_" }
}
Say '   游戏里重开一次 Insert 菜单即可看到；想还原就运行 还原原版.bat。'
if (-not $Quiet) { Say ''; Read-Host '按回车退出' | Out-Null }
