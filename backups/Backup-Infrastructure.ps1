. $PSScriptRoot/../CIScripts/Common/Init.ps1

class VMSpec {
    [string] $Name
    [bool] $SupportsQuiesce = $true
}

function Backup-Infrastructure {
    Param(
        [Parameter(Mandatory = $true)] [VMSpec[]] $VirtualMachines,
        [Parameter(Mandatory = $true)] [string] $Repository
    )

    $backupsDir = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-hhmmss")
    $backupsPath = Join-Path -Path $Repository -ChildPath $backupsDir
    if (!(Test-Path -Path $backupsPath)) {
        New-Item $backupsPath -ItemType Directory
    }

    $failedForVirtualMachines = @()

    Connect-VBRServer
    foreach ($vm in $VirtualMachines) {
        try {
            Backup-VirtualMachine -VirtualMachine $vm -BackupsPath $backupsPath
        } catch {
            $failedForVirtualMachines += $_.Exception.Message
        }
    }
    Disconnect-VBRServer

    if ($failedForVirtualMachines) {
        $message = "Backup failed for vms: " + ($failedForVirtualMachines -join ",")
        throw $message
    }
}

function Backup-VirtualMachine {
    Param(
        [Parameter(Mandatory = $true)] [VMSpec] $VirtualMachine,
        [Parameter(Mandatory = $true)] [string] $BackupsPath,
        [Parameter(Mandatory = $false)] [int32] $CompressionLevel = 5
    )

    $Entity = Find-VBRViEntity -Name $vm.name
    if (!$Entity) {
        throw $vm.name
    }
    try {
        $zipParams = @{
            'Folder'=$BackupsPath;
            'Entity'=$Entity;
            'Compression'=$CompressionLevel;
        }
        if (!$vm.SupportsQuiesce) {
            $zipParams['DisableQuiesce'] = $true
        }
        Start-VBRZip @zipParams
    } catch {
        throw $vm.name
    }
}
