class OpenStackConfig {
    [string] $Username
    [string] $Password
    [string] $Project
    [string] $Address
    [int] $Port

    [string] AuthUrl() {
        return "http://$( $this.Address ):$( $this.Port )/v2.0"
    }
}

class ControllerConfig {
    [string] $Address
    [int] $RestApiPort
    [string] $DefaultProject
    [string] $AuthMethod

    [string] RestApiUrl() {
        return "http://$( $this.Address ):$( $this.RestApiPort )"
    }
}

class SystemConfig {
    [string] $AdapterName;
    [string] $VHostName;
    [string] $ForwardingExtensionName;
    [string] $AgentConfigFilePath;

    [string] VMSwitchName() {
        return "Layered " + $this.AdapterName
    }
}

class TestenvConfigs {
    [SystemConfig] $System;
    [OpenStackConfig] $OpenStack;
    [ControllerConfig] $Controller;

    TestenvConfigs([SystemConfig] $System,
                   [OpenStackConfig] $OpenStack,
                   [ControllerConfig] $Controller) {
        $this.System = $System;
        $this.OpenStack = $OpenStack;
        $this.Controller = $Controller;
    }
}

function Read-TestenvFile {
    Param ([Parameter(Mandatory=$true)] [string] $Path)
    if (-not (Test-Path $Path)) {
        throw [System.Management.Automation.ItemNotFoundException] "Testenv config file not found at specified location."
    }
    $FileContents = Get-Content -Path $Path -Raw
    $Parsed = ConvertFrom-Yaml $FileContents
    return $Parsed
}

function Read-OpenStackConfig {
    Param ([Parameter(Mandatory=$true)] [string] $Path)
    $Parsed = Read-TestenvFile -Path $Path
    return [OpenStackConfig] $Parsed.OpenStack
}

function Read-ControllerConfig {
    Param ([Parameter(Mandatory=$true)] [string] $Path)
    $Parsed = Read-TestenvFile -Path $Path
    return [ControllerConfig] $Parsed.Controller
}

function Read-SystemConfig {
    Param ([Parameter(Mandatory=$true)] [string] $Path)
    $Parsed = Read-TestenvFile -Path $Path
    return [SystemConfig] $Parsed.System
}

function Read-TestbedsConfig {
    Param ([Parameter(Mandatory=$true)] [string] $Path)
    $Parsed = Read-TestenvFile -Path $Path
    $Testbeds = $Parsed.Testbeds
    # The comma forces return value to always be array
    return ,$Testbeds
}
