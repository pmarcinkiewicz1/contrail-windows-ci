function FQNameToUuid {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $Type,
           [Parameter(Mandatory = $true)] [string[]] $FQName)

    $Request = @{
        type     = $Type
        fq_name  = $FQName
    }

    $FQToUuidUrl = $ContrailUrl + "/fqname-to-id"
    $Response = Invoke-RestMethod -Uri $FQToUuidUrl -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Post -ContentType "application/json" -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $Request)
    return $Response.'uuid'
}
