. $PSScriptRoot\..\..\CIScripts\Common\Aliases.ps1

class NetAdapterMacAddresses {
    [string] $MACAddress;
    [string] $MACAddressWindows;
}

class NetAdapterInformation : NetAdapterMacAddresses {
    [int] $IfIndex;
    [string] $IfName;
}

class ContainerNetAdapterInformation : NetAdapterInformation {
    [string] $AdapterShortName;
    [string] $AdapterFullName;
    [string] $IPAddress;
    [int] $MtuSize;
}

class VMNetAdapterInformation : NetAdapterMacAddresses {
    [string] $GUID;
}

function Get-RemoteNetAdapterInformation {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $AdapterName)

    $NetAdapterInformation = Invoke-Command -Session $Session -ScriptBlock {
        $Res = Get-NetAdapter -IncludeHidden -Name $Using:AdapterName | Select-Object ifName,MacAddress,ifIndex

        return @{
            IfIndex = $Res.IfIndex;
            IfName = $Res.ifName;
            MACAddress = $Res.MacAddress.Replace("-", ":").ToLower();
            MACAddressWindows = $Res.MacAddress.ToLower();
        }
    }

    return [NetAdapterInformation] $NetAdapterInformation
}

function Get-RemoteVMNetAdapterInformation {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $VMName,
           [Parameter(Mandatory = $true)] [string] $AdapterName)

    $NetAdapterInformation = Invoke-Command -Session $Session -ScriptBlock {
        $NetAdapter = Get-VMNetworkAdapter -VMName $Using:VMName -Name $Using:AdapterName
        $MacAddress = $NetAdapter.MacAddress -Replace '..(?!$)', '$&-'
        $GUID = $NetAdapter.Id.ToLower().Replace('microsoft:', '').Replace('\', '--')

        return @{
            MACAddress = $MacAddress.Replace("-", ":");
            MACAddressWindows = $MacAddress;
            GUID = $GUID
        }
    }

    return [VMNetAdapterInformation] $NetAdapterInformation
}

function Read-RawRemoteContainerNetAdapterInformation {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [string] $ContainerID
    )

    $JsonAdapterInfo = Invoke-Command -Session $Session -ScriptBlock {

        $RemoteCommand = {
            $GetIPAddress = { ($_ | Get-NetIPAddress -AddressFamily IPv4).IPAddress }
            $Fields = 'ifIndex', 'ifName', 'Name', 'MacAddress', 'MtuSize', @{L='IPAddress'; E=$GetIPAddress}
            $Adapter = (Get-NetAdapter -Name 'vEthernet (Container NIC *)')[0]
            return $Adapter | Select-Object $Fields | ConvertTo-Json -Depth 5
        }.ToString()

        docker exec $Using:ContainerID powershell $RemoteCommand
    }

    return $JsonAdapterInfo | ConvertFrom-Json
}

function Assert-IsIpAddressInRawNetAdapterInfoValid {
    Param (
        [Parameter(Mandatory = $true)] [PSCustomObject] $RawAdapterInfo
    )

    if (!$RawAdapterInfo.IPAddress -or ($RawAdapterInfo.IPAddress -isnot [string])) {
        throw "Invalid IPAddress returned from container: $($RawAdapterInfo.IPAddress | ConvertTo-Json)"
    }
}

function ConvertFrom-RawNetAdapterInformation {
    Param (
        [Parameter(Mandatory = $true)] [PSCustomObject] $RawAdapterInfo
    )

    $AdapterInfo = @{
        ifIndex = $RawAdapterInfo.ifIndex
        ifName = $RawAdapterInfo.ifName
        AdapterFullName = $RawAdapterInfo.Name
        AdapterShortName = [regex]::new('vEthernet \((.*)\)').Replace($RawAdapterInfo.Name, '$1')
        MacAddressWindows = $RawAdapterInfo.MacAddress.ToLower()
        IPAddress = $RawAdapterInfo.IPAddress
        MtuSize = $RawAdapterInfo.MtuSize
    }

    $AdapterInfo.MacAddress = $AdapterInfo.MacAddressWindows.Replace('-', ':')

    return [ContainerNetAdapterInformation] $AdapterInfo
}

function Get-RemoteContainerNetAdapterInformation {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $ContainerID)

    $AdapterInfo = Read-RawRemoteContainerNetAdapterInformation -Session $Session -ContainerID $ContainerID
    Assert-IsIpAddressInRawNetAdapterInfoValid -RawAdapterInfo $AdapterInfo
    return ConvertFrom-RawNetAdapterInformation -RawAdapterInfo $AdapterInfo
}

function Get-VrfStats {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    $VrfStats = Invoke-Command -Session $Session -ScriptBlock {
        $vrfstatsOutput = $(vrfstats --get 2)
        $mplsUdpPktCount = [regex]::new("Udp Mpls Tunnels ([0-9]+)").Match($vrfstatsOutput[3]).Groups[1].Value
        $mplsGrePktCount = [regex]::new("Gre Mpls Tunnels ([0-9]+)").Match($vrfstatsOutput[3]).Groups[1].Value
        $vxlanPktCount = [regex]::new("Vxlan Tunnels ([0-9]+)").Match($vrfstatsOutput[3]).Groups[1].Value
        return @{
            MplsUdpPktCount = $mplsUdpPktCount
            MplsGrePktCount = $mplsGrePktCount
            VxlanPktCount = $vxlanPktCount
        }
    }
    return $VrfStats
}

function Assert-PingSucceeded {
    Param ([Parameter(Mandatory = $true)] [Object[]] $Output)
    $ErrorMessage = "Ping failed. EXPECTED: Ping succeeded."
    Foreach ($Line in $Output) {
        if ($Line -match ", Received = (?<NumOfReceivedPackets>[\d]+),[.]*") {
            if ($matches.NumOfReceivedPackets -gt 0) {
                return
            } else {
                throw $ErrorMessage
            }
        }
    }
    throw $ErrorMessage
}

function Ping-Container {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $ContainerName,
           [Parameter(Mandatory = $true)] [string] $IP)
    $PingOutput = Invoke-Command -Session $Session -ScriptBlock {
        & docker exec $Using:ContainerName ping $Using:IP -n 10 -w 500
    }

    Assert-PingSucceeded -Output $PingOutput
}
