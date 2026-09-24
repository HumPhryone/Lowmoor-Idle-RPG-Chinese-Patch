[CmdletBinding()]
param(
    [string]$PatchRoot = '',
    [string]$OutputZip = ''
)

# 打包发布 ZIP：解压到游戏根目录（与 Lowmoor.exe 同级）后运行 安装汉化.cmd。
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PatchRoot)) {
    $scriptPath = @($PSCommandPath, $MyInvocation.MyCommand.Path) | Where-Object { $_ } | Select-Object -First 1
    $PatchRoot = Split-Path -Parent (Split-Path -Parent ([IO.Path]::GetFullPath($scriptPath)))
} else {
    $PatchRoot = [IO.Path]::GetFullPath($PatchRoot)
}
if ([string]::IsNullOrWhiteSpace($OutputZip)) { $OutputZip = Join-Path $PatchRoot 'Lowmoor-Chinese-Patch.zip' }

$stage = Join-Path ([IO.Path]::GetTempPath()) ('lowmoor-patch-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $stage 'payload'
New-Item -ItemType Directory -Force -Path (Join-Path $payload 'chinese-patch\tools'), (Join-Path $payload 'chinese-patch\translation') | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $PatchRoot 'release-root\安装汉化.cmd') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $PatchRoot 'release-root\卸载汉化.cmd') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $PatchRoot 'tools\Apply-Asar-Patch.ps1') -Destination (Join-Path $payload 'chinese-patch\tools')
    foreach ($f in @('patch-manifest.json', 'zh-override.js')) {
        Copy-Item -LiteralPath (Join-Path $PatchRoot ('translation\' + $f)) -Destination (Join-Path $payload 'chinese-patch\translation')
    }
    Copy-Item -LiteralPath (Join-Path $PatchRoot 'LICENSE') -Destination (Join-Path $payload 'chinese-patch') -ErrorAction SilentlyContinue
    Set-Content -LiteralPath (Join-Path $payload 'chinese-patch\说明.txt') -Encoding UTF8 -Value @(
        'Lowmoor 简体中文润色补丁（适用游戏 v1.7.2a / Steam 2026-09-21 版本）',
        '',
        '安装：将压缩包解压到游戏根目录（与 Lowmoor.exe 同级），双击 安装汉化.cmd。',
        '      进入游戏后在 Options（选项）→ Language 选择“简体中文”。',
        '卸载：双击 卸载汉化.cmd，或在 Steam 中“验证游戏文件的完整性”。',
        'Steam 更新游戏后润色会被覆盖，重新运行 安装汉化.cmd 即可；官方已改动的词条会自动沿用官方新译。',
        '原始封包备份：resources\app.asar.chinese-patch-backup'
    )
    if (Test-Path -LiteralPath $OutputZip) { Remove-Item -LiteralPath $OutputZip -Force }
    Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $OutputZip -CompressionLevel Optimal
    Write-Host "Created: $([IO.Path]::GetFullPath($OutputZip))"
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
