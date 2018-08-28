. $PSScriptRoot\Constants.ps1

function Set-EncapPriorities {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string[]] $PrioritiesList)

    $GetResponse = Invoke-RestMethod -Method GET -Uri ($ContrailUrl + "/global-vrouter-configs") `
        -Headers @{"X-Auth-Token" = $AuthToken}

    # Assume there's only one global-vrouter-config
    $Uuid = $GetResponse."global-vrouter-configs"[0].uuid

    # Request constructed based on
    # http://www.opencontrail.org/documentation/api/r4.0/contrail_openapi.html#globalvrouterconfigcreate
    $Request = @{
        "global-vrouter-config" = @{
            parent_type = "global-system-config"
            fq_name = @("default-global-system-config", "default-global-vrouter-config")
            encapsulation_priorities = @{
                encapsulation = $PrioritiesList
            }
        }
    }

    Invoke-RestMethod -Method PUT -Uri ($ContrailUrl + "/global-vrouter-config/$Uuid") `
        -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $Request) `
        -Headers @{"X-Auth-Token" = $AuthToken} `
        -ContentType "application/json" 
}
