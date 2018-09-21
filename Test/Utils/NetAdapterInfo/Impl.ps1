. $PSScriptRoot\..\..\..\CIScripts\Common\Aliases.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Invoke-UntilSucceeds.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\DataStructs.ps1

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

    if ($RawAdapterInfo.IPAddress -Match '^169\.254') {
        throw "Container reports an autoconfiguration IP address: $( $RawAdapterInfo.IPAddress )"
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

    return $AdapterInfo
}

function Get-RemoteContainerNetAdapterInformation {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $ContainerID)

    $AdapterInfo = Invoke-UntilSucceeds -Duration 60 -Interval 5 -Name "waiting for container $ContainerID IP" {
        try {
            $RawAdapterInfo = Read-RawRemoteContainerNetAdapterInformation -Session $Session -ContainerID $ContainerID
            Assert-IsIpAddressInRawNetAdapterInfoValid -RawAdapterInfo $RawAdapterInfo
            $RawAdapterInfo
        } catch {
            Write-Log "Invalid remote IP: $( $_.Exception )"
            throw
        }
    }
    return ConvertFrom-RawNetAdapterInformation -RawAdapterInfo $AdapterInfo
}