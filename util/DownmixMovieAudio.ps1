<#
    .SYNOPSIS
    Iterates over a movie directory, searching for a given file type. Adds a
    downmixed english audio channel and sets it to default
#>
[CmdletBinding()]
Param(
    [Parameter(
        Mandatory=$False,
        ValueFromPipeline=$True,
        ValueFromPipelineByPropertyName=$True,
        Position=0
    )]
    [String]$Path = '/ext/data/media/movies',

    [Parameter(
        Mandatory=$False,
        ValueFromPipeline=$False,
        ValueFromPipelineByPropertyName=$True
    )]
    [String[]]$Extension = @('.mkv')
)

$ErrorActionPreference = 'Stop'

# Import the needed module
Import-Module -Force -Name (
    Join-Path -Path $PSScriptRoot -ChildPath 'MediaFunctions.psm1'
)

# Make sure the path exists, etc
if (-not (Test-Path -Path $Path)) {
    throw [System.IO.FileNotFoundException]::new(
        "Unable to find path: $Path",
        $Path
    )
}

# Get the list of files to iterate over
$Files = @(
    Get-ChildItem -LiteralPath $Path -Recurse -File |
        Where-Object { $_.Extension -in $Extension } |
        Sort-Object -Property Name
)

Write-Verbose "Updating the following files:"
$Files | ForEach-Object {
    Write-Verbose "  $($_.Name)"
}

$Iterator = 1
foreach ($File in $Files) {
    Write-Progress -Activity 'AudioDownmix' -Status "Updating $($File.Name)..."
    Add-DownmixedAudioStream -Path $File.FullName -Verbose -RemoveOriginal
    $PerComp = $Iterator++ / $Files.Count * 100
    Write-Progress -Activity 'AudioDownmix' -Status "Completed updating $($File.Name)!" -PercentComplete $PerComp
}
Write-Progress -Activity 'AudioDownmix' -Status "Complete!" -Completed