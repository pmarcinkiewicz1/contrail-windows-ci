. $PSScriptRoot\ContrailAPI\Constants.ps1

function Get-AccessTokenFromKeystone {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUserNameAndPassWordParams",
        "", Justification="We don't care that it's plaintext, it's just test env.")]
    Param ([Parameter(Mandatory = $true)] [string] $AuthUrl,
           [Parameter(Mandatory = $true)] [string] $TenantName,
           [Parameter(Mandatory = $true)] [string] $Username,
           [Parameter(Mandatory = $true)] [string] $Password)

    $Request = @{
        auth = @{
            tenantName          = $TenantName
            passwordCredentials = @{
                username = $Username
                password = $Password
            }
        }
    }

    $AuthUrl += "/tokens"
    $Response = Invoke-RestMethod -Uri $AuthUrl -Method Post -ContentType "application/json" `
        -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $Request)
    return $Response.access.token.id
}

function Add-ContrailProject {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $ProjectName)

    $Request = @{
        "project" = @{
            fq_name = @("default-domain", $ProjectName)
        }
    }

    $RequestUrl = $ContrailUrl + "/projects"
    $Response = Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Post -ContentType "application/json" -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $Request)

    return $Response.'project'.'uuid'
}
