. $PSScriptRoot\Constants.ps1
. $PSScriptRoot\Global.ps1
. $PSScriptRoot\VirtualDNSData.ps1
. $PSScriptRoot\VirtualDNSRecordData.ps1

function Add-TenantDNSInformation {
    Param (
        [Parameter(Mandatory = $false)] [string[]] $TenantServersIPAddresses = @(),
        [Parameter(Mandatory = $true)] $Request
    )
    $DNSServer = @{
        "ipam_dns_server" = @{
            "tenant_dns_server_address" = @{
                "ip_address" = $TenantServersIPAddresses
            }
        }
    }

    $Request."network-ipam"."network_ipam_mgmt" += $DNSServer

    return $Request
}

function Add-VirtualDNSInformation {
    Param (
        [Parameter(Mandatory = $false)] [string[]] $VirtualServerFQName,
        [Parameter(Mandatory = $false)] [string] $VirtualServerUuid,
        [Parameter(Mandatory = $false)] [string] $VirtualServerUrl,
        [Parameter(Mandatory = $true)] $Request
    )

    $DNSServer = @{
        "ipam_dns_server" = @{
            "virtual_dns_server_name" = [string]::Join(":",$VirtualServerFQName)
        }
    }
    $Request."network-ipam"."network_ipam_mgmt" += $DNSServer

    $VirtualServerRef = @{
        "href" = $VirtualServerUrl
        "uuid" = $VirtualServerUuid
        "to"   = $VirtualServerFQName

    }

    $Request."network-ipam"."virtual_DNS_refs" = @($VirtualServerRef)

    return $Request
}

function Set-IpamDNSMode {
    Param (
        [Parameter(Mandatory = $true)] [string] $ContrailUrl,
        [Parameter(Mandatory = $true)] [string] $AuthToken,
        [Parameter(Mandatory = $true)] [string[]] $IpamFQName,
        [Parameter(Mandatory = $true)]
            [ValidateSet("none","default-dns-server","tenant-dns-server","virtual-dns-server")]
            [string] $DNSMode,
        [Parameter(Mandatory = $false)] [string[]] $TenantServersIPAddresses = @(),
        [Parameter(Mandatory = $false)] [string] $VirtualServerName
    )

    $Request = @{
        "network-ipam" = @{
            "network_ipam_mgmt" = @{"ipam_dns_method" = $DNSMode}
            "virtual_DNS_refs"  = @()
        }
    }

    if ($DNSMode -ceq 'tenant-dns-server')     {
        Add-TenantDNSInformation -TenantServersIPAddresses $TenantServersIPAddresses -Request $Request
    }
    elseif ($DNSMode -ceq 'virtual-dns-server')     {
        if(-not $VirtualServerName) {
            throw "You need to specify Virtual DNS Server to be used"
        }

        $VirtualServerFQName = @("default-domain", $VirtualServerName)
        $VirtualServerUuid = FQNameToUuid -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
            -Type 'virtual-DNS' -FQName $VirtualServerFQName
        $VirtualServerUrl = $ContrailUrl + "/virtual-DNS/" + $VirtualServerUuid

        Add-VirtualDNSInformation -VirtualServerFQName $VirtualServerFQName -VirtualServerUuid $VirtualServerUuid `
            -VirtualServerUrl $VirtualServerUrl -Request $Request

    }


    $IpamUuid = FQNameToUuid -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
        -Type 'network-ipam' -FQName $IpamFQName
    $RequestUrl = $ContrailUrl + "/network-ipam/" + $IpamUuid
    $Response = Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Put -ContentType "application/json" -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $Request)

    return $Response.'network-ipam'.'uuid'
}

function Add-ContrailDNSRecord {
    Param (
        [Parameter(Mandatory = $true)] [string] $ContrailUrl,
        [Parameter(Mandatory = $true)] [string] $AuthToken,
        [Parameter(Mandatory = $true)] [string] $DNSServerName,
        [Parameter(Mandatory = $true)] [VirtualDNSRecordData] $VirtualDNSRecordData
    )

    $VirtualDNSRecord = @{
        record_name         = $VirtualDNSRecordData.RecordName
        record_type         = $VirtualDNSRecordData.RecordType
        record_class        = $VirtualDNSRecordData.RecordClass
        record_data         = $VirtualDNSRecordData.RecordData
        record_ttl_seconds  = $VirtualDNSRecordData.RecordTTLInSeconds
    }

    $Request = @{
        "virtual-DNS-record" = @{
            parent_type             = "virtual-DNS"
            fq_name                 = @("default-domain", $DNSServerName, [guid]::NewGuid())
            virtual_DNS_record_data = $VirtualDNSRecord
        }
    }

    $RequestUrl = $ContrailUrl + "/virtual-DNS-records"
    $Response = Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Post -ContentType "application/json" -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $Request)

    return $Response.'virtual-DNS-record'.'uuid'
}

function Remove-ContrailDNSRecord {
    Param (
        [Parameter(Mandatory = $true)] [string] $ContrailUrl,
        [Parameter(Mandatory = $true)] [string] $AuthToken,
        [Parameter(Mandatory = $true)] [string] $DNSRecordUuid
    )

    $DNSRecordURl = $ContrailUrl + "/virtual-DNS-record/" + $DNSRecordUuid
    Invoke-RestMethod -Method Delete -Uri $DNSRecordURl -Headers @{"X-Auth-Token" = $AuthToken} | Out-Null
}

function Add-ContrailDNSServer {
    Param (
        [Parameter(Mandatory = $true)] [string] $ContrailUrl,
        [Parameter(Mandatory = $true)] [string] $AuthToken,
        [Parameter(Mandatory = $true)] [string] $DNSServerName,
        [Parameter(Mandatory = $false)] [VirtualDNSData] $VirtualDNSData = [VirtualDNSData]::new()
    )

    $VirtualDNS = @{
        domain_name                 = $VirtualDNSData.DomainName
        dynamic_records_from_client = $VirtualDNSData.DynamicRecordsFromClient
        record_order                = $VirtualDNSData.RecordOrder
        default_ttl_seconds         = $VirtualDNSData.DefaultTTLInSeconds
        floating_ip_record          = $VirtualDNSData.FloatingIpRecord
        external_visible            = $VirtualDNSData.ExternalVisible
        reverse_resolution          = $VirtualDNSData.ReverseResolution
    }

    $Request = @{
        "virtual-DNS" = @{
            parent_type      = "domain"
            fq_name          = @("default-domain", $DNSServerName)
            virtual_DNS_data = $VirtualDNS
        }
    }

    $RequestUrl = $ContrailUrl + "/virtual-DNSs"
    $Response = Invoke-RestMethod -Uri $RequestUrl -Headers @{"X-Auth-Token" = $AuthToken} `
        -Method Post -ContentType "application/json" -Body (ConvertTo-Json -Depth $CONVERT_TO_JSON_MAX_DEPTH $Request)

    return $Response.'virtual-DNS'.'uuid'
}

function Remove-ContrailDNSServer {
    Param (
        [Parameter(Mandatory = $true)] [string] $ContrailUrl,
        [Parameter(Mandatory = $true)] [string] $AuthToken,
        [Parameter(Mandatory = $true)] [string] $DNSServerUuid,
        [Switch] $Force
    )

    $DNSServerURl = $ContrailUrl + "/virtual-DNS/" + $DNSServerUuid
    $DNSServer = Invoke-RestMethod -Method Get -Uri $DNSServerURl -Headers @{"X-Auth-Token" = $AuthToken}

    if ($Force) {

        if($DNSServer.'virtual-DNS'.PSobject.Properties.Name -contains 'virtual_DNS_records') {
            $VirtualDNSRecords = $DNSServer.'virtual-DNS'.'virtual_DNS_records'
            ForEach ($VirtualDNSRecord in $VirtualDNSRecords) {
                Invoke-RestMethod -Method Delete -Uri $VirtualDNSRecord.'href' `
                    -Headers @{"X-Auth-Token" = $AuthToken} | Out-Null
            }
        }

        if($DNSServer.'virtual-DNS'.PSobject.Properties.Name -contains 'network_ipam_back_refs') {
            $NetworkIPAMs = $DNSServer.'virtual-DNS'.'network_ipam_back_refs'
            ForEach ($NetworkIPAM in $NetworkIPAMs) {
                Set-IpamDNSMode -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                    -IpamFQName $NetworkIPAM.'to' `
                    -DNSMode 'none'
            }
        }
    }

    Invoke-RestMethod -Method Delete -Uri $DNSServerURl -Headers @{"X-Auth-Token" = $AuthToken} | Out-Null
}
