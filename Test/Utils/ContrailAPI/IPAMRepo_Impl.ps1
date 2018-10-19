class IPAMRepo {
    [String] $IPAMResourceName = "network-ipam"

    [ContrailNetworkManager] $API

    IPAMRepo ([ContrailNetworkManager] $API) {
        $this.API = $API
    }

    SetIpamDNSMode ([IPAM] $IPAM) {
        $Request = @{
            "network-ipam" = @{
                "network_ipam_mgmt" = @{"ipam_dns_method" = $IPAM.DNSSettings.DNSMode }
                "virtual_DNS_refs"  = @()
            }
        }

        if ($IPAM.DNSSettings.DNSMode -ceq 'tenant-dns-server') {
            $this.AddTenantDNSInformation($IPAM.DNSSettings, $Request)
        }
        elseif ($IPAM.DNSSettings.DNSMode -ceq 'virtual-dns-server') {
            $this.AddVirtualDNSInformation($IPAM.DNSSettings, $Request)
        }

        $IpamUuid = $this.API.FQNameToUuid($this.IPAMResourceName, $IPAM.GetFQName())

        $this.API.Put($this.IPAMResourceName, $IpamUuid, $Request)
    }

    hidden AddTenantDNSInformation ([TenantDNSSettings] $TenantDNSSettings, $Request) {
        $DNSServer = @{
            "ipam_dns_server" = @{
                "tenant_dns_server_address" = @{
                    "ip_address" = $TenantDNSSettings.ServersIPs
                }
            }
        }

        $Request."network-ipam"."network_ipam_mgmt" += $DNSServer
    }

    hidden AddVirtualDNSInformation ([VirtualDNSSettings] $VirtualDNSSettings, $Request) {

        $VirtualServerUuid = $this.API.FQNameToUuid("virtual-DNS", $VirtualDNSSettings.FQServerName)
        $VirtualServerUrl = $this.API.GetResourceUrl("virtual-DNS", $VirtualServerUuid)

        $DNSServer = @{
            "ipam_dns_server" = @{
                "virtual_dns_server_name" = [string]::Join(":", $VirtualDNSSettings.FQServerName)
            }
        }
        $Request."network-ipam"."network_ipam_mgmt" += $DNSServer

        $VirtualServerRef = @{
            "href" = $VirtualServerUrl
            "uuid" = $VirtualServerUuid
            "to"   = $VirtualDNSSettings.FQServerName
        }

        $Request."network-ipam"."virtual_DNS_refs" = @($VirtualServerRef)
    }
}
