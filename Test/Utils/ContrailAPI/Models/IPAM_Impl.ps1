class IPAM {
    [string] $Name = "default-network-ipam";
    [string] $DomainName = "default-domain";
    [string] $ProjectName = "default-project";
    [IPAMDNSSettings] $DNSSettings = [NoneDNSSettings]::New();

    [String[]] GetFQName() {
        return @($this.DomainName, $this.ProjectName, $this.Name)
    }
}

class IPAMDNSSettings {
    [string] $DNSMode;
}

class NoneDNSSettings : IPAMDNSSettings {
    NoneDNSSettings() {
        $this.DNSMode = "none"
    }
}

class DefaultDNSSettings : IPAMDNSSettings {
    DefaultDNSSettings() {
        $this.DNSMode = "default-dns-server"
    }
}

class TenantDNSSettings : IPAMDNSSettings {
    [string[]] $ServersIPs;
    TenantDNSSettings([string[]] $ServersIPs) {
        if(-not $ServersIPs) {
            Throw "You need to specify DNS servers"
        }
        $this.ServersIPs = $ServersIPs
        $this.DNSMode = "tenant-dns-server"
    }
}

class VirtualDNSSettings : IPAMDNSSettings {
    [string[]] $FQServerName;
    VirtualDNSSettings([String[]] $FQServerName) {
        if(-not $FQServerName) {
            Throw "You need to specify DNS server"
        }
        $this.FQServerName = $FQServerName
        $this.DNSMode = "virtual-dns-server"
    }
}
