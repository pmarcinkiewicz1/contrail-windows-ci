. $PSScriptRoot\Constants.ps1

function New-ContrailPassAllPolicyDefinition {
    Param ([Parameter(Mandatory = $true)] [string] $TenantName,
           [Parameter(Mandatory = $true)] [string] $Name)

    $Rule = @{
        "action_list" = @{ "simple_action" = "pass" }
        "direction" = "<>"
        "dst_addresses" = @(
            @{
                "network_policy" = $null
                "security_group" = $null
                "subnet" = $null
                "virtual_network" = "any"
            }
        )
        "dst_ports" = @(
            @{
                "end_port" = -1
                "start_port" = -1
            }
        )
        "ethertype" = "IPv4"
        "protocol" = "any"
        "rule_sequence" = @{
            "major" = -1
            "minor" = -1
        }
        "rule_uuid" = $null
        "src_addresses" = @(
            @{
                "network_policy" = $null
                "security_group" = $null
                "subnet" = $null
                "virtual_network" = "any"
            }
        )
        "src_ports" = @(
            @{
                "end_port" = -1
                "start_port" = -1
            }
        )
    }

    $BodyObject = @{
        "network-policy" = @{
            "fq_name" = @("default-domain", $TenantName, $Name)
            "name" = $Name
            "display_name" = $Name
            "network_policy_entries" = @{
                "policy_rule" = @( $Rule )
            }
        }
    }

    return $BodyObject
}

function Add-ContrailPassAllPolicy {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $TenantName,
           [Parameter(Mandatory = $true)] [string] $Name)

    $Url = $ContrailUrl + "/network-policys"
    $BodyObject = New-ContrailPassAllPolicyDefinition $TenantName $Name
    # We need to escape '<>' in 'direction' field because reasons
    # http://www.azurefieldnotes.com/2017/05/02/replacefix-unicode-characters-created-by-convertto-json-in-powershell-for-arm-templates/
    $Body = ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $BodyObject | ForEach-Object { [System.Text.RegularExpressions.Regex]::Unescape($_) }
    $Response = Invoke-RestMethod `
        -Uri $Url `
        -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Post `
        -ContentType "application/json" `
        -Body $Body
    return $Response.'network-policy'.'uuid'
}

function Remove-ContrailPolicy {
    Param ([Parameter(Mandatory = $true)] [string] $ContrailUrl,
           [Parameter(Mandatory = $true)] [string] $AuthToken,
           [Parameter(Mandatory = $true)] [string] $Uuid)

    $Url = $ContrailUrl + "/network-policy/" + $Uuid
    Invoke-RestMethod -Uri $Url -Headers @{"X-Auth-Token" = $AuthToken} -Method Delete | Out-Null
}
