[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArchivePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

function Read-AsarNode {
    param(
        [Parameter(Mandatory = $true)] [object]$Node,
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string]$RelativePath,
        [Parameter(Mandatory = $true)] [byte[]]$ArchiveBytes,
        [Parameter(Mandatory = $true)] [long]$DataStart,
        [Parameter(Mandatory = $true)] [string]$Destination
    )

    if ($Node.files) {
        foreach ($property in $Node.files.psobject.Properties) {
            $childPath = if ($RelativePath) { Join-Path $RelativePath $property.Name } else { $property.Name }
            Read-AsarNode -Node $property.Value -RelativePath $childPath -ArchiveBytes $ArchiveBytes -DataStart $DataStart -Destination $Destination
        }
        return
    }

    if ($Node.unpacked) {
        # Unpacked entries are intentionally recorded but not copied from the archive.
        return
    }

    if ($null -eq $Node.offset -or $null -eq $Node.size) {
        throw "ASAR entry has no offset/size: $RelativePath"
    }

    $offset = [long]$Node.offset
    $size = [long]$Node.size
    $start = $DataStart + $offset
    if ($start -lt 0 -or $size -lt 0 -or $start + $size -gt $ArchiveBytes.Length) {
        throw "ASAR entry is outside archive bounds: $RelativePath"
    }

    $target = Join-Path $Destination $RelativePath
    $targetFull = [IO.Path]::GetFullPath($target)
    $destinationFull = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    if (-not $targetFull.StartsWith($destinationFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe ASAR path: $RelativePath"
    }
    $parent = Split-Path -Parent $target
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($target, $ArchiveBytes[$start..($start + $size - 1)])
}

if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "Archive not found: $ArchivePath"
}
$archiveFull = [IO.Path]::GetFullPath($ArchivePath)
$bytes = [IO.File]::ReadAllBytes($archiveFull)
if ($bytes.Length -lt 16) { throw 'File is too small to be an ASAR archive.' }

$jsonSize = [BitConverter]::ToUInt32($bytes, 12)
$jsonStart = 16
$dataStart = $jsonStart + $jsonSize
if ($dataStart -gt $bytes.Length) { throw 'ASAR header exceeds archive length.' }
$json = [Text.Encoding]::UTF8.GetString($bytes, $jsonStart, $jsonSize)
$root = $json | ConvertFrom-Json

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Read-AsarNode -Node $root -RelativePath '' -ArchiveBytes $bytes -DataStart $dataStart -Destination $OutputDirectory
Write-Host "Extracted ASAR: $archiveFull"
Write-Host "Output: $([IO.Path]::GetFullPath($OutputDirectory))"
