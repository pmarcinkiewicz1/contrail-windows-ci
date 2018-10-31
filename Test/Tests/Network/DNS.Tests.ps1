Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile = $TestenvConfFile,
    [Parameter(Mandatory=$false)] [string] $LogDir = "pesterLogs",
    [Parameter(ValueFromRemainingArguments=$true)] $UnusedParams
)

. $PSScriptRoot\..\..\..\CIScripts\Common\Aliases.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Init.ps1

. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testbed.ps1

. $PSScriptRoot\..\..\PesterHelpers\PesterHelpers.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\PesterLogger\RemoteLogCollector.ps1

. $PSScriptRoot\..\..\TestConfigurationUtils.ps1
. $PSScriptRoot\..\..\Utils\NetAdapterInfo\RemoteContainer.ps1
. $PSScriptRoot\..\..\Utils\ContrailNetworkManager.ps1
. $PSScriptRoot\..\..\Utils\MultiNode\ContrailMultiNodeProvisioning.ps1

. $PSScriptRoot\..\..\Utils\ContrailAPI\DNSServerRepo.ps1
. $PSScriptRoot\..\..\Utils\ContrailAPI\IPAMRepo.ps1

$ContainersIDs = @("jolly-lumberjack","juniper-tree")

$Subnet = [SubnetConfiguration]::new(
    "10.0.5.0",
    24,
    "10.0.5.1",
    "10.0.5.19",
    "10.0.5.83"
)
$Network = [Network]::New("testnet12", $Subnet)

$TenantDNSServerAddress = "10.0.5.80"

$VirtualDNSServer = [DNSServer]::New("CreatedForTest")

$VirtualDNSrecords = @([DNSRecord]::New("vdnsrecord-nonetest", "1.1.1.1", "A", $VirtualDNSServer.GetFQName()),
                       [DNSRecord]::New("vdnsrecord-defaulttest", "1.1.1.2", "A", $VirtualDNSServer.GetFQName()),
                       [DNSRecord]::New("vdnsrecord-virtualtest", "1.1.1.3", "A", $VirtualDNSServer.GetFQName()),
                       [DNSRecord]::New("vdnsrecord-tenanttest", "1.1.1.4", "A", $VirtualDNSServer.GetFQName())
)

$DefaultDNSrecords = @([DNSRecord]::New("defaultrecord-nonetest.com", "3.3.3.1", "A", ""),
                       [DNSRecord]::New("defaultrecord-defaulttest.com", "3.3.3.2", "A", ""),
                       [DNSRecord]::New("defaultrecord-virtualtest.com", "3.3.3.3", "A", ""),
                       [DNSRecord]::New("defaultrecord-tenanttest.com", "3.3.3.4", "A", "")
)

# This function is used to generate command
# that will be passed to docker exec.
# $Hostname will be substituted.
function Resolve-DNSLocally {
    $resolved = (Resolve-DnsName -Name $Hostname -Type A -ErrorAction SilentlyContinue)

    if($error.Count -eq 0) {
        Write-Host "found"
        $resolved[0].IPAddress
    } else {
        Write-Host "error"
        $error[0].CategoryInfo.Category
    }
}
$ResolveDNSLocallyCommand = (${function:Resolve-DNSLocally} -replace "`n|`r", ";")

function Start-Container {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [string] $ContainerID,
        [Parameter(Mandatory=$true)] [string] $ContainerImage,
        [Parameter(Mandatory=$true)] [string] $NetworkName,
        [Parameter(Mandatory=$false)] [string] $IP
    )

    Write-Log "Creating container: $ContainerID"
    New-Container `
        -Session $Session `
        -NetworkName $NetworkName `
        -Name $ContainerID `
        -Image $ContainerImage `
        -IP $IP

    Write-Log "Getting container NetAdapter Information"
    $ContainerNetInfo = Get-RemoteContainerNetAdapterInformation `
        -Session $Session -ContainerID $ContainerID
    $IP = $ContainerNetInfo.IPAddress
    Write-Log "IP of $ContainerID : $IP"

    return $IP
}

function Start-DNSServerOnTestBed {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session
    )
    Write-Log "Starting Test DNS Server on test bed..."
    $DefaultDNSServerDir = "C:\DNS_Server"
    Invoke-Command -Session $Session -ScriptBlock {
        New-Item -ItemType Directory -Force $Using:DefaultDNSServerDir | Out-Null
        New-Item "$($Using:DefaultDNSServerDir + '\zones')" -Type File -Force
        foreach($Record in $Using:DefaultDNSrecords) {
            Add-Content -Path "$($Using:DefaultDNSServerDir + '\zones')" -Value "$($Record.Name)    $($Record.Type)    $($Record.Data)"
        }
    }

    Copy-Item -ToSession $Session -Path ($DockerfilesPath + "python-dns\dnserver.py") -Destination $DefaultDNSServerDir
    Invoke-Command -Session $Session -ScriptBlock {
        $env:ZONE_FILE = "$($Using:DefaultDNSServerDir + '\zones')"
        Start-Process -FilePath "python" -ArgumentList "$($Using:DefaultDNSServerDir + '\dnserver.py')"
    }
}

function Set-DNSServerAddressOnTestBed {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $ClientSession,
        [Parameter(Mandatory=$true)] [PSSessionT] $ServerSession
    )
    $DefaultDNSServerAddress = Invoke-Command -Session $ServerSession -ScriptBlock {
        Get-NetIPAddress -InterfaceAlias "Ethernet0" | Where-Object { $_.AddressFamily -eq 2 } | Select-Object -ExpandProperty IPAddress
    }
    Write-Log "Setting default DNS Server on test bed for: $DefaultDNSServerAddress..."
    $OldDNSs = Invoke-Command -Session $ClientSession -ScriptBlock {
        Get-DnsClientServerAddress -InterfaceAlias "Ethernet0" | Where-Object {$_.AddressFamily -eq 2} | Select-Object -ExpandProperty ServerAddresses
    }
    Invoke-Command -Session $ClientSession -ScriptBlock {
        Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses $Using:DefaultDNSServerAddress
    }

    return $OldDNSs
}

function Resolve-DNS {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $ContainerName,
        [Parameter(Mandatory=$true)] [String] $Hostname
    )

    $Command = $ResolveDNSLocallyCommand -replace '\$Hostname', ('"'+$Hostname+'"')

    $Result = (Invoke-Command -Session $Session -ScriptBlock {
        docker exec $Using:ContainerName powershell $Using:Command
    }).Split([Environment]::NewLine)

    Write-Log "Resolving effect: $($Result[0]) - $($Result[1])"

    if($Result[0] -eq "error") {
        return @{"error" = $Result[1]; "result" = $null}
    }

    return @{"error" = $null; "result" = $Result[1]}
}

function ResolveCorrectly {
    Param (
        [Parameter(Mandatory=$true)] [String] $Hostname,
        [Parameter(Mandatory=$false)] [String] $IP = "Any"
    )

    Write-Log "Trying to resolve host '$Hostname', expecting ip '$IP'"

    $result = Resolve-DNS -Session $MultiNode.Sessions[0] `
        -ContainerName $ContainersIDs[0] -Hostname $Hostname

    if((-not $result.error)) {
        if(($IP -eq "Any") -or ($result.result -eq $IP)) {
            return $true
        }
    }
    return $false
}

function ResolveWithError {
    Param (
        [Parameter(Mandatory=$true)] [String] $Hostname,
        [Parameter(Mandatory=$true)] [String] $ErrorType
    )

    Write-Log "Trying to resolve host '$Hostname', expecting error '$ErrorType'"

    $result = Resolve-DNS -Session $MultiNode.Sessions[0] `
        -ContainerName $ContainersIDs[0] -Hostname $Hostname
    return (($result.error -eq $ErrorType) -and (-not $result.result))
}

Test-WithRetries 1 {
    Describe "DNS tests" {
        BeforeAll {
            Initialize-PesterLogger -OutDir $LogDir
            $MultiNode = New-MultiNodeSetup -TestenvConfFile $TestenvConfFile
            Start-DNSServerOnTestBed -Session $MultiNode.Sessions[1]

            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                "PSUseDeclaredVarsMoreThanAssignments",
                "OldDNSs",
                Justification="It's actually used."
            )]
            $OldDNSs = Set-DNSServerAddressOnTestBed `
                           -ClientSession $MultiNode.Sessions[0] `
                           -ServerSession $MultiNode.Sessions[1]

            Write-Log "Creating Virtual DNS Server in Contrail..."
            $DNSServerRepo = [DNSServerRepo]::New($MultiNode.NM)
            $DNSServerRepo.AddDNSServer($VirtualDNSServer)
            foreach($DNSRecord in $VirtualDNSrecords) {
                $DNSServerRepo.AddDNSRecord($DNSRecord)
            }

            Write-Log "Initializing Contrail services on test beds..."
            foreach($Session in $MultiNode.Sessions) {
                Initialize-ComputeServices -Session $Session `
                    -SystemConfig $MultiNode.Configs.System `
                    -OpenStackConfig $MultiNode.Configs.OpenStack `
                    -ControllerConfig $MultiNode.Configs.Controller
            }

            Write-Log "Creating virtual network: $($Network.Name)"
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                "PSUseDeclaredVarsMoreThanAssignments",
                "ContrailNetwork",
                Justification="It's actually used."
            )]
            $ContrailNetwork = $MultiNode.NM.AddOrReplaceNetwork($null, $Network.Name, $Network.Subnet)
        }

        function BeforeEachContext {
            Param (
                [Parameter(Mandatory=$true)] [IPAMDNSSettings] $DNSSettings
            )
            $IPAM = [IPAM]::New()
            $IPAM.DNSSettings = $DNSSettings
            $IPAMRepo = [IPAMRepo]::New($MultiNode.NM)
            $IPAMRepo.SetIpamDNSMode($IPAM)

            foreach($Session in $MultiNode.Sessions) {
                $ID = New-DockerNetwork -Session $Session `
                    -TenantName $MultiNode.Configs.Controller.DefaultProject `
                    -Name $Network.Name `
                    -Subnet "$( $Network.Subnet.IpPrefix )/$( $Network.Subnet.IpPrefixLen )"

                Write-Log "Created network id: $ID"
            }

            Start-Container -Session $MultiNode.Sessions[0] `
                -ContainerID $ContainersIDs[0] `
                -ContainerImage "microsoft/windowsservercore" `
                -NetworkName $Network.Name
        }

        function AfterEachContext {
            try {
                Merge-Logs -LogSources (
                    (New-ContainerLogSource -Sessions $MultiNode.Sessions[0] -ContainerNames $ContainersIDs[0]),
                    (New-ContainerLogSource -Sessions $MultiNode.Sessions[1] -ContainerNames $ContainersIDs[1])
                )

                Write-Log "Removing all containers and docker networks"
                Remove-AllContainers -Sessions $MultiNode.Sessions
                Remove-AllUnusedDockerNetworks -Session $MultiNode.Sessions[0]
                Remove-AllUnusedDockerNetworks -Session $MultiNode.Sessions[1]
            } finally {
                Merge-Logs -DontCleanUp -LogSources (New-FileLogSource -Path (Get-ComputeLogsPath) -Sessions $MultiNode.Sessions)
            }
        }

        AfterAll {
            if (Get-Variable "ContrailNetwork" -ErrorAction SilentlyContinue) {
                Write-Log "Deleting virtual network"
                $MultiNode.NM.RemoveNetwork($ContrailNetwork)
            }

            if (Get-Variable "MultiNode" -ErrorAction SilentlyContinue) {
                foreach($Session in $MultiNode.Sessions) {
                    Clear-TestConfiguration -Session $Session `
                        -SystemConfig $MultiNode.Configs.System
                }

                Clear-Logs -LogSources (New-FileLogSource -Path (Get-ComputeLogsPath) -Sessions $MultiNode.Sessions)

                if($VirtualDNSServer.Uuid) {
                    Write-Log "Removing Virtual DNS Server from Contrail..."
                    $DNSServerRepo = [DNSServerRepo]::New($MultiNode.NM)
                    $DNSServerRepo.RemoveDNSServerWithDependencies($VirtualDNSServer)
                }

                if (Get-Variable "OldDNSs" -ErrorAction SilentlyContinue) {
                    Write-Log "Restoring old DNS servers on test bed..."
                    Invoke-Command -Session $MultiNode.Sessions[0] -ScriptBlock {
                        Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses $Using:OldDNSs
                    }
                }

                Remove-MultiNodeSetup -MultiNode $MultiNode
                Remove-Variable "MultiNode"
            }
        }

        Context "DNS mode none" {
            BeforeAll { BeforeEachContext -DNSSetting ([NoneDNSSettings]::New()) }

            AfterAll { AfterEachContext }

            It "timeouts resolving juniper.net" {
                ResolveWithError `
                    -Hostname "Juniper.net" `
                    -ErrorType "OperationTimeout" `
                    | Should -BeTrue
            }
        }

        Context "DNS mode default" {
            BeforeAll { BeforeEachContext -DNSSetting ([DefaultDNSSettings]::New()) }

            AfterAll { AfterEachContext }

            It "doesn't resolve juniper.net" {
                ResolveWithError `
                    -Hostname "Juniper.net" `
                    -ErrorType "ResourceUnavailable" `
                    | Should -BeTrue
            }

            It "doesn't resolve virtual DNS" {
                ResolveWithError `
                    -Hostname "vdnsrecord-defaulttest.default-domain" `
                    -ErrorType "ResourceUnavailable" `
                    | Should -BeTrue
            }

            It "resolves default DNS server" {
                ResolveCorrectly `
                    -Hostname "defaultrecord-defaulttest.com" `
                    -IP "3.3.3.2" `
                    | Should -BeTrue
            }
        }

        Context "DNS mode virtual" {
            BeforeAll { BeforeEachContext -DNSSetting ([VirtualDNSSettings]::New($VirtualDNSServer.GetFQName())) }

            AfterAll { AfterEachContext }

            It "resolves juniper.net" {
                ResolveCorrectly `
                    -Hostname " juniper.net" `
                    | Should -BeTrue
            }

            It "resolves virtual DNS" {
                ResolveCorrectly `
                    -Hostname "vdnsrecord-virtualtest.default-domain" `
                    -IP "1.1.1.3" `
                    | Should -BeTrue
            }

            It "doesn't resolve default DNS server" {
                ResolveWithError `
                    -Hostname "defaultrecord-virtualtest.com" `
                    -ErrorType "ResourceUnavailable" `
                    | Should -BeTrue
            }
        }

        Context "DNS mode tenant" {
            BeforeAll {
                BeforeEachContext -DNSSetting ([TenantDNSSettings]::New(@($TenantDNSServerAddress)))

                Start-Container `
                    -Session $MultiNode.Sessions[1] `
                    -ContainerID $ContainersIDs[1] `
                    -ContainerImage "python-dns" `
                    -NetworkName $Network.Name `
                    -IP $TenantDNSServerAddress
            }

            AfterAll { AfterEachContext }

            It "doesn't resolve juniper.net" {
                ResolveWithError `
                    -Hostname "juniper.net" `
                    -ErrorType "ResourceUnavailable" `
                    | Should -BeTrue
            }

            It "doesn't resolve virtual DNS" {
                ResolveWithError `
                    -Hostname "vdnsrecord-tenanttest.default-domain" `
                    -ErrorType "ResourceUnavailable" `
                    | Should -BeTrue
            }

            It "doesn't resolve default DNS server" {
                ResolveWithError `
                    -Hostname "defaultrecord-tenanttest.com" `
                    -ErrorType "ResourceUnavailable" `
                    | Should -BeTrue
            }

            It "resolves tenant DNS" {
                ResolveCorrectly `
                    -Hostname "tenantrecord-tenanttest.com" `
                    -IP "2.2.2.4" `
                    | Should -BeTrue
            }
        }
    }
}
