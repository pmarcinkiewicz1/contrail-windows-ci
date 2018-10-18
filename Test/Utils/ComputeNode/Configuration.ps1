. $PSScriptRoot\..\..\..\CIScripts\Common\Init.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Invoke-CommandWithFunctions.ps1

. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testenv.ps1
. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testbed.ps1

. $PSScriptRoot\..\..\Utils\NetAdapterInfo\RemoteHost.ps1

function Get-DefaultCNMPluginsConfigPath {
    return "C:\ProgramData\Contrail\etc\contrail\contrail-cnm-plugin.conf"
}

function Get-DefaultAgentConfigPath {
    return "C:\ProgramData\Contrail\etc\contrail\contrail-vrouter-agent.conf"
}

function New-CNMPluginConfigFile {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [string] $AdapterName,
        [Parameter(Mandatory = $true)] [OpenStackConfig] $OpenStackConfig,
        [Parameter(Mandatory = $true)] [ControllerConfig] $ControllerConfig
    )
    $ConfigPath = Get-DefaultCNMPluginsConfigPath

    $Config = @"
[DRIVER]
Adapter=$AdapterName
ControllerIP=$( $ControllerConfig.Address )
ControllerPort=8082
AgentURL=http://127.0.0.1:9091
VSwitchName=Layered?<adapter>

[LOGGING]
LogLevel=Debug

[AUTH]
AuthMethod=$( $ControllerConfig.AuthMethod )

[KEYSTONE]
Os_auth_url=$( $OpenStackConfig.AuthUrl() )
Os_username=$( $OpenStackConfig.Username )
Os_tenant_name=$( $OpenStackConfig.Project )
Os_password=$( $OpenStackConfig.Password )
Os_token=
"@

    Invoke-Command -Session $Session -ScriptBlock {
        Set-Content -Path $Using:ConfigPath -Value $Using:Config
    }
}

function Get-DefaultNodeMgrsConfigPath {
    return "C:\ProgramData\Contrail\etc\contrail\contrail-vrouter-nodemgr.conf"
}


function Get-NodeManagementIP {
    Param([Parameter(Mandatory = $true)] [PSSessionT] $Session)
    return Invoke-Command -Session $Session -ScriptBlock { Get-NetIPAddress |
        Where-Object InterfaceAlias -like "Ethernet0*" | # TODO: this is hardcoded and bad.
        Where-Object AddressFamily -eq IPv4 |
        Select-Object -ExpandProperty IPAddress
    }
}

function New-NodeMgrConfigFile {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [string] $ControllerIP
    )

    $ConfigPath = Get-DefaultNodeMgrsConfigPath
    $LogPath = Join-Path (Get-ComputeLogsDir) "contrail-vrouter-nodemgr.log"

    $HostIP = Get-NodeManagementIP -Session $Session

    $Config = @"
[DEFAULTS]
log_local=1
log_level=SYS_DEBUG
log_file=$LogPath
hostip=$HostIP

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

function Get-AdaptersInfo {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig
    )
    # Gather information about testbed's network adapters
    $HNSTransparentAdapter = Get-RemoteNetAdapterInformation `
            -Session $Session `
            -AdapterName $SystemConfig.VHostName

    $PhysicalAdapter = Get-RemoteNetAdapterInformation `
            -Session $Session `
            -AdapterName $SystemConfig.AdapterName

    return @{
        "VHostIfName" = $HNSTransparentAdapter.ifName;
        "VHostIfIndex" = $HNSTransparentAdapter.ifIndex;
        "PhysIfName" = $PhysicalAdapter.ifName
    }
}

#Functions executed in the remote machine to create Agent's config file.
function Get-VHostConfiguration {
    Param (
        [Parameter(Mandatory = $true)] [string] $IfIndex
    )
    $IP = (Get-NetIPAddress -ifIndex $IfIndex -AddressFamily IPv4).IPAddress
    $PrefixLength = (Get-NetIPAddress -ifIndex $IfIndex -AddressFamily IPv4).PrefixLength
    $Gateway = (Get-NetIPConfiguration -InterfaceIndex $IfIndex).IPv4DefaultGateway
    $GatewayConfig = if ($Gateway) { "gateway=$( $Gateway.NextHop )" } else { "" }

    return @{
        "IP" = $IP;
        "PrefixLength" = $PrefixLength;
        "GatewayConfig" = $GatewayConfig
    }
}

function Get-AgentConfig {
    Param (
        [Parameter(Mandatory = $true)] [string] $ControllerIP,
        [Parameter(Mandatory = $true)] [string] $VHostIfName,
        [Parameter(Mandatory = $true)] [string] $VHostIfIndex,
        [Parameter(Mandatory = $true)] [string] $PhysIfName
    )
    $VHostConfguration = Get-VHostConfiguration -IfIndex $VHostIfIndex

    return @"
[DEFAULT]
platform=windows

[CONTROL-NODE]
servers=$ControllerIP

[DNS]
dns_client_port=53
servers=$($ControllerIP):53

[VIRTUAL-HOST-INTERFACE]
name=$VHostIfName
ip=$( $VHostConfguration.IP )/$( $VHostConfguration.PrefixLength )
$( $VHostConfguration.GatewayConfig )
physical_interface=$PhysIfName
"@
}

function New-AgentConfigFile {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [ControllerConfig] $ControllerConfig,
        [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig
    )
    $AdaptersInfo = Get-AdaptersInfo -Session $Session -SystemConfig $SystemConfig

    Invoke-CommandWithFunctions `
        -Functions @("Get-VHostConfiguration", "Get-AgentConfig") `
        -Session $Session `
        -ScriptBlock {
            # Save file with prepared config
            $ConfigFileContent = Get-AgentConfig `
                -ControllerIP $Using:ControllerConfig.Address `
                -VHostIfName $Using:AdaptersInfo.VHostIfName `
                -VHostIfIndex $Using:AdaptersInfo.VHostIfIndex `
                -PhysIfName $Using:AdaptersInfo.PhysIfName

            Set-Content -Path $Using:SystemConfig.AgentConfigFilePath -Value $ConfigFileContent
    }
}
