class DNSServer {
    [string] $Name;
    [string] $DomainName = "default-domain";
    [boolean] $DynamicRecordsFromClient = $true;
    [int] $DefaultTTLInSeconds = 86400;
    [boolean] $ExternalVisible = $false;
    [boolean] $ReverseResolution = $false;
    [string] $Uuid;
    [string] $NextDNSServer = $null;

    [ValidateSet("fixed","random","round-robin")]
    [string] $RecordOrder = "random";

    [ValidateSet("dashed-ip","dashed-ip-tenant-name","vm-name","vm-name-tenant-name")]
    [string] $FloatingIpRecord = "dashed-ip-tenant-name";

    DNSServer([String] $Name) {
        $this.Name = $Name
    }

    [String[]] GetFQName() {
        return @($this.DomainName, $this.Name)
    }
}
