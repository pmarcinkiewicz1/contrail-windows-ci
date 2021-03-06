. $PSScriptRoot\..\DockerNetwork\DockerNetwork.ps1
. $PSScriptRoot\Constants.ps1

function Get-ContrailVirtualNetworkUuidByName {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $TenantName,
           [Parameter(Mandatory = $true)] [string] $NetworkName)

    $RequestUrl = $ContrailUrl + "/virtual-networks"
    $Response = Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $AuthToken} -Method Get
    $Networks = $Response.'virtual-networks'

    $ExpectedFqName = @("default-domain", $TenantName, $NetworkName)
    foreach ($Network in $Networks) {
        $FqName = $Network.fq_name
        $AreFqNamesEqual = $null -eq $(Compare-Object $FqName $ExpectedFqName)

        if ($AreFqNamesEqual) {
            return $Network.uuid
        }
    }

    throw "Contrail virtual network with name '$($ExpectedFqname -join ":")' cannot be found."
}

function Add-ContrailVirtualNetwork {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $TenantName,
           [Parameter(Mandatory = $true)] [string] $NetworkName,
           [SubnetConfiguration] $SubnetConfig = [SubnetConfiguration]::new("10.0.0.0", 24, "10.0.0.1", "10.0.0.100", "10.0.0.200"))

    $Subnet = @{
        subnet           = @{
            ip_prefix     = $SubnetConfig.IpPrefix
            ip_prefix_len = $SubnetConfig.IpPrefixLen
        }
        addr_from_start  = $true
        enable_dhcp      = $true
        default_gateway  = $SubnetConfig.DefaultGateway
        allocation_pools = @(@{
                start = $SubnetConfig.AllocationPoolsStart
                end   = $SubnetConfig.AllocationPoolsEnd
            })
    }

    $NetworkImap = @{
        attr = @{
            ipam_subnets = @($Subnet)
        }
        to   = @("default-domain", "default-project", "default-network-ipam")
    }

    $Request = @{
        "virtual-network" = @{
            parent_type       = "project"
            fq_name           = @("default-domain", $TenantName, $NetworkName)
            network_ipam_refs = @($NetworkImap)
        }
    }

    $RequestUrl = $ContrailUrl + "/virtual-networks"
    $Response = Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Post -ContentType "application/json" -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $Request)

    return $Response.'virtual-network'.'uuid'
}

function Remove-ContrailVirtualNetwork {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $NetworkUuid,
           [bool] $Force = $false)

    $NetworkUrl = $ContrailUrl + "/virtual-network/" + $NetworkUuid
    $Network = Invoke-RestMethod -Method Get -Uri $NetworkUrl -Headers @{"X-Auth-Token" = $AuthToken}

    if ($Force) {
        # TODO remove this outer if, this is only a quick workaround,
        # because sometimes the fields below are empty,
        # and that's a failure in strict mode (I guess).
        $VirtualMachines = $Network.'virtual-network'.virtual_machine_interface_back_refs
        $IpInstances = $Network.'virtual-network'.instance_ip_back_refs

        if ($VirtualMachines -or $IpInstances) {
            if (!$Force) {
                Write-Error "Couldn't remove network. Resources are still referred. Use force mode"
                return
            }

            # First we have to remove resources referred by network instance in correct order:
            #   - Instance IPs
            #   - Virtual machines
            ForEach ($IpInstance in $IpInstances) {
                Invoke-RestMethod -Uri $IpInstance.href -Headers @{"X-Auth-Token" = $AuthToken} -Method Delete | Out-Null
            }

            ForEach ($VirtualMachine in $VirtualMachines) {
                Invoke-RestMethod -Uri $VirtualMachine.href -Headers @{"X-Auth-Token" = $AuthToken} -Method Delete | Out-Null
            }
        }
    }

    # We can now remove the network
    Invoke-RestMethod -Uri $NetworkUrl -Headers @{"X-Auth-Token" = $AuthToken} -Method Delete | Out-Null
}

function Get-ContrailVirtualNetworkPorts {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $NetworkUuid)

    $VirtualNetworkUrl = $ContrailUrl + "/virtual-network/" + $NetworkUuid
    $VirtualNetwork = Invoke-RestMethod -Uri $VirtualNetworkUrl -Headers @{"X-Auth-Token" = $AuthToken}
    $Interfaces = $VirtualNetwork.'virtual-network'.virtual_machine_interface_back_refs

    $Result = @()
    foreach ($Interface in $Interfaces) {
        $FqName = $Interface.to -Join ":"
        $Result = $Result + $FqName
    }

    return $Result
}

function Add-ContrailPolicyToNetwork {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $PolicyUuid,
           [Parameter(Mandatory = $true)] [string] $NetworkUuid)
    $PolicyRef = @{
        "uuid" = $PolicyUuid
        "attr" = @{
            "timer" = $null
            "sequence" = @{
                "major" = 0
                "minor" = 0
            }
        }
    }
    $BodyObject = @{
        "virtual-network" = @{
            "uuid" = $NetworkUuid
            "network_policy_refs" = @( $PolicyRef )
        }
    }

    $NetworkUrl = $ContrailUrl + "/virtual-network/" + $NetworkUuid
    $Body = ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $BodyObject
    Invoke-RestMethod `
        -Uri $NetworkUrl `
        -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Put `
        -ContentType "application/json" `
        -Body $Body | Out-Null
}
