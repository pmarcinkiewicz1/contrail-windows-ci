. $PSScriptRoot\Constants.ps1

function Get-ContrailVirtualRouterUuidByName {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $RouterName)

    $RequestUrl = $ContrailUrl + "/virtual-routers"
    $Response = Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $AuthToken} -Method Get
    $Routers = $Response.'virtual-routers'

    $ExpectedFqname = @("default-global-system-config", $RouterName)
    foreach ($Router in $Routers) {
        $FqName = $Router.fq_name
        $AreFqNamesEqual = $null -eq $(Compare-Object $FqName $ExpectedFqname)

        if ($AreFqNamesEqual) {
            return $Router.uuid
        }
    }

    throw "Contrail virtual router with name '$($ExpectedFqname -join ":")' cannot be found."
}

function Add-ContrailVirtualRouter {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $RouterName,
           [Parameter(Mandatory = $true)] [string] $RouterIp)

    $Request = @{
        "virtual-router" = @{
            parent_type               = "global-system-config"
            fq_name                   = @("default-global-system-config", $RouterName)
            virtual_router_ip_address = $RouterIp
        }
    }

    $RequestUrl = $ContrailUrl + "/virtual-routers"
    $Response = Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Post -ContentType "application/json" -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $Request)

    return $Response.'virtual-router'.'uuid'
}

function Remove-ContrailVirtualRouter {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $RouterUuid)

    $RequestUrl = $ContrailUrl + "/virtual-router/" + $RouterUuid
    Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $AuthToken} -Method Delete | Out-Null
}
