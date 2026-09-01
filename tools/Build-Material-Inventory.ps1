[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$ExtractedDirectory,
    [Parameter(Mandatory = $true)] [string]$OutputCsv,
    [Parameter(Mandatory = $true)] [string]$OutputJson
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ExtractedDirectory)
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Directory not found: $root" }

$textExtensions = @('.html', '.htm', '.js', '.css', '.json', '.txt', '.md', '.xml', '.svg', '.csv')
$rows = foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
    $relative = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
    $ext = $file.Extension.ToLowerInvariant()
    $classification = 'runtime-or-binary'
    $reason = 'Internal/runtime file; inspect only if it contains player-visible text.'
    if ($relative -match '^(game/|assets/)') {
        $classification = 'player-facing-candidate'
        $reason = 'Game UI, narrative, content, or visual asset directory.'
    } elseif ($relative -match '(^|/)(main|preload|window|settings|zoom|steam|lowmoor-boot)\.js$') {
        $classification = 'runtime-entry'
        $reason = 'Runtime entry; translate only user-visible strings and preserve APIs.'
    } elseif ($relative -eq 'package.json') {
        $classification = 'metadata'
        $reason = 'Packaging metadata; normally not translated.'
    }
    [PSCustomObject]@{
        path = $relative
        size_bytes = $file.Length
        extension = $ext
        text_candidate = ($textExtensions -contains $ext)
        classification = $classification
        reason = $reason
    }
}
$rows | Sort-Object path | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $OutputCsv
$rows | Sort-Object path | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $OutputJson
Write-Host "Inventory entries: $($rows.Count)"
