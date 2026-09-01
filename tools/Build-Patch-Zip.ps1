[CmdletBinding()]
param(
    [string]$PatchRoot = '',
    [string]$OutputZip = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PatchRoot)) {
    # Resolve the script directory at runtime; $PSScriptRoot may be empty
    # under Windows PowerShell when invoked through a wrapper.
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
            if (Test-Path -LiteralPath (Join-Path $candidateDir 'Build-Patch-Zip.ps1') -PathType Leaf) {
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
if ([string]::IsNullOrWhiteSpace($OutputZip)) { $OutputZip = Join-Path $PatchRoot 'Lowmoor-Chinese-Patch.zip' }
$stage = Join-Path ([IO.Path]::GetTempPath()) ('lowmoor-patch-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $stage 'payload'
New-Item -ItemType Directory -Force -Path (Join-Path $payload 'chinese-patch\tools'), (Join-Path $payload 'chinese-patch\translation'), (Join-Path $payload 'chinese-patch\fonts') | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $PatchRoot 'release-root\安装汉化.cmd') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $PatchRoot 'release-root\卸载汉化.cmd') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $PatchRoot 'tools\Apply-Asar-Patch.ps1') -Destination (Join-Path $payload 'chinese-patch\tools')
    Copy-Item -LiteralPath (Join-Path $PatchRoot 'tools\Extract-Asar.ps1') -Destination (Join-Path $payload 'chinese-patch\tools')
    Copy-Item -LiteralPath (Join-Path $PatchRoot 'translation\patch-manifest.json') -Destination (Join-Path $payload 'chinese-patch\translation')
    if (Test-Path -LiteralPath (Join-Path $PatchRoot 'translation\runtime-zh.js') -PathType Leaf) {
        Copy-Item -LiteralPath (Join-Path $PatchRoot 'translation\runtime-zh.js') -Destination (Join-Path $payload 'chinese-patch\translation')
    }
    if (Test-Path -LiteralPath (Join-Path $PatchRoot 'translation\runtime-zh-exact.js') -PathType Leaf) {
        Copy-Item -LiteralPath (Join-Path $PatchRoot 'translation\runtime-zh-exact.js') -Destination (Join-Path $payload 'chinese-patch\translation')
    }
    if (Test-Path -LiteralPath (Join-Path $PatchRoot 'translation\font-injection-entry.json') -PathType Leaf) {
        Copy-Item -LiteralPath (Join-Path $PatchRoot 'translation\font-injection-entry.json') -Destination (Join-Path $payload 'chinese-patch\translation')
    }
    $fontSource = Join-Path $PatchRoot 'fonts'
    if (Test-Path -LiteralPath $fontSource -PathType Container) {
        Copy-Item -Path (Join-Path $fontSource '*') -Destination (Join-Path $payload 'chinese-patch\fonts') -Recurse -Force
    }
    Set-Content -LiteralPath (Join-Path $payload 'chinese-patch\PATCH_STATUS.txt') -Encoding UTF8 -Value @(
        'Lowmoor Chinese Patch - release package',
        '简体中文汉化已完成全量静态文本、动态模板、资源覆盖与格式审计。',
        '本版本已修复复杂窗口（军械库、技能树等）因重复翻译扫描导致的数秒级输入延迟。',
        '安装/卸载脚本可从游戏根目录运行，也可从 chinese-patch 目录运行；无需填写参数。',
        'Uninstall with 卸载汉化.cmd; the original resources/app.asar is backed up automatically.'
    )
    if (Test-Path -LiteralPath $OutputZip) { Remove-Item -LiteralPath $OutputZip -Force }
    Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $OutputZip -CompressionLevel Optimal
    Write-Host "Created: $([IO.Path]::GetFullPath($OutputZip))"
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
