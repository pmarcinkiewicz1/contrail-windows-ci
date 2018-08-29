Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(Mandatory=$false)] [string] $LogDir = "pesterLogs",
    [Parameter(ValueFromRemainingArguments=$true)] $UnusedParams
)

. $PSScriptRoot\..\..\..\CIScripts\Common\Invoke-UntilSucceeds.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Invoke-NativeCommand.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Init.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Aliases.ps1
. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testenv.ps1
. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testbed.ps1

. $PSScriptRoot\..\..\Utils\CommonTestCode.ps1
. $PSScriptRoot\..\..\Utils\ComponentsInstallation.ps1
. $PSScriptRoot\..\..\Utils\ContrailNetworkManager.ps1
. $PSScriptRoot\..\..\TestConfigurationUtils.ps1
. $PSScriptRoot\..\..\Utils\CommonTestCode.ps1
. $PSScriptRoot\..\..\PesterHelpers\PesterHelpers.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\PesterLogger\RemoteLogCollector.ps1

$ConfigPath = "C:\ProgramData\Contrail\etc\contrail\contrail-vrouter-nodemgr.conf"
$LogPath = Join-Path (Get-ComputeLogsDir) "contrail-vrouter-nodemgr.log"

function New-NodeMgrConfig {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [string] $ControllerIP
    )

    $HostIP = Get-NodeManagementIP -Session $Session

    $Config = @"
[DEFAULTS]
log_local = 1
log_level = SYS_DEBUG
log_file = $LogPath
hostip=$HostIP
db_port=9042
db_jmx_port=7200

[COLLECTOR]
server_list=${ControllerIP}:8086

[SANDESH]
introspect_ssl_enable=False
sandesh_ssl_enable=False
"@

    Invoke-Command -Session $Session -ScriptBlock {
        Set-Content -Path $Using:ConfigPath -Value $Using:Config
    }
}

function Clear-NodeMgrLogs {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )

    Invoke-Command -Session $Session -ScriptBlock {
        if (Test-Path -Path $Using:LogPath) {
            Remove-Item $Using:LogPath -Force
        }
    }
}

function Test-NodeMgrLogs {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )

    $Res = Invoke-Command -Session $Session -ScriptBlock {
        return Test-Path -Path $Using:LogPath
    }

    return $Res
}

function Test-NodeMgrConnectionWithController {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )

    $TestbedHostname = Invoke-Command -Session $Session -ScriptBlock {
        hostname
    }
    $Out = Invoke-RestMethod ("http://" + $ControllerConfig.Address + ":8089/Snh_ShowCollectorServerReq?")
    $OurNode = $Out.ShowCollectorServerResp.generators.list.GeneratorSummaryInfo.source | Where-Object "#text" -Like "$TestbedHostname"

    return [bool]($OurNode)
}

function Test-ControllerReceivesNodeStatus {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )

    # TODO

    return $true
}

function Start-NodeMgr {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )

    Invoke-Command -Session $Session -ScriptBlock {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseDeclaredVarsMoreThanAssignments", "",
        Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $NodeMgrJob = Start-Job -ScriptBlock {
            contrail-nodemgr --nodetype contrail-vrouter
        }
    }
}

function Stop-NodeMgr {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )

    Invoke-Command -Session $Session -ScriptBlock {
        if(Get-Variable "NodeMgrJob" -ErrorAction SilentlyContinue) {
            $NodeMgrJob | Stop-Job
            Remove-Variable "NodeMgrJob"
        }
    }
}

function Install-Components {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [string] $ControllerIP
    )

    Install-Extension -Session $Session
    Install-DockerDriver -Session $Session
    Install-Agent -Session $Session
    Install-Nodemgr -Session $Session
    New-NodeMgrConfig -Session $Session -ControllerIP $ControllerIP
}

function Uninstall-Components {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )

    Uninstall-Nodemgr -Session $Session
    Uninstall-Agent -Session $Session
    Uninstall-DockerDriver -Session $Session
    Uninstall-Extension -Session $Session
}

Describe "Node manager" {
    It "starts" {
        Eventually {
            Test-NodeMgrLogs -Session $Session | Should Be True
        } -Duration 60
    }

    It "connects to controller" {
        Eventually {
            Test-NodeMgrConnectionWithController -Session $Session | Should Be True
        } -Duration 60
    }

    It "sets node state as 'Up'" -Pending {
        Eventually {
            Test-ControllerReceivesNodeStatus -Session $Session | Should Be True
        } -Duration 60
    }

    BeforeEach {
        Initialize-ComputeServices -Session $Session `
            -SystemConfig $SystemConfig `
            -OpenStackConfig $OpenStackConfig `
            -ControllerConfig $ControllerConfig
        Clear-NodeMgrLogs -Session $Session
        Start-NodeMgr -Session $Session
    }

    AfterEach {
        try {
            Stop-NodeMgr -Session $Session
            Clear-TestConfiguration -Session $Session -SystemConfig $SystemConfig
        } finally {
            Merge-Logs -LogSources (New-FileLogSource -Path (Get-ComputeLogsPath) -Sessions $Session)
        }
    }

    BeforeAll {
        $VMs = Read-TestbedsConfig -Path $TestenvConfFile
        $Sessions = New-RemoteSessions -VMs $VMs
        $Session = $Sessions[0]

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $ControllerConfig = Read-ControllerConfig -Path $TestenvConfFile
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $OpenStackConfig = Read-OpenStackConfig -Path $TestenvConfFile
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $SystemConfig = Read-SystemConfig -Path $TestenvConfFile

        Initialize-PesterLogger -OutDir $LogDir

        Write-Log "Installing components on testbed..."
        Install-Components `
            -Session $Session `
            -ControllerIP $ControllerConfig.Address

        $ContrailNM = [ContrailNetworkManager]::new($OpenStackConfig, $ControllerConfig)
        $ContrailNM.EnsureProject($ControllerConfig.DefaultProject)

        $TestbedAddress = $VMs[0].Address
        $TestbedName = $VMs[0].Name
        Write-Log "Creating virtual router. Name: $TestbedName; Address: $TestbedAddress"
        $VRouterUuid = $ContrailNM.AddVirtualRouter($TestbedName, $TestbedAddress)
        Write-Log "Reported UUID of new virtual router: $VRouterUuid"
    }

    AfterAll {
        if (-not (Get-Variable Sessions -ErrorAction SilentlyContinue)) { return }

        if(Get-Variable "VRouterUuid" -ErrorAction SilentlyContinue) {
            Write-Log "Removing virtual router: $VRouterUuid"
            $ContrailNM.RemoveVirtualRouter($VRouterUuid)
            Remove-Variable "VRouterUuid"
        }

        Write-Log "Uninstalling components from testbed..."
        Uninstall-Components -Session $Session

        Remove-PSSession $Sessions
    }
}
