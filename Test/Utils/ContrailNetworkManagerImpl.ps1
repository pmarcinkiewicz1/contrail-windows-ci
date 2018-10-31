. $PSScriptRoot\ContrailAPI\FloatingIP.ps1
. $PSScriptRoot\ContrailAPI\FloatingIPPool.ps1
. $PSScriptRoot\ContrailAPI\NetworkPolicy.ps1
. $PSScriptRoot\ContrailAPI\VirtualNetwork.ps1
. $PSScriptRoot\ContrailAPI\VirtualRouter.ps1
. $PSScriptRoot\ContrailUtils.ps1
. $PSScriptRoot\ContrailAPI\GlobalVrouterConfig.ps1

class ContrailNetworkManager {
    [Int] $CONVERT_TO_JSON_MAX_DEPTH = 100;

    [String] $AuthToken;
    [String] $ContrailUrl;
    [String] $DefaultTenantName;

    # We cannot add a type to the parameters,
    # because the class is parsed before the files are sourced.
    ContrailNetworkManager($OpenStackConfig, $ControllerConfig) {

        $this.ContrailUrl = $ControllerConfig.RestApiUrl()
        $this.DefaultTenantName = $ControllerConfig.DefaultProject

        $this.AuthToken = Get-AccessTokenFromKeystone `
            -AuthUrl $OpenStackConfig.AuthUrl() `
            -Username $OpenStackConfig.Username `
            -Password $OpenStackConfig.Password `
            -Tenant $OpenStackConfig.Project
    }

    [PSObject] GetResourceUrl([String] $Resource, [String] $Uuid) {
        $RequestUrl = $this.ContrailUrl + "/" + $Resource

        if(-not $Uuid) {
            $RequestUrl += "s"
        } else {
            $RequestUrl += ("/" + $Uuid)
        }

        return $RequestUrl
    }

    hidden [PSObject] SendRequest([String] $Method, [String] $Resource,
                                  [String] $Uuid, $Request) {
        $RequestUrl = $this.GetResourceUrl($Resource, $Uuid)

        return Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $this.AuthToken} `
            -Method $Method -ContentType "application/json" -Body (ConvertTo-Json -Depth $this.CONVERT_TO_JSON_MAX_DEPTH $Request)
    }

    [PSObject] Get([String] $Resource, [String] $Uuid, $Request) {
        return $this.SendRequest("Get", $Resource, $Uuid, $Request)
    }

    [PSObject] Post([String] $Resource, [String] $Uuid, $Request) {
        return $this.SendRequest("Post", $Resource, $Uuid, $Request)
    }

    [PSObject] Put([String] $Resource, [String] $Uuid, $Request) {
        return $this.SendRequest("Put", $Resource, $Uuid, $Request)
    }

    [PSObject] Delete([String] $Resource, [String] $Uuid, $Request) {
        return $this.SendRequest("Delete", $Resource, $Uuid, $Request)
    }

    [String] FQNameToUuid ([string] $Resource, [string[]] $FQName) {
        $Request = @{
            type     = $Resource
            fq_name  = $FQName
        }

        $RequestUrl = $this.ContrailUrl + "/fqname-to-id"
        $Response = Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $this.AuthToken} `
            -Method "Post" -ContentType "application/json" -Body (ConvertTo-Json -Depth $this.CONVERT_TO_JSON_MAX_DEPTH $Request)
        return $Response.'uuid'
    }

    [String] AddProject([String] $TenantName) {
        if (-not $TenantName) {
            $TenantName = $this.DefaultTenantName
        }

        return Add-ContrailProject `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -ProjectName $TenantName
    }

    EnsureProject([String] $TenantName) {
        if (-not $TenantName) {
            $TenantName = $this.DefaultTenantName
        }

        try {
            $this.AddProject($TenantName)
        }
        catch {
            if ($_.Exception.Response.StatusCode -ne [System.Net.HttpStatusCode]::Conflict) {
                throw
            }
        }
    }

    # TODO support multiple subnets per network
    # TODO return a class (perhaps use the class from MultiTenancy test?)
    # We cannot add a type to $SubnetConfig parameter,
    # because the class is parsed before the files are sourced.
    [String] AddOrReplaceNetwork([String] $TenantName, [String] $Name, $SubnetConfig) {
        if (-not $TenantName) {
            $TenantName = $this.DefaultTenantName
        }

        try {
            return Add-ContrailVirtualNetwork `
                -ContrailUrl $this.ContrailUrl `
                -AuthToken $this.AuthToken `
                -TenantName $TenantName `
                -NetworkName $Name `
                -SubnetConfig $SubnetConfig
        } catch {
            if ($_.Exception.Response.StatusCode -ne [System.Net.HttpStatusCode]::Conflict) {
                throw
            }

            $NetworkUuid = Get-ContrailVirtualNetworkUuidByName `
                -ContrailUrl $this.ContrailUrl `
                -AuthToken $this.AuthToken `
                -TenantName $TenantName `
                -NetworkName $Name

            $this.RemoveNetwork($NetworkUuid)

            return Add-ContrailVirtualNetwork `
                -ContrailUrl $this.ContrailUrl `
                -AuthToken $this.AuthToken `
                -TenantName $TenantName `
                -NetworkName $Name `
                -SubnetConfig $SubnetConfig
        }
    }

    RemoveNetwork([String] $Uuid) {
        Remove-ContrailVirtualNetwork `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -NetworkUuid $Uuid
    }

    [String] AddOrReplaceVirtualRouter([String] $RouterName, [String] $RouterIp) {
        try {
            return Add-ContrailVirtualRouter `
                -ContrailUrl $this.ContrailUrl `
                -AuthToken $this.AuthToken `
                -RouterName $RouterName `
                -RouterIp $RouterIp
        } catch {
            if ($_.Exception.Response.StatusCode -ne [System.Net.HttpStatusCode]::Conflict) {
                throw
            }

            $RouterUuid = Get-ContrailVirtualRouterUuidByName `
                -ContrailUrl $this.ContrailUrl `
                -AuthToken $this.AuthToken `
                -RouterName $RouterName

            $this.RemoveVirtualRouter($RouterUuid)

            return Add-ContrailVirtualRouter `
                -ContrailUrl $this.ContrailUrl `
                -AuthToken $this.AuthToken `
                -RouterName $RouterName `
                -RouterIp $RouterIp
        }
    }

    RemoveVirtualRouter([String] $RouterUuid) {
        Remove-ContrailVirtualRouter `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -RouterUuid $RouterUuid
    }

    SetEncapPriorities([String[]] $PrioritiesList) {
        # PrioritiesList is a list of (in any order) "MPLSoGRE", "MPLSoUDP", "VXLAN".
        Set-EncapPriorities `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -PrioritiesList $PrioritiesList
    }

    [String] AddFloatingIpPool([String] $TenantName, [String] $NetworkName, [String] $PoolName) {
        if (-not $TenantName) {
            $TenantName = $this.DefaultTenantName
        }

        return Add-ContrailFloatingIpPool `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -TenantName $TenantName `
            -NetworkName $NetworkName `
            -PoolName $PoolName
    }

    RemoveFloatingIpPool([String] $PoolUuid) {
        Remove-ContrailFloatingIpPool `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -PoolUuid $PoolUuid
    }

    [String] AddFloatingIp([String] $PoolUuid,
                           [String] $IPName,
                           [String] $IPAddress) {
        return Add-ContrailFloatingIp `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -PoolUuid $PoolUuid `
            -IPName $IPName `
            -IPAddress $IPAddress
    }

    AssignFloatingIpToAllPortsInNetwork([String] $IpUuid,
                                        [String] $NetworkUuid) {
        $PortFqNames = Get-ContrailVirtualNetworkPorts `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -NetworkUuid $NetworkUuid

        Set-ContrailFloatingIpPorts `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -IpUuid $IpUuid `
            -PortFqNames $PortFqNames
    }

    RemoveFloatingIp([String] $IpUuid) {
        Remove-ContrailFloatingIp `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -IpUuid $IpUuid
    }

    [String] AddPassAllPolicyOnDefaultTenant([String] $Name) {
        $TenantName = $this.DefaultTenantName

        return Add-ContrailPassAllPolicy `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -TenantName $TenantName `
            -Name $Name
    }

    RemovePolicy([String] $Uuid) {
        Remove-ContrailPolicy `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -Uuid $Uuid
    }

    AddPolicyToNetwork([String] $PolicyUuid,
                       [String] $NetworkUuid) {
        Add-ContrailPolicyToNetwork `
            -ContrailUrl $this.ContrailUrl `
            -AuthToken $this.AuthToken `
            -PolicyUuid $PolicyUuid `
            -NetworkUuid $NetworkUuid
    }
}
