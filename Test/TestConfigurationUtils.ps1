. $PSScriptRoot\..\CIScripts\Common\Invoke-UntilSucceeds.ps1
. $PSScriptRoot\..\CIScripts\Common\Invoke-NativeCommand.ps1
. $PSScriptRoot\..\CIScripts\Testenv\Testenv.ps1
. $PSScriptRoot\..\CIScripts\Testenv\Testbed.ps1

. $PSScriptRoot\Utils\CommonTestCode.ps1
. $PSScriptRoot\Utils\DockerImageBuild.ps1
. $PSScriptRoot\PesterLogger\PesterLogger.ps1

$MAX_WAIT_TIME_FOR_AGENT_IN_SECONDS = 60
$TIME_BETWEEN_AGENT_CHECKS_IN_SECONDS = 2

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

function Start-DockerDriver {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $AdapterName,
           [Parameter(Mandatory = $true)] [OpenStackConfig] $OpenStackConfig,
           [Parameter(Mandatory = $true)] [ControllerConfig] $ControllerConfig,
           [Parameter(Mandatory = $false)] [int] $WaitTime = 60)

    Write-Log "Starting Docker Driver"

    # We have to specify some file, because docker driver doesn't
    # currently support stderr-only logging.
    # TODO: Remove this when after "no log file" option is supported.
    $OldLogPath = "NUL"

    $LogDir = Get-ComputeLogsDir

    $Arguments = @(
        "-forceAsInteractive",
        "-controllerIP", $ControllerConfig.Address,
        "-os_username", $OpenStackConfig.Username,
        "-os_password", $OpenStackConfig.Password,
        "-os_auth_url", $OpenStackConfig.AuthUrl(),
        "-os_tenant_name", $OpenStackConfig.Project,
        "-adapter", $AdapterName,
        "-vswitchName", "Layered <adapter>",
        "-logPath", $OldLogPath,
        "-logLevel", "Debug"
    )

    Invoke-Command -Session $Session -ScriptBlock {

        # Nested ScriptBlock variable passing workaround
        $Arguments = $Using:Arguments
        $LogDir = $Using:LogDir

        Start-Job -ScriptBlock {
            Param($Arguments, $LogDir)

            New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
            $LogPath = Join-Path $LogDir "contrail-windows-docker-driver.log"
            $ErrorActionPreference = "Continue"

            & "C:\Program Files\Juniper Networks\contrail-windows-docker.exe" $Arguments 2>&1 |
                Add-Content -NoNewline $LogPath
        } -ArgumentList $Arguments, $LogDir
    }

    Start-Sleep -s $WaitTime
}

function Stop-DockerDriver {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Stopping Docker Driver"

    Stop-ProcessIfExists -Session $Session -ProcessName "contrail-windows-docker"

    Invoke-Command -Session $Session -ScriptBlock {
        Stop-Service docker | Out-Null
        Get-NetNat | Remove-NetNat -Confirm:$false
        Get-ContainerNetwork | Remove-ContainerNetwork -ErrorAction SilentlyContinue -Force
        Get-ContainerNetwork | Remove-ContainerNetwork -Force
        Start-Service docker | Out-Null
    }
}

function Test-IsDockerDriverProcessRunning {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    return Test-IsProcessRunning -Session $Session -ProcessName "contrail-windows-docker"
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

function Enable-AgentService {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Starting Agent"
    Invoke-Command -Session $Session -ScriptBlock {
        Start-Service ContrailAgent | Out-Null
    }
}

function Disable-AgentService {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Stopping Agent"
    Invoke-Command -Session $Session -ScriptBlock {
        Stop-Service ContrailAgent -ErrorAction SilentlyContinue | Out-Null
    }
}

function Get-AgentServiceStatus {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $Service = Get-Service "ContrailAgent" -ErrorAction SilentlyContinue

        if ($Service -and $Service.Status) {
            return $Service.Status.ToString()
        } else {
            return $null
        }
    }
}

function Assert-IsAgentServiceEnabled {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)
    $Status = Invoke-UntilSucceeds { Get-AgentServiceStatus -Session $Session } `
            -Interval $TIME_BETWEEN_AGENT_CHECKS_IN_SECONDS `
            -Duration $MAX_WAIT_TIME_FOR_AGENT_IN_SECONDS
    if ($Status -eq "Running") {
        return
    } else {
        throw "Agent service is not enabled. EXPECTED: Agent service is enabled"
    }
}

function Assert-IsAgentServiceDisabled {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)
    $Status = Invoke-UntilSucceeds { Get-AgentServiceStatus -Session $Session } `
            -Interval $TIME_BETWEEN_AGENT_CHECKS_IN_SECONDS `
            -Duration $MAX_WAIT_TIME_FOR_AGENT_IN_SECONDS
    if ($Status -eq "Stopped") {
        return
    } else {
        throw "Agent service is not disabled. EXPECTED: Agent service is disabled"
    }
}

function Read-SyslogForAgentCrash {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [DateTime] $After)
    Invoke-Command -Session $Session -ScriptBlock {
        Get-EventLog -LogName "System" -EntryType "Error" `
            -Source "Service Control Manager" `
            -Message "The ContrailAgent service terminated unexpectedly*" `
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
    $InjectedFunction = [PSCustomObject] @{ 
        Name = 'Select-ValidNetIPInterface'; 
        Body = ${Function:Select-ValidNetIPInterface} 
    }

    Invoke-UntilSucceeds -Name "Waiting for IP on interface $AdapterName" -Duration 60 {
        Invoke-Command -Session $Session {
            $Using:InjectedFunction | ForEach-Object { Invoke-Expression "function $( $_.Name ) { $( $_.Body ) }" }

            Get-NetAdapter -Name $Using:AdapterName `
            | Get-NetIPAddress -ErrorAction SilentlyContinue `
            | Select-ValidNetIPInterface
        }
    } | Out-Null
}

function Initialize-DriverAndExtension {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig,
        [Parameter(Mandatory = $true)] [OpenStackConfig] $OpenStackConfig,
        [Parameter(Mandatory = $true)] [ControllerConfig] $ControllerConfig
    )

    Write-Log "Initializing Test Configuration"

    $NRetries = 3;
    foreach ($i in 1..$NRetries) {
        Wait-RemoteInterfaceIP -Session $Session -AdapterName $SystemConfig.AdapterName

        # DockerDriver automatically enables Extension
        Start-DockerDriver -Session $Session `
            -AdapterName $SystemConfig.AdapterName `
            -OpenStackConfig $OpenStackConfig `
            -ControllerConfig $ControllerConfig `
            -WaitTime 0

        try {
            $TestProcessRunning = { Test-IsDockerDriverProcessRunning -Session $Session }

            $TestProcessRunning | Invoke-UntilSucceeds -Duration 15

            {
                Test-IsDockerDriverEnabled -Session $Session
            } | Invoke-UntilSucceeds -Duration 600 -Interval 5 -Precondition $TestProcessRunning

            Wait-RemoteInterfaceIP -Session $Session -AdapterName $SystemConfig.VHostName

            break
        }
        catch {
            Write-Log $_

            if ($i -eq $NRetries) {
                throw "Docker driver was not enabled."
            } else {
                Write-Log "Docker driver was not enabled, retrying."
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
    Write-Log "Docker Driver status: $( Test-IsDockerDriverProcessRunning -Session $Session )"

    Remove-AllUnusedDockerNetworks -Session $Session
    Disable-AgentService -Session $Session
    Stop-DockerDriver -Session $Session
    Disable-VRouterExtension -Session $Session -SystemConfig $SystemConfig

    Wait-RemoteInterfaceIP -Session $Session -AdapterName $SystemConfig.AdapterName
}

function New-AgentConfigFile {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [ControllerConfig] $ControllerConfig,
        [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig
    )

    # Gather information about testbed's network adapters
    $HNSTransparentAdapter = Get-RemoteNetAdapterInformation `
            -Session $Session `
            -AdapterName $SystemConfig.VHostName

    $PhysicalAdapter = Get-RemoteNetAdapterInformation `
            -Session $Session `
            -AdapterName $SystemConfig.AdapterName

    # Prepare parameters for script block
    $ControllerIP = $ControllerConfig.Address
    $VHostIfName = $HNSTransparentAdapter.ifName
    $VHostIfIndex = $HNSTransparentAdapter.ifIndex
    $PhysIfName = $PhysicalAdapter.ifName

    $AgentConfigFilePath = $SystemConfig.AgentConfigFilePath

    Invoke-Command -Session $Session -ScriptBlock {
        $ControllerIP = $Using:ControllerIP
        $VHostIfName = $Using:VHostIfName
        $VHostIfIndex = $Using:VHostIfIndex
        $PhysIfName = $Using:PhysIfName

        $VHostIP = (Get-NetIPAddress -ifIndex $VHostIfIndex -AddressFamily IPv4).IPAddress
        $PrefixLength = (Get-NetIPAddress -ifIndex $VHostIfIndex -AddressFamily IPv4).PrefixLength

        $ConfigFileContent = @"
[DEFAULT]
platform=windows

[CONTROL-NODE]
servers=$ControllerIP

[VIRTUAL-HOST-INTERFACE]
name=$VHostIfName
ip=$VHostIP/$PrefixLength
physical_interface=$PhysIfName
"@

        # Save file with prepared config
        [System.IO.File]::WriteAllText($Using:AgentConfigFilePath, $ConfigFileContent)
    }
}

function Initialize-ComputeServices {
        Param (
            [Parameter(Mandatory = $true)] [PSSessionT] $Session,
            [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig,
            [Parameter(Mandatory = $true)] [OpenStackConfig] $OpenStackConfig,
            [Parameter(Mandatory = $true)] [ControllerConfig] $ControllerConfig
        )

        Initialize-DriverAndExtension -Session $Session `
            -SystemConfig $SystemConfig `
            -OpenStackConfig $OpenStackConfig `
            -ControllerConfig $ControllerConfig

        New-AgentConfigFile -Session $Session `
            -ControllerConfig $ControllerConfig `
            -SystemConfig $SystemConfig

        Enable-AgentService -Session $Session
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
