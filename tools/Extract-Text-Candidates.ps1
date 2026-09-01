[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$SourceDirectory,
    [Parameter(Mandatory = $true)] [string]$OutputCsv,
    [Parameter(Mandatory = $true)] [string]$OutputJson
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($SourceDirectory)
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Directory not found: $root" }

$items = [Collections.Generic.List[object]]::new()
$seenOffsets = @{}
$nextId = 1
function Add-Candidate {
    param([string]$File, [int]$Line, [string]$Kind, [string]$Text, [string]$Review, [int]$Offset = -1)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $clean = [Net.WebUtility]::HtmlDecode($Text).Trim()
    if ($clean.Length -lt 2) { return }
    $key = "$File|$Offset"
    if ($Offset -ge 0 -and $script:seenOffsets.ContainsKey($key)) { return }
    if ($Offset -ge 0) { $script:seenOffsets[$key] = $true }
    $script:items.Add([PSCustomObject]@{
        id = ('T{0:D6}' -f $script:nextId)
        file = $File.Replace('\', '/')
        line = $Line
        offset = $Offset
        kind = $Kind
        text = $clean
        review = $Review
    })
    $script:nextId++
}

foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { @('.html','.htm','.js','.css','.json','.txt','.md') -contains $_.Extension.ToLowerInvariant() }) {
    # GetRelativePath is unavailable in Windows PowerShell 5.1. Both paths
    # are rooted under $root, so a normalized substring is equivalent here.
    $relative = $file.FullName.Substring($root.Length).TrimStart([char]92, [char]47)
    $content = Get-Content -Raw -LiteralPath $file.FullName
    $ext = $file.Extension.ToLowerInvariant()

    if ($ext -in @('.html','.htm')) {
        foreach ($m in [regex]::Matches($content, '(?is)(?<=^|>)([^<]+)(?=<)')) {
            $line = 1 + (($content.Substring(0, $m.Index) -split "`n").Count - 1)
            Add-Candidate $relative $line 'html-text' $m.Groups[1].Value 'translate if visible; preserve markup and IDs'
        }
        foreach ($m in [regex]::Matches($content, '(?is)(data-help|data-helptitle|aria-label|placeholder|title)\s*=\s*["'']([^"'']+)')) {
            $line = 1 + (($content.Substring(0, $m.Index) -split "`n").Count - 1)
            Add-Candidate $relative $line ('html-' + $m.Groups[1].Value.ToLowerInvariant()) $m.Groups[2].Value 'translate; tooltip/accessibility text is player-visible'
        }
    } elseif ($ext -eq '.js') {
        # Lightweight quote scanner: this intentionally keeps technical literals too,
        # because later review must decide whether a literal reaches the player.
        $i = 0
        while ($i -lt $content.Length) {
            # Do not skip comment-looking text here.  This scanner has no
            # JavaScript lexer state yet, so URLs and `//` inside quoted
            # strings would otherwise desynchronise the quote scan.  Any
            # literals found in comments are harmless candidates and are
            # filtered during review/audit.
            $quote = $content[$i]
            if ($quote -ne "'" -and $quote -ne '"' -and $quote -ne '`') { $i++; continue }
            $start = $i; $i++; $buf = [Text.StringBuilder]::new(); $escaped = $false
            while ($i -lt $content.Length) {
                $ch = $content[$i]
                if ($escaped) { [void]$buf.Append($ch); $escaped = $false; $i++; continue }
                # Compare against the actual backslash character.  A literal
                # '\\' in PowerShell is two characters, so it never matched
                # the single character read from the JavaScript source and
                # apostrophes in escaped single-quoted strings were truncated.
                if ($ch -eq [char]92) { [void]$buf.Append($ch); $escaped = $true; $i++; continue }
                if ($ch -eq $quote) { break }
                [void]$buf.Append($ch); $i++
            }
            if ($i -lt $content.Length -and $content[$i] -eq $quote) {
                $line = 1 + (($content.Substring(0, $start) -split "`n").Count - 1)
                $value = $buf.ToString()
                if ($value -match '[A-Za-z]{2,}|\s' -and $value -notmatch '^[a-zA-Z_$][a-zA-Z0-9_$.-]*$') {
                    Add-Candidate $relative $line 'js-string' $value 'translate only when rendered/logged; preserve placeholders, tags, keys and control words' $start
                }
            }
            $i++
        }
    }
}

$items | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $OutputCsv
$items | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $OutputJson
Write-Host "Text candidates: $($items.Count)"
