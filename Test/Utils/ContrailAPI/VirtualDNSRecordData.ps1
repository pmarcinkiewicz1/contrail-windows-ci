class VirtualDNSRecordData {
    [string] $RecordName;
    [string] $RecordClass;
    [string] $RecordData;
    [int] $RecordTTLInSeconds;

    [ValidateSet("A","AAAA","CNAME","PTR","NS","MX")]
    [string] $RecordType;

    hidden Init([string] $RecordName, [string] $RecordData,
        [string] $RecordType, [int] $RecordTTLInSeconds,
        [string] $RecordClass) {

        $this.RecordName = $RecordName;
        $this.RecordData = $RecordData;
        $this.RecordType = $RecordType;
        $this.RecordTTLInSeconds = $RecordTTLInSeconds;
        $this.RecordClass = $RecordClass;
    }

    hidden Init([string] $RecordName, [string] $RecordData,
        [string] $RecordType, [int] $RecordTTLInSeconds) {

        $this.Init($RecordName, $RecordData, $RecordType, $RecordTTLInSeconds, "IN")
    }

    hidden Init([string] $RecordName, [string] $RecordData,
        [string] $RecordType) {

        $this.Init($RecordName, $RecordData, $RecordType, 86400);
    }

    VirtualDNSRecordData([string] $RecordName, [string] $RecordData, [string] $RecordType,
        [int] $RecordTTLInSeconds) {

        $this.Init($RecordName, $RecordData, $RecordType, $RecordTTLInSeconds);
    }

    VirtualDNSRecordData([string] $RecordName, [string] $RecordData, [string] $RecordType) {
        $this.Init($RecordName, $RecordData, $RecordType);
    }
}
