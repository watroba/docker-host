function Add-DownmixedAudioStream {
    <#
        .SYNOPSIS
        Adds a downmixed to 2 channel audio track to a media container

        .DESCRIPTION
        .PARAMETER 1
        .EXAMPLE
        .NOTES
        Requires ffmpeg and mediainfo cmdlets
    #>

    [CmdletBinding()]
    Param (
        [Parameter(
            Mandatory=$True,
            ValueFromPipeline=$True,
            ValueFromPipelineByPropertyName=$True
        )]
        [String]$Path,

        [Parameter(
            Mandatory=$False,
            ValueFromPipeline=$False,
            ValueFromPipelineByPropertyName=$True
        )]
        [switch]$RemoveOriginal = $False
    )

    $ErrorActionPreference = 'Stop'

    # Make sure the file exists 
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Warning "Path does not exist!"
        Write-Warning "   Path : $Path"
        throw "File not found!"
    }

    Write-Verbose "Make sure our path is actually valid for use"
    $Path = $(Resolve-Path -LiteralPath $Path).Path

    Write-Verbose "Prep all the pathy stuff"
    $PathFolder = Split-Path -Path $Path -Parent
    $FileName =  Split-Path -Path $Path -Leaf
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $Extension = [System.IO.Path]::GetExtension($Path)
    $OutputFileName = "$BaseName-WAT-2.1$Extension"
    $OutputPath = Join-Path -Path $PathFolder -ChildPath $OutputFileName

    Write-Verbose "Get the mediainfo for the file"
    $MediaInfo = Get-MediaInformation -Path $Path

    Write-Verbose "Get the list of audio streams and find the first english one"
    $AudioStreams = @(
        $MediaInfo.media.track | Where-Object { $_.'@type' -eq 'Audio' }
    )
    $EnglishAudioStreams = @(
        $AudioStreams | Where-Object { $_.Language -eq 'en' }
    )
    # $DownmixedAudioStreams = @(
    #     $EnglishAudioStreams | Where-Object { $_.Channels -eq 2 }
    # )
    $WATAudioStreams = @(
        $EnglishAudioStreams | 
            Where-Object { $_.Title -eq 'English 2.0 Stereo WAT' }
    )
    if ($AudioStreams.Count -le 0) {
        Write-Warning "No valid audio streams found in file!"
        Write-Warning "    Path : $Path"
        throw "No audio streams found!"
    }
    if ($EnglishAudioStreams.Count -le 0) {
        Write-Warning "No valid 'ENGLISH' audio streams found in file!"
        Write-Warning "    Path : $Path"
        Write-Warning "Removing language filter..."
        $EnglishAudioStreams = $AudioStreams
    }
    if ($WATAudioStreams.Count -ge 1) {
        Write-Verbose "File already contains downmixed audio stream. Ignoring."
        Write-Verbose "   Path : $Path"
        return
    }

    Write-Verbose "Total Audio Streams   : $($AudioStreams.Count)"
    Write-Verbose "English Audio Streams : $($EnglishAudioStreams.Count)"
    Write-Verbose "WAT Audio Streams     : $($WATAudioStreams.Count)"

    Write-Verbose "Prefer the highest count of channels or the default stream"
    $EnglishAudioStreams = $EnglishAudioStreams | Sort-Object -Property @(
        @{ 'Expression' = 'Channels'; 'Descending' = $True },
        @{ 'Expression' = 'StreamOrder'; 'Descending' = $False }
    )

    Write-Verbose "Get the index of the first stream, and offset back to zero index"
    # Media info uses 1 based indexing
    [int]$EnglishAudioStreamIndex = $Null
    $Parsed = [int]::TryParse(
                $EnglishAudioStreams[0].'StreamOrder',
                [ref]$EnglishAudioStreamIndex
            )
    if (-not $Parsed){
        Write-Warning "Failed to parse stream index"
        Write-Warning "    $($EnglishAudioStreams[0].'StreamOrder')"
        throw "Faild to parse stream index"
    }
    $EnglishAudioStreamIndex--

    # ffmpeg commands
    #  - Base command to execute ffmpeg. 0 is filename
    #  - Copy all video streams in existing order (if they exist)
    #  - Copy all subtitles in existing order (if they exist)
    #  - Copy all data streams if (if they exist)
    $BaseCommand = [System.Collections.Generic.List[String]]@(
        '-map 0:v? -c:v copy',
        '-map 0:s? -c:s copy',
        '-map 0:d? -c:d copy'
    )

    # Copy all audio tracks in existing order wth an incremented index (if they exist)
    # Set the dispositon to none to remove default status
    $BaseAudioCmd = '-map 0:a:{0}? -c:a:{1} copy -disposition:a:{1} none'
    for ($i = 0; $i -lt $AudioStreams.Count; $i++){
        $BaseCommand.Add((
            $BaseAudioCmd -f $i,$($i + 1)
        ))
    }

    # Copy the first audio track again, downmixing in the process
    # Assume this audio track will be in the same position in both the source and 
    # destination. All others will be pushed further down
    $DownmixCopyCmd = (
        '-map 0:a:{0}? -c:a:{1} ac3 -ac 2 -lfe_mix_level 1',
        '-metadata:s:a:{1} title="English 2.0 Stereo WAT"',
        '-metadata:s:a:{1} language=eng',
        '-disposition:a:{1} default'
    ) -join ' '
    $BaseCommand.Add((
        $DownmixCopyCmd -f $EnglishAudioStreamIndex,0
    ))

    # Convert base command to a string
    $BaseCommand = $BaseCommand -join ' '

    # Media processing time
    try {

        # Make sure the output path doesn't already exist
        if (Test-Path -Path $OutputPath) {
            Remove-Item -Path $OutputPath -Force
        }

        # ffmpeg doesn't support full paths, so push to that location
        Write-Verbose "Pushing to $($PathFolder)"
        Push-Location -Path $PathFolder

        # Execute our big ol' command
        Write-Verbose "Command:"
        Write-Verbose "ffmpeg -y -i $FileName $($BaseCommand.Split('')) $OutputFileName"

        # Execute the ffmpeg command
        #
        # NOTE: This hackiness is what allows redirection of data written to the
        # stderr stream (stream 2) without throwing an error
        # Essentially, we run the whole command with Invoke-Command (which in the
        # current, local case, inherits scope and variables from this script),
        # specify that we're ignoring errors but allowing the stream contents to 
        # still be displayed (error action preference of 'continue'), perform the
        # redirecton, and capture the lastexitcode an send it into the pipeline as
        # a hashtable, which allows us to reference that key/value using some
        # collection property enumeration magic to get that value seperate from
        # the other string output
        #
        # TODO: Implement hackiness
        & ffmpeg -y -i $FileName $BaseCommand.Split(' ') $OutputFileName

        # Check for any errors. ffmpeg uses 0 as the only success code
        if ($LASTEXITCODE -ne 0) {
            throw "Error processing!"
        }
    }
    catch {
        Write-Warning "Something went wrong with processing the media file!"
        Write-Warning "   Path : $Path"
        $_ | Write-Warning
        throw "Failed to process file with ffmpeg"
    }
    finally {
        Pop-Location
    }

    # Make sure the new file was created properly and has the new media stream
    if (-not (Test-Path -Path $OutputPath -PathType Leaf)) {
        Write-Warning "Unable to locate output file!"
        Write-Warning "    Output Path : $OutputPath"
        throw "Failed to find processed file"
    }

    Write-Verbose "Get the mediainfo for the file"
    $MediaInfo = Get-MediaInformation -Path $OutputPath

    # Get the list of audio streams and find the first english one
    
    
    $NewAudioStreams = @(
        $MediaInfo.media.track | 
            Where-Object { 
                $_.'@type' -eq 'Audio' -and
                $_.Language -eq 'en' -and
                $_.Title -eq 'English 2.0 Stereo WAT'
                #$_.Channels -eq 2
            }
    )
    if ($NewAudioStreams.Count -lt 1) {
        Write-Warning "File doesn't contain downmixed audio stream!"
        Write-Warning "   Output Path : $OutputPath"
        # Add back after testing
        # Remove-Item -Path $OutputPath -Force
        throw 'Failed to downmix audio stream!'
    }
    if ($NewAudioStreams.Count -le $WATAudioStreams.Count) {
        Write-Warning "File has fewer than exected audio streams!"
        Write-Warning "   Output Path : $OutputPath"
        Write-Warning "Original Count : $($AudioStreams.Count)"
        Write-Warning "     New Count : $($AudioStreams.Count)"
        # Add back after testing
        # Remove-Item -Path $OutputPath -Force
        throw 'Audio streams missing!'
    }

    Write-Verbose "Audio downmixing succeeded for: $OutputPath"
    if ($RemoveOriginal) {
        Write-Verbose "Replacing original file with downmixed copy"
        Remove-Item -Path $Path -Force
        Rename-Item -Path $OutputPath -NewName $FileName
    }
}

function Get-MediaInformation {
    [CmdletBinding()]
    Param (
        [Parameter(
            Mandatory=$True,
            ValueFromPipeline=$True,
            ValueFromPipelineByPropertyName=$True
        )]
        [String]$Path
    )

    $ErrorActionPreference = 'Stop'

    # Make sure the file exists 
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Warning "Path does not exist!"
        Write-Warning "   Path : $Path"
        throw "File not found!"
    }

    Write-Verbose "Make sure our path is actually valid for use"
    $Path = $(Resolve-Path -Path $Path).Path

    Write-Verbose "Get the mediainfo for the file"
    try {
        $MediaInfoRaw = & mediainfo $('"' + $Path + '"') '--output=JSON'
        if (-not $?) {
            $MediaInfoRaw | Write-Warning
            throw "Error executing media info extraction!"
        }
        $MediaInfo = $MediaInfoRaw | ConvertFrom-JSON
        $MediaInfo
    }
    catch {
        $_ | Write-Warning
        throw $_
    }
}

function Test-AudioStream {}