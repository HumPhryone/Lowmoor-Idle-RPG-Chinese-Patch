[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall')]
    [string]$Mode = 'Install',
    [string]$PatchRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PatchRoot)) {
    # $PSScriptRoot is empty in some Windows PowerShell -File/dot-source
    # combinations. Resolve a real tools directory before calling Split-Path.
    $scriptCandidates = @($PSCommandPath, $MyInvocation.MyCommand.Path) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    $toolRoot = $null
    foreach ($candidate in $scriptCandidates) {
        $candidateFull = [IO.Path]::GetFullPath($candidate)
        $candidateDir = Split-Path -Parent $candidateFull
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
    $toolRoot = Join-Path $PatchRoot 'tools'
}
$GameRoot = Split-Path -Parent $PatchRoot
$Archive = Join-Path $GameRoot 'resources\app.asar'
$Backup = Join-Path $GameRoot 'resources\app.asar.chinese-patch-backup'
$ManifestPath = Join-Path $PatchRoot 'translation\patch-manifest.json'

function Assert-Path($path, $kind) {
    if (-not (Test-Path -LiteralPath $path -PathType $kind)) { throw "找不到$kind：$path" }
}

function Read-Manifest {
    Assert-Path $ManifestPath Leaf
    $manifest = [IO.File]::ReadAllText($ManifestPath, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    if ([int]$manifest.format_version -ne 1) { throw '不支持的 patch-manifest format_version。' }
    return $manifest
}

function Add-AsarFileNode {
    param([object]$Root, [string]$RelativePath, [long]$Size, [long]$Offset)
    $parts = $RelativePath -split '/'
    $node = $Root
    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        if (-not $node.Contains($parts[$i])) { $node[$parts[$i]] = [ordered]@{ files = [ordered]@{} } }
        $partNode = $node[$parts[$i]]
        if (-not $partNode.Contains("files")) { $partNode["files"] = [ordered]@{} }
        $node = $partNode.files
    }
    $node[$parts[-1]] = [ordered]@{ size = $Size; offset = [string]$Offset }
}

function Write-Asar {
    param([string]$SourceDirectory, [string]$DestinationArchive)
    $sourceFull = [IO.Path]::GetFullPath($SourceDirectory)
    $files = Get-ChildItem -LiteralPath $sourceFull -Recurse -File | Sort-Object FullName
    $tree = [ordered]@{ files = [ordered]@{} }
    $offset = [long]0
    $payloadFiles = [Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($sourceFull.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
        Add-AsarFileNode -Root $tree.files -RelativePath $relative -Size $file.Length -Offset $offset
        $payloadFiles.Add([PSCustomObject]@{ file = $file; offset = $offset })
        $offset += $file.Length
    }

    $json = $tree | ConvertTo-Json -Depth 20 -Compress
    $jsonBytes = [Text.Encoding]::UTF8.GetBytes($json)
    $header = New-Object byte[] 16
    [BitConverter]::GetBytes([uint32]4).CopyTo($header, 0)
    [BitConverter]::GetBytes([uint32]($jsonBytes.Length + 8)).CopyTo($header, 4)
    [BitConverter]::GetBytes([uint32]($jsonBytes.Length + 4)).CopyTo($header, 8)
    [BitConverter]::GetBytes([uint32]$jsonBytes.Length).CopyTo($header, 12)

    $stream = [IO.File]::Open($DestinationArchive, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($header, 0, $header.Length)
        $stream.Write($jsonBytes, 0, $jsonBytes.Length)
        $buffer = New-Object byte[] 1048576
        foreach ($entry in $payloadFiles) {
            $input = [IO.File]::OpenRead($entry.file.FullName)
            try {
                while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) { $stream.Write($buffer, 0, $read) }
            } finally { $input.Dispose() }
        }
    } finally { $stream.Dispose() }
}

function Invoke-Install {
    Assert-Path $Archive Leaf
    $manifest = Read-Manifest
    $entries = @($manifest.entries)
    if ($entries.Count -eq 0) { throw '翻译清单为空：准备阶段不执行安装。' }
    if (-not (Test-Path -LiteralPath $Backup -PathType Leaf)) { Copy-Item -LiteralPath $Archive -Destination $Backup }

    $work = Join-Path ([IO.Path]::GetTempPath()) ('lowmoor-asar-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    try {
        & (Join-Path $toolRoot 'Extract-Asar.ps1') -ArchivePath $Backup -OutputDirectory $work
        $fontSource = Join-Path $PatchRoot 'fonts'
        if (Test-Path -LiteralPath $fontSource -PathType Container) {
            $fontTarget = Join-Path $work 'game\fonts'
            New-Item -ItemType Directory -Force -Path $fontTarget | Out-Null
            Copy-Item -Path (Join-Path $fontSource '*') -Destination $fontTarget -Recurse -Force
        }
        $runtimeSource = Join-Path $PatchRoot 'translation\runtime-zh.js'
        if (Test-Path -LiteralPath $runtimeSource -PathType Leaf) {
            Copy-Item -LiteralPath $runtimeSource -Destination (Join-Path $work 'game\zh.js') -Force
        }
        $exactSource = Join-Path $PatchRoot 'translation\runtime-zh-exact.js'
        if (Test-Path -LiteralPath $exactSource -PathType Leaf) {
            Copy-Item -LiteralPath $exactSource -Destination (Join-Path $work 'game\zh-exact.js') -Force
        }
        foreach ($entry in $entries) {
            if ([string]::IsNullOrWhiteSpace($entry.path) -or $null -eq $entry.old -or $null -eq $entry.new) { throw '清单条目缺少 path、old 或 new。' }
            $target = Join-Path $work ($entry.path -replace '/', [string][char]92)
            Assert-Path $target Leaf
            $text = [IO.File]::ReadAllText($target, [Text.UTF8Encoding]::new($false))
            $expected = if ($null -eq $entry.expected_count) { 1 } else { [int]$entry.expected_count }
            $actual = ([regex]::Matches($text, [regex]::Escape([string]$entry.old))).Count
            if ($actual -ne $expected) { throw "替换次数不符 [$($entry.path)]：期望 $expected，实际 $actual。" }
            $updated = $text.Replace([string]$entry.old, [string]$entry.new)
            [IO.File]::WriteAllText($target, $updated, [Text.UTF8Encoding]::new($false))
        }
        $newArchive = Join-Path (Join-Path $work '..') 'app.asar.new'
        Write-Asar -SourceDirectory $work -DestinationArchive $newArchive
        Move-Item -LiteralPath $newArchive -Destination $Archive -Force
    } finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    }
    Write-Host '汉化补丁安装完成。原始封包已保存为 resources\app.asar.chinese-patch-backup。'
}

function Invoke-Uninstall {
    Assert-Path $Backup Leaf
    Copy-Item -LiteralPath $Backup -Destination $Archive -Force
    Write-Host '汉化补丁已卸载，原始封包已恢复。'
}

if ($Mode -eq 'Install') { Invoke-Install } else { Invoke-Uninstall }

