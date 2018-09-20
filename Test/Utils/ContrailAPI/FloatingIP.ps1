. $PSScriptRoot\Constants.ps1

function Add-ContrailFloatingIp {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $PoolUuid,
           [Parameter(Mandatory = $true)] [string] $IPName,
           [Parameter(Mandatory = $true)] [string] $IPAddress)

    $PoolUrl = $ContrailUrl + "/floating-ip-pool/" + $PoolUuid
    $Pool = Invoke-RestMethod -Uri $PoolUrl -Headers @{"X-Auth-Token" = $AuthToken}

    $PoolFqName = $Pool."floating-ip-pool".fq_name
    $FipFqName = $PoolFqName + $IPName

    $Request = @{
        "floating-ip" = @{
            "floating_ip_address" = $IPAddress
            "fq_name" = $FipFqName
            "parent_type" = "floating-ip-pool"
            "uuid" = $null
        }
    }
    $RequestUrl = $ContrailUrl + "/floating-ips"
    $Response = Invoke-RestMethod `
        -Uri $RequestUrl `
        -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Post `
        -ContentType "application/json" `
        -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $Request)
    return $Response.'floating-ip'.'uuid'
}

function Remove-ContrailFloatingIp {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $IpUuid)

    $RequestUrl = $ContrailUrl + "/floating-ip/" + $IpUuid
    Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $AuthToken} -Method Delete | Out-Null
}

function Set-ContrailFloatingIpPorts {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $IpUuid,
           [Parameter(Mandatory = $true)] [string[]] $PortFqNames,
           [Parameter(Mandatory = $false)] [string] $TenantName)

    $FipUrl = $ContrailUrl + "/floating-ip/" + $IpUuid
    $Fip = Invoke-RestMethod -Uri $FipUrl -Headers @{"X-Auth-Token" = $AuthToken}

    $InterfaceRefs = @()
    foreach ($PortFqName in $PortFqNames) {
        $Ref = @{
            "to" = $PortFqName -Split ":"
        }
        $InterfaceRefs = $InterfaceRefs + $Ref
    }

    $RequestBody = @{
        "floating-ip" = @{
            "floating_ip_address" = $Fip.'floating-ip'.floating_ip_address
            "fq_name" = $Fip.'floating-ip'.fq_name
            "parent_type" = $Fip.'floating-ip'.parent_type
            "uuid" = $Fip.'floating-ip'.uuid
            "virtual_machine_interface_refs" = $InterfaceRefs
        }
    }
    Invoke-RestMethod `
        -Uri $FipUrl `
        -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Put `
        -ContentType "application/json" `
        -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $RequestBody)
}
