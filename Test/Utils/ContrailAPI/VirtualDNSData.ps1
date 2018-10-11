class VirtualDNSData {
    [string] $DomainName;
    [boolean] $DynamicRecordsFromClient;
    [int] $DefaultTTLInSeconds;
    [boolean] $ExternalVisible;
    [boolean] $ReverseResolution;

    [ValidateSet("fixed","random","round-robin")]
    [string] $RecordOrder;

    [ValidateSet("dashed-ip","dashed-ip-tenant-name","vm-name","vm-name-tenant-name")]
    [string] $FloatingIpRecord;

    hidden Init([boolean] $DynamicRecordsFromClient, [string] $RecordOrder,
        [int] $DefaultTTLInSeconds, [string] $FloatingIpRecord,
        [boolean] $ExternalVisible, [boolean] $ReverseResolution, [string] $DomainName) {

        $this.DomainName = $DomainName;
        $this.DynamicRecordsFromClient = $DynamicRecordsFromClient;
        $this.RecordOrder = $RecordOrder;
        $this.DefaultTTLInSeconds = $DefaultTTLInSeconds;
        $this.FloatingIpRecord = $FloatingIpRecord;
        $this.ExternalVisible = $ExternalVisible;
        $this.ReverseResolution = $ReverseResolution;
    }

    hidden Init([boolean] $DynamicRecordsFromClient, [string] $RecordOrder,
        [int] $DefaultTTLInSeconds, [string] $FloatingIpRecord,
        [boolean] $ExternalVisible, [boolean] $ReverseResolution) {

        $this.Init($DynamicRecordsFromClient, $RecordOrder,
            $DefaultTTLInSeconds, $FloatingIpRecord,
            $ExternalVisible, $ReverseResolution, "default-domain")
    }

    hidden Init() {
        $this.Init($true, "random", 86400,
            "dashed-ip-tenant-name", $false, $false)
    }

    VirtualDNSData() {
        $this.Init()
    }

    VirtualDNSData([boolean] $DynamicRecordsFromClient, [string] $RecordOrder,
        [int] $DefaultTTLInSeconds, [string] $FloatingIpRecord,
        [boolean] $ExternalVisible, [boolean] $ReverseResolution) {

        $this.Init($DynamicRecordsFromClient, $RecordOrder,
            $DefaultTTLInSeconds, $FloatingIpRecord,
            $ExternalVisible, $ReverseResolution)
    }
}
