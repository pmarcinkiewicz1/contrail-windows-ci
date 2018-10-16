. $PSScriptRoot\..\CIScripts\Common\Invoke-UntilSucceeds.ps1
. $PSScriptRoot\..\CIScripts\Common\Invoke-NativeCommand.ps1
. $PSScriptRoot\..\CIScripts\Common\Invoke-CommandWithFunctions.ps1
. $PSScriptRoot\..\CIScripts\Testenv\Testenv.ps1
. $PSScriptRoot\..\CIScripts\Testenv\Testbed.ps1

. $PSScriptRoot\Utils\ComputeNode\Configuration.ps1
. $PSScriptRoot\Utils\ComputeNode\Service.ps1
. $PSScriptRoot\Utils\DockerImageBuild.ps1
. $PSScriptRoot\PesterLogger\PesterLogger.ps1

$AGENT_EXECUTABLE_PATH = "C:/Program Files/Juniper Networks/agent/contrail-vrouter-agent.exe"

function Stop-ProcessIfExists {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $ProcessName)

    Invoke-Command -Session $Session -ScriptBlock {
        $Proc = Get-Process $Using:ProcessName -ErrorAction SilentlyContinue
        if ($Proc) {
            $Proc | Stop-Process -Force -PassThru | Wait-Process -ErrorAction SilentlyContinue
        }
    }
}

function Test-IsProcessRunning {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $ProcessName)

    $Proc = Invoke-Command -Session $Session -ScriptBlock {
        return $(Get-Process $Using:ProcessName -ErrorAction SilentlyContinue)
    }

    return [bool] $Proc
}

function Assert-AreDLLsPresent {
    Param (
        [Parameter(Mandatory=$true)] $ExitCode
    )
    #https://msdn.microsoft.com/en-us/library/cc704588.aspx
    #Value below is taken from the link above and it indicates
    #that application failed to load some DLL.
    $MissingDLLsErrorReturnCode = [int64]0xC0000135
    $System32Dir = "C:/Windows/System32"

    if ([int64]$ExitCode -eq $MissingDLLsErrorReturnCode) {
        $VisualDLLs = @("msvcp140d.dll", "ucrtbased.dll", "vcruntime140d.dll")
        $MissingVisualDLLs = @()

        foreach($DLL in $VisualDLLs) {
            if (-not (Test-Path $(Join-Path $System32Dir $DLL))) {
                $MissingVisualDLLs += $DLL
            }
        }

        if ($MissingVisualDLLs.count -ne 0) {
            throw "$MissingVisualDLLs must be present in $System32Dir"
        }
        else {
            throw "Some other not known DLL(s) couldn't be loaded"
        }
    }
}

function Enable-VRouterExtension {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig,
        [Parameter(Mandatory = $false)] [string] $ContainerNetworkName = "testnet"
    )

    Write-Log "Enabling Extension"

    $AdapterName = $SystemConfig.AdapterName
    $ForwardingExtensionName = $SystemConfig.ForwardingExtensionName
    $VMSwitchName = $SystemConfig.VMSwitchName()

    Wait-RemoteInterfaceIP -Session $Session -AdapterName $SystemConfig.AdapterName

    Invoke-Command -Session $Session -ScriptBlock {
        New-ContainerNetwork -Mode Transparent -NetworkAdapterName $Using:AdapterName -Name $Using:ContainerNetworkName | Out-Null
    }

    # We're not waiting for IP on this adapter, because our tests
    # don't rely on this adapter to have the correct IP set for correctess.
    # We could implement retrying to avoid flakiness but it's easier to just
    # ignore the error.
    # Wait-RemoteInterfaceIP -Session $Session -AdapterName $SystemConfig.VHostName

    Invoke-Command -Session $Session -ScriptBlock {
        $Extension = Get-VMSwitch | Get-VMSwitchExtension -Name $Using:ForwardingExtensionName | Where-Object Enabled
        if ($Extension) {
            Write-Warning "Extension already enabled on: $($Extension.SwitchName)"
        }
        $Extension = Enable-VMSwitchExtension -VMSwitchName $Using:VMSwitchName -Name $Using:ForwardingExtensionName
        if ((-not $Extension.Enabled) -or (-not ($Extension.Running))) {
            throw "Failed to enable extension (not enabled or not running)"
        }
    }
}

function Disable-VRouterExtension {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig
    )

    Write-Log "Disabling Extension"

    $AdapterName = $SystemConfig.AdapterName
    $ForwardingExtensionName = $SystemConfig.ForwardingExtensionName
    $VMSwitchName = $SystemConfig.VMSwitchName()

    Invoke-Command -Session $Session -ScriptBlock {
        Disable-VMSwitchExtension -VMSwitchName $Using:VMSwitchName -Name $Using:ForwardingExtensionName -ErrorAction SilentlyContinue | Out-Null
        Get-ContainerNetwork | Where-Object NetworkAdapterName -eq $Using:AdapterName | Remove-ContainerNetwork -ErrorAction SilentlyContinue -Force
        Get-ContainerNetwork | Where-Object NetworkAdapterName -eq $Using:AdapterName | Remove-ContainerNetwork -Force
    }
}

function Test-IsVRouterExtensionEnabled {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig
    )

    $ForwardingExtensionName = $SystemConfig.ForwardingExtensionName
    $VMSwitchName = $SystemConfig.VMSwitchName()

    $Ext = Invoke-Command -Session $Session -ScriptBlock {
        return $(Get-VMSwitchExtension -VMSwitchName $Using:VMSwitchName -Name $Using:ForwardingExtensionName -ErrorAction SilentlyContinue)
    }

    return $($Ext.Enabled -and $Ext.Running)
}

function Test-IsDockerDriverEnabled {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    function Test-IsDockerDriverListening {
        return Invoke-Command -Session $Session -ScriptBlock {
            return Test-Path //./pipe/Contrail
        }
    }

    function Test-IsDockerPluginRegistered {
        return Invoke-Command -Session $Session -ScriptBlock {
            return Test-Path $Env:ProgramData/docker/plugins/Contrail.spec
        }
    }

    return (Test-IsDockerDriverListening) -And `
        (Test-IsDockerPluginRegistered)
}

function Test-IfUtilsCanLoadDLLs {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )
    $Utils = @(
        "vif.exe",
        "nh.exe",
        "rt.exe",
        "flow.exe"
    )
    Invoke-CommandWithFunctions `
        -Session $Session `
        -Functions "Assert-AreDLLsPresent" `
        -ScriptBlock {
            foreach ($Util in $using:Utils) {
                & $Util 2>&1 | Out-Null
                Assert-AreDLLsPresent -ExitCode $LastExitCode
            }
    }
}

function Test-IfAgentCanLoadDLLs {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )
    Invoke-CommandWithFunctions `
        -Session $Session `
        -Functions "Assert-AreDLLsPresent" `
        -ScriptBlock {
            & $using:AGENT_EXECUTABLE_PATH --version 2>&1 | Out-Null
            Assert-AreDLLsPresent -ExitCode $LastExitCode
    }
}

function Read-SyslogForAgentCrash {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [DateTime] $After)
    Invoke-Command -Session $Session -ScriptBlock {
        Get-EventLog -LogName "System" -EntryType "Error" `
            -Source "Service Control Manager" `
            -Message "The contrail-vrouter-agent service terminated unexpectedly*" `
            -After ($Using:After).addSeconds(-1)
    }
}

function New-DockerNetwork {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $Name,
           [Parameter(Mandatory = $true)] [string] $TenantName,
           [Parameter(Mandatory = $false)] [string] $Network,
           [Parameter(Mandatory = $false)] [string] $Subnet)

    if (!$Network) {
        $Network = $Name
    }

    Write-Log "Creating network $Name"

    $NetworkID = Invoke-Command -Session $Session -ScriptBlock {
        if ($Using:Subnet) {
            return $(docker network create --ipam-driver windows --driver Contrail -o tenant=$Using:TenantName -o network=$Using:Network --subnet $Using:Subnet $Using:Name)
        }
        else {
            return $(docker network create --ipam-driver windows --driver Contrail -o tenant=$Using:TenantName -o network=$Using:Network $Using:Name)
        }
    }

    return $NetworkID
}

function Remove-AllUnusedDockerNetworks {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Removing all docker networks"

    Invoke-Command -Session $Session -ScriptBlock {
        docker network prune --force | Out-Null
    }
}

function Select-ValidNetIPInterface {
    Param ([parameter(Mandatory=$true, ValueFromPipeline=$true)]$GetIPAddressOutput)

    Process { $_ `
        | Where-Object AddressFamily -eq "IPv4" `
        | Where-Object { ($_.SuffixOrigin -eq "Dhcp") -or ($_.SuffixOrigin -eq "Manual") }
    }
}

function Wait-RemoteInterfaceIP {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [String] $AdapterName)

    Invoke-UntilSucceeds -Name "Waiting for IP on interface $AdapterName" -Duration 60 {
        Invoke-CommandWithFunctions -Functions "Select-ValidNetIPInterface" -Session $Session {
            Get-NetAdapter -Name $Using:AdapterName `
            | Get-NetIPAddress -ErrorAction SilentlyContinue `
            | Select-ValidNetIPInterface
        }
    } | Out-Null
}

# Before running this function make sure CNM-Plugin config file is created.
# It can be done by function New-CNMPluginConfigFile.
function Initialize-DriverAndExtension {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig
    )

    Write-Log "Initializing CNMPlugin and Extension"

    $NRetries = 3;
    foreach ($i in 1..$NRetries) {
        Wait-RemoteInterfaceIP -Session $Session -AdapterName $SystemConfig.AdapterName

        # CNMPlugin automatically enables Extension
        Start-CNMPluginService -Session $Session

        try {
            $TestCNMRunning = { Test-IsCNMPluginServiceRunning -Session $Session }

            $TestCNMRunning | Invoke-UntilSucceeds -Duration 15

            {
                if (-not (Invoke-Command $TestCNMRunning)) {
                    throw [HardError]::new("CNM plugin service didn't start")
                }
                Test-IsDockerDriverEnabled -Session $Session
            } | Invoke-UntilSucceeds -Duration 600 -Interval 5

            Wait-RemoteInterfaceIP -Session $Session -AdapterName $SystemConfig.VHostName

            break
        }
        catch {
            Write-Log $_

            if ($i -eq $NRetries) {
                throw "CNM plugin was not enabled."
            } else {
                Write-Log "CNM plugin was not enabled, retrying."
                Clear-TestConfiguration -Session $Session -SystemConfig $SystemConfig
            }
        }
    }
}

function Clear-TestConfiguration {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig)

    Write-Log "Cleaning up test configuration"

    Write-Log "Agent service status: $( Get-AgentServiceStatus -Session $Session )"
    Write-Log "CNMPlugin service status: $( Get-CNMPluginServiceStatus -Session $Session )"

    Remove-AllUnusedDockerNetworks -Session $Session
    Stop-CNMPluginService -Session $Session
    Stop-AgentService -Session $Session
    Disable-VRouterExtension -Session $Session -SystemConfig $SystemConfig

    Wait-RemoteInterfaceIP -Session $Session -AdapterName $SystemConfig.AdapterName
}

function Initialize-ComputeServices {
        Param (
            [Parameter(Mandatory = $true)] [PSSessionT] $Session,
            [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig,
            [Parameter(Mandatory = $true)] [OpenStackConfig] $OpenStackConfig,
            [Parameter(Mandatory = $true)] [ControllerConfig] $ControllerConfig
        )
        New-CNMPluginConfigFile -Session $Session `
            -AdapterName $SystemConfig.AdapterName `
            -OpenStackConfig $OpenStackConfig `
            -ControllerConfig $ControllerConfig

        Initialize-DriverAndExtension -Session $Session `
            -SystemConfig $SystemConfig

        New-AgentConfigFile -Session $Session `
            -ControllerConfig $ControllerConfig `
            -SystemConfig $SystemConfig

        Start-AgentService -Session $Session
}

function Remove-DockerNetwork {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [string] $Name
    )

    Invoke-Command -Session $Session -ScriptBlock {
        docker network rm $Using:Name | Out-Null
    }
}

function New-Container {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $NetworkName,
           [Parameter(Mandatory = $false)] [string] $Name,
           [Parameter(Mandatory = $false)] [string] $Image = "microsoft/nanoserver")

    if (Test-Dockerfile $Image) {
        Initialize-DockerImage -Session $Session -DockerImageName $Image | Out-Null
    }

    $Arguments = "run", "-di"
    if ($Name) { $Arguments += "--name", $Name }
    $Arguments += "--network", $NetworkName, $Image

    $Result = Invoke-NativeCommand -Session $Session -CaptureOutput -AllowNonZero { docker @Using:Arguments }
    $ContainerID = $Result.Output[0]
    $OutputMessages = $Result.Output

    # Workaround for occasional failures of container creation in Docker for Windows.
    # In such a case Docker reports: "CreateContainer: failure in a Windows system call",
    # container is created (enters CREATED state), but is not started and can not be
    # started manually. It's possible to delete a faulty container and start it again.
    # We want to capture just this specific issue here not to miss any new problem.
    if ($Result.Output -match "CreateContainer: failure in a Windows system call") {
        Write-Log "Container creation failed with the following output: $OutputMessages"
        Write-Log "Removing incorrectly created container (if exists)..."
        Invoke-NativeCommand -Session $Session -AllowNonZero { docker rm -f $Using:ContainerID } | Out-Null
        Write-Log "Retrying container creation..."
        $ContainerID = Invoke-Command -Session $Session { docker @Using:Arguments }
    } elseif ($Result.ExitCode -ne 0) {
        throw "New-Container failed with the following output: $OutputMessages"
    }

    return $ContainerID
}

function Remove-Container {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $false)] [string] $NameOrId)

    Invoke-Command -Session $Session -ScriptBlock {
        docker rm -f $Using:NameOrId | Out-Null
    }
}

function Remove-AllContainers {
    Param ([Parameter(Mandatory = $true)] [PSSessionT[]] $Sessions)

    foreach ($Session in $Sessions) {
        $Result = Invoke-NativeCommand -Session $Session -CaptureOutput -AllowNonZero {
            $Containers = docker ps -aq
            $MaxAttempts = 3
            $TimesToGo = $MaxAttempts
            while ( $Containers -and $TimesToGo -gt 0 ) {
                if($Containers) {
                    $Command = "docker rm -f $Containers"
                    Invoke-Expression -Command $Command
                }
                $Containers = docker ps -aq
                $TimesToGo = $TimesToGo - 1
                if ( $Containers -and $TimesToGo -eq 0 ) {
                    $LASTEXITCODE = 1
                }
            }
            Remove-Variable "Containers"
            return $MaxAttempts - $TimesToGo - 1
        }

        $OutputMessages = $Result.Output
        if ($Result.ExitCode -ne 0) {
            throw "Remove-AllContainers - removing containers failed with the following messages: $OutputMessages"
        } elseif ($Result.Output[-1] -gt 0) {
            Write-Host "Remove-AllContainers - removing containers was successful, but required more than one attempt: $OutputMessages"
        }
    }
}
