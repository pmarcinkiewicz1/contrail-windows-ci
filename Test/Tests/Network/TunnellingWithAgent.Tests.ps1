Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
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
. $PSScriptRoot\..\..\Utils\Network\Connectivity.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Initialize.ps1
. $PSScriptRoot\..\..\Utils\ContrailNetworkManager.ps1
. $PSScriptRoot\..\..\Utils\MultiNode\ContrailMultiNodeProvisioning.ps1

$TCPServerDockerImage = "python-http"
$Container1ID = "jolly-lumberjack"
$Container2ID = "juniper-tree"
$Subnet = [SubnetConfiguration]::new(
    "10.0.5.0",
    24,
    "10.0.5.1",
    "10.0.5.19",
    "10.0.5.83"
)
$Network = [Network]::New("testnet12", $Subnet)

function Get-MaxIPv4DataSizeForMTU {
    Param ([Parameter(Mandatory=$true)] [Int] $MTU)
    $MinimalIPHeaderSize = 20
    return $MTU - $MinimalIPHeaderSize
}

function Get-MaxICMPDataSizeForMTU {
    Param ([Parameter(Mandatory=$true)] [Int] $MTU)
    $ICMPHeaderSize = 8
    return $(Get-MaxIPv4DataSizeForMTU -MTU $MTU) - $ICMPHeaderSize
}

function Get-MaxUDPDataSizeForMTU {
    Param ([Parameter(Mandatory=$true)] [Int] $MTU)
    $UDPHeaderSize = 8
    return $(Get-MaxIPv4DataSizeForMTU -MTU $MTU) - $UDPHeaderSize
}

function Get-VrfStats {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    # NOTE: we are assuming that there will be only one vif with index == 2.
    #       Indices 0 and 1 are reserved, so the first available is index 2.
    #       This is consistent - for now. It used to be that only index 0 was reserved, so it may
    #       change in the future.
    #       We could get this index by using other utils and doing a bunch of filtering, but
    #       let's do it when the time comes.
    $VifIdx = 2
    $Stats = Invoke-Command -Session $Session -ScriptBlock {
        $Out = $(vrfstats --get $Using:VifIdx)
        $PktCountMPLSoUDP = [regex]::new("Udp Mpls Tunnels ([0-9]+)").Match($Out[3]).Groups[1].Value
        $PktCountMPLSoGRE = [regex]::new("Gre Mpls Tunnels ([0-9]+)").Match($Out[3]).Groups[1].Value
        $PktCountVXLAN = [regex]::new("Vxlan Tunnels ([0-9]+)").Match($Out[3]).Groups[1].Value
        return @{
            MPLSoUDP = $PktCountMPLSoUDP
            MPLSoGRE = $PktCountMPLSoGRE
            VXLAN = $PktCountVXLAN
        }
    }
    Write-Log "vrfstats for vif $VifIdx : $($Stats | Out-String)"
    return $Stats
}

Test-WithRetries 3 {
    Describe "Tunneling with Agent tests" {

        #
        #               !!!!!! IMPORTANT: DEBUGGING/DEVELOPING THESE TESTS !!!!!!
        #
        # tl;dr: "fresh" controller uses MPLSoGRE by default. But when someone logs in via WebUI for
        # the first time, it changes to MPLSoUDP. You have been warned.
        #
        # Logging into WebUI for the first time is known to cause problems.
        # When someone logs into webui for the first time, it suddenly realizes that its default
        # encap priorities list is different than the one on the controller. It causes a cascade of
        # requests from WebUI to config node, that will change the tunneling method.
        #
        # When debugging, make sure that the encapsulation method specified in webui
        # (under Configure/Infrastructure/Global Config/Virtual Routers/Encapsulation Priority Order)
        # matches the one that is applied using ContrailNM in code below (Config node REST API).
        # Do it especially when logging in via WebUI for the first time.
        #

        foreach($TunnelingMethod in @("MPLSoGRE", "MPLSoUDP", "VXLAN")) {
            Context "Tunneling $TunnelingMethod" {
                BeforeEach {
                    $EncapPrioritiesList = @($TunnelingMethod)
                    $MultiNode.NM.SetEncapPriorities($EncapPrioritiesList)

                    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                        "PSUseDeclaredVarsMoreThanAssignments",
                        "Sessions",
                        Justification="It's actually used in 'It' blocks."
                    )]
                    $Sessions = $MultiNode.Sessions
                }

                It "Uses specified tunneling method" -Pending {
                    if ($TunnelingMethod -eq "VXLAN") {
                        # Probably a bug here: https://github.com/Juniper/contrail-vrouter/blob/master/dp-core/vr_nexthop.c#L1983
                        Set-TestInconclusive "Test not performed, because VXLAN doesn't report correctly in vrfstats"
                    }

                    $StatsBefore = Get-VrfStats -Session $Sessions[0]

                    Test-Ping `
                        -Session $Sessions[0] `
                        -SrcContainerName $Container1ID `
                        -DstContainerName $Container2ID `
                        -DstIP $Container2NetInfo.IPAddress | Should Be 0

                    $StatsAfter = Get-VrfStats -Session $Sessions[0]
                    $StatsAfter[$TunnelingMethod] | Should BeGreaterThan $StatsBefore[$TunnelingMethod]
                }

                It "ICMP - Ping between containers on separate compute nodes succeeds" -Pending {
                    Test-Ping `
                        -Session $Sessions[0] `
                        -SrcContainerName $Container1ID `
                        -DstContainerName $Container2ID `
                        -DstIP $Container2NetInfo.IPAddress | Should Be 0

                    Test-Ping `
                        -Session $Sessions[1] `
                        -SrcContainerName $Container2ID `
                        -DstContainerName $Container1ID `
                        -DstIP $Container1NetInfo.IPAddress | Should Be 0
                }

                It "TCP - HTTP connection between containers on separate compute nodes succeeds" -Pending {
                    Test-TCP `
                        -Session $Sessions[1] `
                        -SrcContainerName $Container2ID `
                        -DstContainerName $Container1ID `
                        -DstIP $Container1NetInfo.IPAddress | Should Be 0
                }

                It "UDP - sending message between containers on separate compute nodes succeeds" -Pending {
                    $MyMessage = "We are Tungsten Fabric. We come in peace."

                    Test-UDP `
                        -ListenerContainerSession $Sessions[0] `
                        -ListenerContainerName $Container1ID `
                        -ListenerContainerIP $Container1NetInfo.IPAddress `
                        -ClientContainerSession $Sessions[1] `
                        -ClientContainerName $Container2ID `
                        -Message $MyMessage | Should Be $true
                }

                It "IP fragmentation - ICMP - Ping with big buffer succeeds" -Pending {
                    $Container1MsgFragmentationThreshold = Get-MaxICMPDataSizeForMTU -MTU $Container1NetInfo.MtuSize
                    $Container2MsgFragmentationThreshold = Get-MaxICMPDataSizeForMTU -MTU $Container2NetInfo.MtuSize

                    $SrcContainers = @($Container1ID, $Container2ID)
                    $DstContainers = @($Container2ID, $Container1ID)
                    $DstIPs = @($Container2NetInfo.IPAddress, $Container1NetInfo.IPAddress)
                    $BufferSizes = @($Container1MsgFragmentationThreshold, $Container2MsgFragmentationThreshold)

                    foreach ($ContainerIdx in @(0, 1)) {
                        $BufferSizeLargerBeforeTunneling = $BufferSizes[$ContainerIdx] + 1
                        $BufferSizeLargerAfterTunneling = $BufferSizes[$ContainerIdx] - 1
                        foreach ($BufferSize in @($BufferSizeLargerBeforeTunneling, $BufferSizeLargerAfterTunneling)) {
                            Test-Ping `
                                -Session $Sessions[$ContainerIdx] `
                                -SrcContainerName $SrcContainers[$ContainerIdx] `
                                -DstContainerName $DstContainers[$ContainerIdx] `
                                -DstIP $DstIPs[$ContainerIdx] `
                                -BufferSize $BufferSize | Should Be 0
                        }
                    }
                }

                It "IP fragmentation - UDP - sending big buffer succeeds" -Pending {
                    $MsgFragmentationThreshold = Get-MaxUDPDataSizeForMTU -MTU $Container1NetInfo.MtuSize

                    $MessageLargerBeforeTunneling = "a" * $($MsgFragmentationThreshold + 1)
                    $MessageLargerAfterTunneling = "a" * $($MsgFragmentationThreshold - 1)
                    foreach ($Message in @($MessageLargerBeforeTunneling, $MessageLargerAfterTunneling)) {
                        Test-UDP `
                            -ListenerContainerSession $Sessions[0] `
                            -ListenerContainerName $Container1ID `
                            -ListenerContainerIP $Container1NetInfo.IPAddress `
                            -ClientContainerSession $Sessions[1] `
                            -ClientContainerName $Container2ID `
                            -Message $Message | Should Be $true
                    }
                }

                # NOTE: There is no TCPoIP fragmentation test, because it auto-adjusts segment size,
                #       so it would always pass.
            }
        }

        BeforeAll {
            Initialize-PesterLogger -OutDir $LogDir
            $MultiNode = New-MultiNodeSetup -TestenvConfFile $TestenvConfFile

            Write-Log "Creating virtual network: $($Network.Name)"
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                "PSUseDeclaredVarsMoreThanAssignments",
                "ContrailNetwork",
                Justification="It's actually used."
            )]
            $ContrailNetwork = $MultiNode.NM.AddOrReplaceNetwork($null, $Network.Name, $Subnet)

            Initialize-ComputeNode -Session $MultiNode.Sessions[0] -Networks @($Network) -Configs $MultiNode.Configs
            Initialize-ComputeNode -Session $MultiNode.Sessions[1] -Networks @($Network) -Configs $MultiNode.Configs
        }

        AfterAll {
            if (Get-Variable "MultiNode" -ErrorAction SilentlyContinue) {
                $Sessions = $MultiNode.Sessions
                $SystemConfig = $MultiNode.Configs.System

                Clear-TestConfiguration -Session $Sessions[0] -SystemConfig $SystemConfig
                Clear-TestConfiguration -Session $Sessions[1] -SystemConfig $SystemConfig
                Clear-Logs -LogSources (New-FileLogSource -Path (Get-ComputeLogsPath) -Sessions $Sessions)

                Write-Log "Deleting virtual network"
                if (Get-Variable ContrailNetwork -ErrorAction SilentlyContinue) {
                    $MultiNode.NM.RemoveNetwork($ContrailNetwork)
                }

                Remove-MultiNodeSetup -MultiNode $MultiNode
                Remove-Variable "MultiNode"
            }
        }

        BeforeEach {
            Write-Log "Creating containers"
            Write-Log "Creating container: $Container1ID"
            New-Container `
                -Session $MultiNode.Sessions[0] `
                -NetworkName $Network.Name `
                -Name $Container1ID `
                -Image $TCPServerDockerImage
            Write-Log "Creating container: $Container2ID"
            New-Container `
                -Session $MultiNode.Sessions[1] `
                -NetworkName $Network.Name `
                -Name $Container2ID `
                -Image "microsoft/windowsservercore"

            Write-Log "Getting containers' NetAdapter Information"
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                "PSUseDeclaredVarsMoreThanAssignments",
                "Container1NetInfo",
                Justification="It's actually used."
            )]
            $Container1NetInfo = Get-RemoteContainerNetAdapterInformation `
                -Session $MultiNode.Sessions[0] -ContainerID $Container1ID
            $IP = $Container1NetInfo.IPAddress
            Write-Log "IP of ${Container1ID}: $IP"
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                "PSUseDeclaredVarsMoreThanAssignments",
                "Container2NetInfo",
                Justification="It's actually used."
            )]
            $Container2NetInfo = Get-RemoteContainerNetAdapterInformation `
                -Session $MultiNode.Sessions[1] -ContainerID $Container2ID
            $IP = $Container2NetInfo.IPAddress
            Write-Log "IP of ${Container2ID}: $IP"
        }

        AfterEach {
            $Sessions = $MultiNode.Sessions
            try {
                Merge-Logs -LogSources (
                    (New-ContainerLogSource -Sessions $Sessions[0] -ContainerNames $Container1ID),
                    (New-ContainerLogSource -Sessions $Sessions[1] -ContainerNames $Container2ID)
                )

                Write-Log "Removing all containers"
                Remove-AllContainers -Sessions $Sessions
            } finally {
                Merge-Logs -DontCleanUp -LogSources (New-FileLogSource -Path (Get-ComputeLogsPath) -Sessions $Sessions)
            }
        }
    }
}
