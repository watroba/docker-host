# Updates files on the remote system
#Requires -Module Posh-SSH
[CmdletBinding(
    DefaultParameterSetName='UserAndPass',
    SupportsShouldProcess=$True
)]
Param(
    [Parameter(
        Mandatory=$False,
        ValueFromPipelineByPropertyName=$True,
        ParameterSetName='UserAndPass'
    )]
    [String]$Username = "caboose",

    [Parameter(
        Mandatory=$False,
        ValueFromPipelineByPropertyName=$True,
        ParameterSetName='UserAndPass'
    )]
    [System.Security.SecureString]$Password=$Null,

    [Parameter(
        Mandatory=$True,
        ValueFromPipelineByPropertyName=$True,
        ParameterSetName='Cred'
    )]
    [System.Management.Automation.PSCredential]$Credential=$(
        [System.Management.Automation.PSCredential]::Empty
    ),

    [Parameter(
        Mandatory=$False,
        ValueFromPipelineByPropertyName=$True   
    )]
    [String]$RemoteHost = "192.168.2.104",

    [Parameter(
        Mandatory=$False,
        ValueFromPipelineByPropertyName=$True   
    )]
    [String]$DestinationFolder = "/ext/compute",

    [Parameter(
        Mandatory=$False,
        ValueFromPipelineByPropertyName=$True   
    )]
    [ValidateSet('dev0', 'dev1', 'prod', 'test', 'util', 'all')]
    [String[]]$Environment = 'dev0'
)

$ErrorActionPreference = 'Stop'
if ($Environment -contains 'All') {
    $Environment = @('dev0', 'dev1', 'prod', 'test', 'util')
}
Write-Host -ForegroundColor Cyan "[$(Get-Date -Format o)] >>> Remote FU (File Updater)"
Write-Host -ForegroundColor Gray "[$(Get-Date -Format o)]  Remote      : $RemoteHost"
Write-Host -ForegroundColor Gray "[$(Get-Date -Format o)]  Environment : $Environment"
Write-Host -ForegroundColor Gray "[$(Get-Date -Format o)]  Folder      : $DestinationFolder"

# List of files to copy over
# $Files = @(
#     @{
#         "Source" = "$PSScriptRoot/.env"
#         "Destination" = "$DestinationFolder"
#     },
#     @{
#         "Source" = "$PSScriptRoot/docker-compose.yml"
#         "Destination" = "$DestinationFolder"
#     },
#     @{
#         "Source" = "$PSScriptRoot/docker-compose-test.yml"
#         "Destination" = "$DestinationFolder"
#     },
#     @{
#         "Source" = "$PSScriptRoot/docker/traefik/traefik.yaml"
#         "Destination" = "$DestinationFolder/docker/traefik"
#     }
# )
try {
    Push-Location -StackName 'RemoteFileProc' -Path $PSScriptRoot
    $Files = Get-ChildItem -Path $PSScriptRoot -Directory |
        Where-Object { $_.Name -in $Environment } |
        Get-ChildItem -File -Recurse |
        ForEach-Object {
            $Folder = Split-Path -Parent -Path $_.FullName
            $Destination = (Resolve-Path -Path $Folder -Relative) -Split '\\|/' -Join '/' -replace '^\.',$DestinationFolder
            [PSCustomObject]@{
                'Source' = $_.FullName
                'Destination' = $Destination
            }
        }
}
catch {
    throw
}
finally {
    Pop-Location -StackName 'RemoteFileProc' -ErrorAction SilentlyContinue
}

# Build the cred object
if ($Null -eq $Credential -or
    $Credential -eq [System.Management.Automation.PSCredential]::Empty) {

    if($Null -eq $Password){
        $Password = $(
            Read-Host -AsSecureString -Prompt "Enter password for [$Username]"
        )
    }
    $Credential = [System.Management.Automation.PSCredential]::new(
        $Username,
        $Password
    )
}

# Build splatting for call
$SCPParams = @{
    'ComputerName' = $RemoteHost
    'NoProgress' = $True
    'AcceptKey' = $True
}
$SCPParams.Add('Credential',$Credential)

# Loop and copy the files
Write-Host -ForegroundColor White "[$(Get-Date -Format o)] Beginning update..."
foreach ($File in $Files) {

    Write-Host -ForegroundColor White  "[$(Get-Date -Format o)] Copying " -NoNewline
    Write-Host -ForegroundColor Yellow "$($File.Source) " -NoNewline
    Write-Host -ForegroundColor White  "to " -NoNewline
    Write-Host -ForegroundColor Yellow "$($File.Destination) " -NoNewline
    Write-Host -ForegroundColor White  "on " -NoNewline
    Write-Host -ForegroundColor Yellow "$RemoteHost" -NoNewline
    Write-Host -ForegroundColor White  "..."

    if ($PSCmdlet.ShouldProcess($File.Source,'Copy to remote')) {
        Set-SCPFile @SCPParams -LocalFile $File.Source -RemotePath $File.Destination
    }
}
Write-Host -ForegroundColor Green "[$(Get-Date -Format o)] Update completed."