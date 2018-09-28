. $PSScriptRoot\..\..\..\CIScripts\Common\Aliases.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Invoke-NativeCommand.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\Configuration.ps1

function Invoke-MsiExec {
    Param (
        [Switch] $Uninstall,
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [String] $Path
    )

    $Action = if ($Uninstall) { "/x" } else { "/i" }

    Invoke-Command -Session $Session -ScriptBlock {
        # Get rid of all leftover handles to the Service objects
        [System.GC]::Collect()

        $Result = Start-Process msiexec.exe -ArgumentList @($Using:Action, $Using:Path, "/quiet") `
            -Wait -PassThru

        # Do not fail while uninstaling MSIs that are not currently installed
        $MsiErrorUnknownProduct = 1605
        if ($Using:Uninstall -and ($Result.ExitCode -eq $MsiErrorUnknownProduct)) {
            return
        }

        if ($Result.ExitCode -ne 0) {
            $WhatWentWrong = if ($Using:Uninstall) {"Uninstallation"} else {"Installation"}
            throw "$WhatWentWrong of $Using:Path failed with $($Result.ExitCode)"
        }

        # Refresh Path
        $Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    }
}

function Install-Agent {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Installing Agent"
    Invoke-MsiExec -Session $Session -Path "C:\Artifacts\contrail-vrouter-agent.msi"
}

function Uninstall-Agent {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Uninstalling Agent"
    Invoke-MsiExec -Uninstall -Session $Session -Path "C:\Artifacts\contrail-vrouter-agent.msi"
}

function Install-Extension {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Installing vRouter Forwarding Extension"
    Invoke-MsiExec -Session $Session -Path "C:\Artifacts\vRouter.msi"
}

function Uninstall-Extension {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Uninstalling vRouter Forwarding Extension"
    Invoke-MsiExec -Uninstall -Session $Session -Path "C:\Artifacts\vRouter.msi"
}

function Install-Utils {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Installing vRouter utility tools"
    Invoke-MsiExec -Session $Session -Path "C:\Artifacts\utils.msi"
}

function Uninstall-Utils {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Uninstalling vRouter utility tools"
    Invoke-MsiExec -Uninstall -Session $Session -Path "C:\Artifacts\utils.msi"
}

function Install-DockerDriver {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Installing Docker Driver"
    Invoke-MsiExec -Session $Session -Path "C:\Artifacts\docker-driver.msi"
}

function Uninstall-DockerDriver {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Uninstalling Docker Driver"
    Invoke-MsiExec -Uninstall -Session $Session -Path "C:\Artifacts\docker-driver.msi"
}

function Install-Nodemgr {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Installing Nodemgr"
    $Res = Invoke-NativeCommand -Session $Session -AllowNonZero -CaptureOutput -ScriptBlock {
        Get-ChildItem "C:\Artifacts\nodemgr\*.tar.gz" -Name
    }
    $Archives = $Res.Output
    foreach($A in $Archives) {
        Write-Log "- (Nodemgr) Installing pip archive $A"
        Invoke-NativeCommand -Session $Session -ScriptBlock {
            pip install "C:\Artifacts\nodemgr\$Using:A"
        } | Out-Null
    }
}

function Uninstall-Nodemgr {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Uninstalling Nodemgr"
    $Res = Invoke-NativeCommand -Session $Session -AllowNonZero -CaptureOutput -ScriptBlock {
        Get-ChildItem "C:\Artifacts\nodemgr\*.tar.gz" -Name
    }
    $Archives = $Res.Output
    foreach($P in $Archives) {
        Write-Log "- (Nodemgr) Uninstalling pip package $P"
        Invoke-NativeCommand -Session $Session -ScriptBlock {
            pip uninstall "C:\Artifacts\nodemgr\$Using:P"
        }
    }
}

function Install-Components {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $false)] [Switch] $InstallNodeMgr,
           [Parameter(Mandatory = $false)] [String] $ControllerIP)

    Install-Extension -Session $Session
    Install-DockerDriver -Session $Session
    Install-Agent -Session $Session
    Install-Utils -Session $Session

    if ($InstallNodeMgr -and $ControllerIP) {
        Install-Nodemgr -Session $Session
        New-NodeMgrConfigFile -Session $Session -ControllerIP $ControllerIP
    }
}

function Uninstall-Components {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $false)] [Switch] $UninstallNodeMgr)

    if ($UninstallNodeMgr) {
        Uninstall-Nodemgr -Session $Session
    }

    Uninstall-Utils -Session $Session
    Uninstall-Agent -Session $Session
    Uninstall-DockerDriver -Session $Session
    Uninstall-Extension -Session $Session
}
