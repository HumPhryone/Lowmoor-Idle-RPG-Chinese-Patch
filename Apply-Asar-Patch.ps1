[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall')]
    [string]$Mode = 'Install',
    [string]$PatchRoot = ''
)

# Lowmoor 简体中文润色补丁安装器（manifest format_version 2）
# - 直接在 ASAR 封包层面重建：保留 unpacked 条目（steamworks.js 原生模块）与其余文件原样字节；
# - 只改清单列出的文本文件，并加入 add_files；
# - 以流式读写处理 50MB+ 封包，兼容 Windows PowerShell 5.1。

$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

if ([string]::IsNullOrWhiteSpace($PatchRoot)) {
    $scriptCandidates = @($PSCommandPath, $MyInvocation.MyCommand.Path) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    $toolRoot = $null
    foreach ($candidate in $scriptCandidates) {
        $candidateDir = Split-Path -Parent ([IO.Path]::GetFullPath($candidate))
        if ((Split-Path -Leaf $candidateDir) -ieq 'tools') { $toolRoot = $candidateDir; break }
    }
    if ($null -eq $toolRoot) {
        $cwd = [IO.Directory]::GetCurrentDirectory()
        foreach ($candidateDir in @($cwd, (Join-Path $cwd 'tools'), (Join-Path $cwd 'chinese-patch\tools'))) {
            if (Test-Path -LiteralPath (Join-Path $candidateDir 'Apply-Asar-Patch.ps1') -PathType Leaf) {
                $toolRoot = [IO.Path]::GetFullPath($candidateDir); break
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($toolRoot)) { throw '无法确定 chinese-patch\tools 目录。' }
    $PatchRoot = Split-Path -Parent $toolRoot
} else {
    $PatchRoot = [IO.Path]::GetFullPath($PatchRoot)
}

$GameRoot = Split-Path -Parent $PatchRoot
$Archive = Join-Path $GameRoot 'resources\app.asar'
$Backup = Join-Path $GameRoot 'resources\app.asar.chinese-patch-backup'
$ManifestPath = Join-Path $PatchRoot 'translation\patch-manifest.json'
$PatchMarker = 'zh-override.js'

function Read-AsarHeader([string]$Path) {
    $fs = [IO.File]::OpenRead($Path)
    try {
        $head = New-Object byte[] 16
        if ($fs.Read($head, 0, 16) -ne 16) { throw "不是有效的 ASAR 文件：$Path" }
        $pickleSize = [BitConverter]::ToUInt32($head, 4)
        $jsonLen = [BitConverter]::ToUInt32($head, 12)
        if ($jsonLen -le 0 -or $jsonLen -gt 64MB) { throw "ASAR 头部长度异常：$Path" }
        $jsonBytes = New-Object byte[] $jsonLen
        $read = 0
        while ($read -lt $jsonLen) {
            $n = $fs.Read($jsonBytes, $read, $jsonLen - $read)
            if ($n -le 0) { throw "ASAR 头部被截断：$Path" }
            $read += $n
        }
        $raw = $Utf8.GetString($jsonBytes)
        return [PSCustomObject]@{
            Raw       = $raw
            Tree      = ($raw | ConvertFrom-Json)
            DataStart = [long](8 + $pickleSize)
        }
    } finally { $fs.Dispose() }
}

function Get-AsarEntries($Node, [string]$Prefix, $List) {
    foreach ($prop in $Node.files.psobject.Properties) {
        $rel = if ($Prefix) { "$Prefix/$($prop.Name)" } else { $prop.Name }
        if ($null -ne $prop.Value.files) {
            $List.Add([PSCustomObject]@{ Path = $rel; Dir = $true; Node = $prop.Value })
            Get-AsarEntries $prop.Value $rel $List
        } else {
            $List.Add([PSCustomObject]@{ Path = $rel; Dir = $false; Node = $prop.Value })
        }
    }
}

function ConvertTo-JsonString([string]$s) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($ch -eq '"') { [void]$sb.Append('\"') }
        elseif ($ch -eq '\') { [void]$sb.Append('\\') }
        elseif ($c -lt 0x20) { [void]$sb.Append(('\u{0:x4}' -f $c)) }
        else { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# 目录树节点：有序字典 name -> @{ Dir; Children | Meta }
function New-DirNode { return [ordered]@{ '__dir' = $true; '__children' = [ordered]@{} } }

function Add-TreeFile($Root, [string]$RelPath, $Meta) {
    $parts = $RelPath -split '/'
    $node = $Root
    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        if (-not $node['__children'].Contains($parts[$i])) { $node['__children'][$parts[$i]] = New-DirNode }
        $node = $node['__children'][$parts[$i]]
    }
    $node['__children'][$parts[-1]] = $Meta
}

function Write-TreeJson($Node, $sb) {
    [void]$sb.Append('{"files":{')
    $first = $true
    foreach ($name in $Node['__children'].Keys) {
        if (-not $first) { [void]$sb.Append(',') }
        $first = $false
        [void]$sb.Append((ConvertTo-JsonString $name)).Append(':')
        $child = $Node['__children'][$name]
        if ($child.Contains('__dir')) { Write-TreeJson $child $sb }
        else {
            [void]$sb.Append('{')
            $mf = $true
            foreach ($k in $child.Keys) {
                if (-not $mf) { [void]$sb.Append(',') }
                $mf = $false
                [void]$sb.Append((ConvertTo-JsonString $k)).Append(':')
                $v = $child[$k]
                if ($v -is [bool]) { [void]$sb.Append($(if ($v) { 'true' } else { 'false' })) }
                elseif ($v -is [string]) { [void]$sb.Append((ConvertTo-JsonString $v)) }
                elseif ($v -is [System.Collections.IDictionary] -or $v -is [PSCustomObject]) { [void]$sb.Append(($v | ConvertTo-Json -Depth 10 -Compress)) }
                else { [void]$sb.Append([string]$v) }
            }
            [void]$sb.Append('}')
        }
    }
    [void]$sb.Append('}}')
}

function Read-Range([IO.FileStream]$fs, [long]$Offset, [long]$Size) {
    $buf = New-Object byte[] $Size
    [void]$fs.Seek($Offset, [IO.SeekOrigin]::Begin)
    $read = 0
    while ($read -lt $Size) {
        $n = $fs.Read($buf, $read, [int]([Math]::Min(1048576, $Size - $read)))
        if ($n -le 0) { throw 'ASAR 数据被截断。' }
        $read += $n
    }
    return ,$buf
}

function Invoke-Install {
    if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) { throw "找不到游戏封包：$Archive。请把补丁解压到游戏根目录（与 Lowmoor.exe 同级）。" }
    $manifest = [IO.File]::ReadAllText($ManifestPath, $Utf8) | ConvertFrom-Json
    if ([int]$manifest.format_version -ne 2) { throw '不支持的 patch-manifest format_version（需要 2）。' }

    # 备份策略：当前封包未打过补丁（首次安装或 Steam 更新后）→ 刷新备份。
    $current = Read-AsarHeader $Archive
    if ($current.Raw.Contains('"' + $PatchMarker + '"')) {
        if (-not (Test-Path -LiteralPath $Backup -PathType Leaf)) {
            throw '当前封包已被汉化，但找不到原始备份。请在 Steam 中“验证游戏文件的完整性”后重新安装。'
        }
        Write-Host '检测到已安装的汉化，将从原始备份重新构建。'
    } else {
        Copy-Item -LiteralPath $Archive -Destination $Backup -Force
        Write-Host '已备份原始封包：resources\app.asar.chinese-patch-backup'
    }

    $src = Read-AsarHeader $Backup
    $entries = New-Object System.Collections.Generic.List[object]
    Get-AsarEntries $src.Tree '' $entries

    $edits = @{}
    foreach ($e in @($manifest.entries)) {
        if (-not $edits.ContainsKey($e.path)) { $edits[$e.path] = New-Object System.Collections.Generic.List[object] }
        $edits[$e.path].Add($e)
    }
    $adds = @($manifest.add_files)

    $root = New-DirNode
    $payload = New-Object System.Collections.Generic.List[object]   # 按顺序写入的数据块
    $offset = [long]0
    $inFs = [IO.File]::OpenRead($Backup)
    try {
        foreach ($entry in $entries) {
            if ($entry.Dir) { continue }
            $node = $entry.Node
            $meta = [ordered]@{}
            if ($node.unpacked -eq $true) {
                foreach ($p in $node.psobject.Properties) { $meta[$p.Name] = $p.Value }
                Add-TreeFile $root $entry.Path $meta
                continue
            }
            if ($null -ne $node.link) {
                foreach ($p in $node.psobject.Properties) { $meta[$p.Name] = $p.Value }
                Add-TreeFile $root $entry.Path $meta
                continue
            }
            $size = [long]$node.size
            $start = $src.DataStart + [long]$node.offset
            if ($edits.ContainsKey($entry.Path)) {
                $text = $Utf8.GetString((Read-Range $inFs $start $size))
                foreach ($e in $edits[$entry.Path]) {
                    $expected = if ($null -eq $e.expected_count) { 1 } else { [int]$e.expected_count }
                    $actual = ([regex]::Matches($text, [regex]::Escape([string]$e.old))).Count
                    if ($actual -ne $expected) {
                        throw "替换次数不符 [$($entry.Path)]：期望 $expected，实际 $actual。游戏版本可能已更新，请下载对应版本的补丁。"
                    }
                    $text = $text.Replace([string]$e.old, [string]$e.new)
                }
                $bytes = $Utf8.GetBytes($text)
                $payload.Add([PSCustomObject]@{ Bytes = $bytes; Start = [long]-1; Size = [long]$bytes.Length })
                $meta['size'] = [long]$bytes.Length
                $meta['offset'] = [string]$offset
                $offset += $bytes.Length
                $edits.Remove($entry.Path)
            } else {
                $payload.Add([PSCustomObject]@{ Bytes = $null; Start = $start; Size = $size })
                $meta['size'] = $size
                $meta['offset'] = [string]$offset
                if ($node.executable -eq $true) { $meta['executable'] = $true }
                if ($null -ne $node.integrity) { $meta['integrity'] = $node.integrity }
                $offset += $size
            }
            Add-TreeFile $root $entry.Path $meta
        }
        if ($edits.Count -gt 0) { throw ('封包中找不到清单文件：' + (($edits.Keys) -join ', ')) }
        foreach ($a in $adds) {
            $srcPath = Join-Path $PatchRoot ($a.source -replace '/', '\')
            if (-not (Test-Path -LiteralPath $srcPath -PathType Leaf)) { throw "缺少补丁文件：$srcPath" }
            $bytes = [IO.File]::ReadAllBytes($srcPath)
            $payload.Add([PSCustomObject]@{ Bytes = $bytes; Start = [long]-1; Size = [long]$bytes.Length })
            Add-TreeFile $root $a.path ([ordered]@{ size = [long]$bytes.Length; offset = [string]$offset })
            $offset += $bytes.Length
        }

        $sb = New-Object Text.StringBuilder
        Write-TreeJson $root $sb
        $jsonBytes = $Utf8.GetBytes($sb.ToString())
        $aligned = [int]([Math]::Ceiling($jsonBytes.Length / 4.0) * 4)
        $header = New-Object byte[] (16 + $aligned)
        [BitConverter]::GetBytes([uint32]4).CopyTo($header, 0)
        [BitConverter]::GetBytes([uint32]($aligned + 8)).CopyTo($header, 4)
        [BitConverter]::GetBytes([uint32]($aligned + 4)).CopyTo($header, 8)
        [BitConverter]::GetBytes([uint32]$jsonBytes.Length).CopyTo($header, 12)
        [Array]::Copy($jsonBytes, 0, $header, 16, $jsonBytes.Length)

        $tmp = $Archive + '.chinese-patch-new'
        $out = [IO.File]::Open($tmp, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $out.Write($header, 0, $header.Length)
            $buffer = New-Object byte[] 1048576
            foreach ($blk in $payload) {
                if ($null -ne $blk.Bytes) { $out.Write($blk.Bytes, 0, $blk.Bytes.Length); continue }
                [void]$inFs.Seek($blk.Start, [IO.SeekOrigin]::Begin)
                $left = $blk.Size
                while ($left -gt 0) {
                    $n = $inFs.Read($buffer, 0, [int]([Math]::Min($buffer.Length, $left)))
                    if ($n -le 0) { throw 'ASAR 数据被截断。' }
                    $out.Write($buffer, 0, $n)
                    $left -= $n
                }
            }
        } finally { $out.Dispose() }
    } finally { $inFs.Dispose() }

    if (Test-Path -LiteralPath $Archive) {
    Remove-Item -LiteralPath $Archive -Force
}
Move-Item -LiteralPath $tmp -Destination $Archive -Force
    Write-Host '汉化补丁安装完成。进入游戏后在 Options（选项）→ Language 选择“简体中文”。'
    Write-Host 'Steam 更新游戏后如中文润色失效，重新运行 安装汉化.cmd 即可。'
}

function Invoke-Uninstall {
    if (-not (Test-Path -LiteralPath $Backup -PathType Leaf)) { throw '找不到原始备份，无法卸载。可在 Steam 中“验证游戏文件的完整性”恢复原版。' }
    $current = Read-AsarHeader $Archive
    if (-not $current.Raw.Contains('"' + $PatchMarker + '"')) {
        Write-Host '当前封包不是汉化版本（可能已被 Steam 更新），无需卸载。'
        return
    }
    Copy-Item -LiteralPath $Backup -Destination $Archive -Force
    Write-Host '汉化补丁已卸载，原始封包已恢复。'
}

if ($Mode -eq 'Install') { Invoke-Install } else { Invoke-Uninstall }
