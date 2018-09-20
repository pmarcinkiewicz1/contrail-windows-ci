. $PSScriptRoot\Constants.ps1

function Add-ContrailFloatingIpPool {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $TenantName,
           [Parameter(Mandatory = $true)] [string] $NetworkName,
           [Parameter(Mandatory = $true)] [string] $PoolName)

    $Request = @{
        "floating-ip-pool" = @{
            "fq_name" = @("default-domain", $TenantName, $NetworkName, $PoolName)
            "parent_type" = "virtual-network"
            "uuid" = $null
        }
    }

    $RequestUrl = $ContrailUrl + "/floating-ip-pools"
    $Response = Invoke-RestMethod `
        -Uri $RequestUrl `
        -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Post `
        -ContentType "application/json" `
        -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $Request)

    return $Response.'floating-ip-pool'.'uuid'
}

function Remove-ContrailFloatingIpPool {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $PoolUuid)

    $RequestUrl = $ContrailUrl + "/floating-ip-pool/" + $PoolUuid
    Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $AuthToken} -Method Delete | Out-Null
}
