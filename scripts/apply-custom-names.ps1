# 把译名写进游戏自己的 bin\longshot_vk.dll（不改代码段，只追加一个 .zhcn 节放译文，再把语言表里的指针指过去）
# 关键：改的是“你这台电脑上那份 DLL”本身，所以游戏版本/构建不会不匹配。
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
$running = Get-Process -Name longshot -ErrorAction SilentlyContinue
if ($running) { Warn '游戏正在运行，请先退出游戏。'; if (-not $Quiet -and (Read-Host '继续？(y/N)').Trim().ToLower() -ne 'y') { exit 1 } }

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
                            return [pscustomobject]@{ Code = $code; EntriesRva = [uint32]($entriesPtr - $imgBase); Count = [int]$count; EntriesOff = [int]$eo }
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
if ($items.Count -eq 0) { Say '没有要修改的内容。'; if (-not $Quiet) { Read-Host '按回车退出' | Out-Null }; exit 0 }

# ---------- 准备 .zhcn 节 ----------
$limit = 0x4000
$existing = $secs | Where-Object { $_.Name -eq '.zhcn' }
if ($existing) {
    $secVA = $existing.VA; $secRPtr = $existing.RPtr; $secRSize = $existing.RSize
    Say "复用已有 .zhcn 节（$secRSize 字节）"
    [Array]::Clear($bytes, $secRPtr, $secRSize)
    # 上次补丁留下的指针、而这次的清单里没有的条目：把文本指针改回英文原文，避免变成空白
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
    # 节表变了，重新算语言表里各条目的文件偏移
    $tables = @()
    foreach ($code in @('zh-Hans', 'zh-Hant')) {
        $t = FindTable $code
        if ($t) { $tables += $t }
    }
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
        $eo = $t.EntriesOff
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

# ---------- 第二遍：直接改写 DLL 里硬编码的英文原名 ----------
# 有些构建（旧版 / 自己编译的）里道具名根本不在这张翻译表里，而是菜单直接显示的字面量。
# 这种地方没有“指针”可换，只能就地覆盖：中文的 UTF-8 字节数必须不超过英文原名的字节数。
$literalDone = @()
$literalTooLong = @()
$unknownLeft = @()
if ($unknown.Count -gt 0) {
    $latinAll = $latin.GetString($bytes)   # 1 字节 = 1 字符，字符串下标就是文件偏移
    $tableRanges = @()
    foreach ($t in $tables) { $tableRanges += , @($t.EntriesOff, ($t.EntriesOff + 16 * $t.Count)) }
    foreach ($key in $unknown) {
        $it = $items | Where-Object { $_.Key -eq $key } | Select-Object -First 1
        if (-not $it) { continue }
        $vb = [System.Text.Encoding]::UTF8.GetBytes($it.Value)
        $needleLen = $key.Length
        if ($vb.Length -gt $needleLen) { $literalTooLong += ("{0} = {1}（原名 {2} 字节，中文 {3} 字节）" -f $key, $it.Value, $needleLen, $vb.Length); continue }
        $pos = 0
        $hits = 0
        while (($pos = $latinAll.IndexOf($key, $pos, [System.StringComparison]::Ordinal)) -ge 0) {
            $endp = $pos + $needleLen
            $inTable = $false
            foreach ($r in $tableRanges) { if ($pos -ge $r[0] -and $pos -lt $r[1]) { $inTable = $true; break } }
            if (-not $inTable -and $endp -lt $bytes.Length -and $bytes[$endp] -eq 0 -and ($pos -eq 0 -or $bytes[$pos - 1] -eq 0)) {
                [Array]::Copy($vb, 0, $bytes, $pos, $vb.Length)
                $bytes[$pos + $vb.Length] = 0
                $hits++
            }
            $pos++
        }
        if ($hits -gt 0) { $literalDone += ("{0} → {1}（{2} 处）" -f $key, $it.Value, $hits) } else { $unknownLeft += $key }
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
$cur = @{}
foreach ($it in $items) { if (-not $cur.ContainsKey($it.Value)) { $cur[$it.Value] = 0 } }
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

if (-not $Quiet) {
    Say ''
    Say "✅ 完成：翻译表里替换 $applied 条；DLL 里就地改写 $($literalDone.Count) 条。"
    Say '   游戏里重开一次 Insert 菜单即可看到；把译名改回原样再运行即可恢复。'
}
if ($bad -gt 0) { Warn "校验有 $bad 条不一致，请用 .zhCN-backup 还原后重试。" }
if ($literalTooLong.Count -gt 0) {
    Warn "以下 $($literalTooLong.Count) 条中文比英文原名长，DLL 原位放不下（请把译名缩短后重跑）："
    $literalTooLong | Select-Object -First 20 | ForEach-Object { Warn "   $_" }
}
if ($literalDone.Count -gt 0 -and -not $Quiet) {
    Say "就地改写（旧构建里硬编码的名字）："
    $literalDone | Select-Object -First 20 | ForEach-Object { Say "   $_" }
}
if ($unknownLeft.Count -gt 0) {
    Warn "以下 $($unknownLeft.Count) 条在这份 DLL 里既不在翻译表里、也找不到同名的硬编码字符串："
    $unknownLeft | Select-Object -First 20 | ForEach-Object { Warn "   $_" }
}
if (-not $Quiet) { Say ''; Read-Host '按回车退出' | Out-Null }
