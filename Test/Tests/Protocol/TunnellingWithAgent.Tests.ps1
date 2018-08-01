Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(Mandatory=$false)] [string] $LogDir = "pesterLogs",
    [Parameter(ValueFromRemainingArguments=$true)] $UnusedParams
)

. $PSScriptRoot\..\..\..\CIScripts\Common\Aliases.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Init.ps1
. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testenv.ps1
. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testbed.ps1

. $PSScriptRoot\..\..\Utils\ComponentsInstallation.ps1
. $PSScriptRoot\..\..\Utils\ContrailNetworkManager.ps1
. $PSScriptRoot\..\..\TestConfigurationUtils.ps1
. $PSScriptRoot\..\..\Utils\CommonTestCode.ps1
. $PSScriptRoot\..\..\Utils\DockerImageBuild.ps1
. $PSScriptRoot\..\..\PesterHelpers\PesterHelpers.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\PesterLogger\RemoteLogCollector.ps1

$TCPServerDockerImage = "python-http"
$Container1ID = "jolly-lumberjack"
$Container2ID = "juniper-tree"
$NetworkName = "testnet12"
$Subnet = [SubnetConfiguration]::new(
    "10.0.5.0",
    24,
    "10.0.5.1",
    "10.0.5.19",
    "10.0.5.83"
)

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

function Initialize-ComputeNode {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [SubnetConfiguration] $Subnet
    )

    Initialize-ComputeServices -Session $Session `
        -SystemConfig $SystemConfig `
        -OpenStackConfig $OpenStackConfig `
        -ControllerConfig $ControllerConfig

    $NetworkID = New-DockerNetwork -Session $Session `
        -TenantName $ControllerConfig.DefaultProject `
        -Name $NetworkName `
        -Subnet "$( $Subnet.IpPrefix )/$( $Subnet.IpPrefixLen )"

    Write-Log "Created network id: $NetworkID"
}

function Test-Ping {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $SrcContainerName,
        [Parameter(Mandatory=$true)] [String] $DstContainerName,
        [Parameter(Mandatory=$true)] [String] $DstContainerIP,
        [Parameter(Mandatory=$false)] [Int] $BufferSize = 32
    )

    Write-Log "Container $SrcContainerName is pinging $DstContainerName..."
    $Res = Invoke-Command -Session $Session -ScriptBlock {
        docker exec $Using:SrcContainerName powershell `
            "ping -l $Using:BufferSize $Using:DstContainerIP; `$LASTEXITCODE;"
    }
    $Output = $Res[0..($Res.length - 2)]
    Write-Log "Ping output: $Output"
    return $Res[-1]
}

function Test-TCP {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $SrcContainerName,
        [Parameter(Mandatory=$true)] [String] $DstContainerName,
        [Parameter(Mandatory=$true)] [String] $DstContainerIP
    )

    Write-Log "Container $SrcContainerName is sending HTTP request to $DstContainerName..."
    $Res = Invoke-Command -Session $Session -ScriptBlock {
        docker exec $Using:SrcContainerName powershell "Invoke-WebRequest -Uri http://${Using:DstContainerIP}:8080/ -UseBasicParsing -ErrorAction Continue; `$LASTEXITCODE"
    }
    $Output = $Res[0..($Res.length - 2)]
    Write-Log "Web request output: $Output"
    return $Res[-1]
}

function Install-Components {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session
    )

    Install-Extension -Session $Session
    Install-DockerDriver -Session $Session
    Install-Agent -Session $Session
    Install-Utils -Session $Session
}

function Uninstall-Components {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session
    )

    Uninstall-Utils -Session $Session
    Uninstall-Agent -Session $Session
    Uninstall-DockerDriver -Session $Session
    Uninstall-Extension -Session $Session
}

function Test-MPLSoGRE {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session
    )

    $VrfStats = Get-VrfStats -Session $Session
    if (($VrfStats.MplsGrePktCount -eq 0) -or ($VrfStats.MplsUdpPktCount -ne 0) -or ($VrfStats.VxlanPktCount -ne 0)) {
        Write-Log "Tunnel usage statistics: Udp = $($VrfStats.MplsUdpPktCount), Gre = $($VrfStats.MplsGrePktCount), Vxlan = $($VrfStats.VxlanPktCount)"
        return $false
    } else {
        return $true
    }
}

function Test-MPLSoUDP {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session
    )

    $VrfStats = Get-VrfStats -Session $Session
    if (($VrfStats.MplsGrePktCount -ne 0) -or ($VrfStats.MplsUdpPktCount -eq 0) -or ($VrfStats.VxlanPktCount -ne 0)) {
        Write-Log "Tunnel usage statistics: Udp = $($VrfStats.MplsUdpPktCount), Gre = $($VrfStats.MplsGrePktCount), Vxlan = $($VrfStats.VxlanPktCount)"
        return $false
    } else {
        return $true
    }
}

function Start-UDPEchoServerInContainer {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $ContainerName,
        [Parameter(Mandatory=$true)] [Int16] $ServerPort,
        [Parameter(Mandatory=$true)] [Int16] $ClientPort
    )
    $UDPEchoServerCommand = ( `
    '$SendPort = {0};' + `
    '$RcvPort = {1};' + `
    '$IPEndpoint = New-Object System.Net.IPEndPoint([IPAddress]::Any, $RcvPort);' + `
    '$RemoteIPEndpoint = New-Object System.Net.IPEndPoint([IPAddress]::Any, 0);' + `
    '$UDPSocket = New-Object System.Net.Sockets.UdpClient;' + `
    '$UDPSocket.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true);' + `
    '$UDPSocket.Client.Bind($IPEndpoint);' + `
    'while($true) {{' + `
    '    $Payload = $UDPSocket.Receive([ref]$RemoteIPEndpoint);' + `
    '    $RemoteIPEndpoint.Port = $SendPort;' + `
    '    $UDPSocket.Send($Payload, $Payload.Length, $RemoteIPEndpoint);' + `
    '    \"Received message and sent it to: $RemoteIPEndpoint.\" | Out-String;' + `
    '}}') -f $ClientPort, $ServerPort

    Invoke-Command -Session $Session -ScriptBlock {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments",
            "UDPEchoServerJob",
            Justification="It's actually used."
        )]
        $UDPEchoServerJob = Start-Job -ScriptBlock {
            param($ContainerName, $UDPEchoServerCommand)
            docker exec $ContainerName powershell "$UDPEchoServerCommand"
        } -ArgumentList $Using:ContainerName, $Using:UDPEchoServerCommand
    }
}

function Stop-EchoServerInContainer {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session
    )

    $Output = Invoke-Command -Session $Session -ScriptBlock {
        $UDPEchoServerJob | Stop-Job | Out-Null
        $Output = Receive-Job -Job $UDPEchoServerJob
        return $Output
    }

    Write-Log "Output from UDP echo server running in remote session: $Output"
}

function Start-UDPListenerInContainer {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $ContainerName,
        [Parameter(Mandatory=$true)] [Int16] $ListenerPort
    )
    $UDPListenerCommand = ( `
    '$RemoteIPEndpoint = New-Object System.Net.IPEndPoint([IPAddress]::Any, 0);' + `
    '$UDPRcvSocket = New-Object System.Net.Sockets.UdpClient {0};' + `
    '$Payload = $UDPRcvSocket.Receive([ref]$RemoteIPEndpoint);' + `
    '[Text.Encoding]::UTF8.GetString($Payload)') -f $ListenerPort

    Invoke-Command -Session $Session -ScriptBlock {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments",
            "UDPListenerJob",
            Justification="It's actually used."
        )]
        $UDPListenerJob = Start-Job -ScriptBlock {
            param($ContainerName, $UDPListenerCommand)
            & docker exec $ContainerName powershell "$UDPListenerCommand"
        } -ArgumentList $Using:ContainerName, $Using:UDPListenerCommand
    }
}

function Stop-UDPListenerInContainerAndFetchResult {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session
    )

    $Message = Invoke-Command -Session $Session -ScriptBlock {
        $UDPListenerJob | Wait-Job -Timeout 30 | Out-Null
        $ReceivedMessage = Receive-Job -Job $UDPListenerJob
        return $ReceivedMessage
    }
    Write-Log "UDP listener output from remote session: $Message"
    return $Message
}

function Send-UDPFromContainer {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $ContainerName,
        [Parameter(Mandatory=$true)] [String] $Message,
        [Parameter(Mandatory=$true)] [String] $ListenerIP,
        [Parameter(Mandatory=$true)] [Int16] $ListenerPort,
        [Parameter(Mandatory=$true)] [Int16] $NumberOfAttempts,
        [Parameter(Mandatory=$true)] [Int16] $WaitSeconds
    )
    $UDPSendCommand = (
    '$EchoServerAddress = New-Object System.Net.IPEndPoint([IPAddress]::Parse(\"{0}\"), {1});' + `
    '$UDPSenderSocket = New-Object System.Net.Sockets.UdpClient 0;' + `
    '$Payload = [Text.Encoding]::UTF8.GetBytes(\"{2}\");' + `
    '1..{3} | ForEach-Object {{' + `
    '    $UDPSenderSocket.Send($Payload, $Payload.Length, $EchoServerAddress);' + `
    '    Start-Sleep -Seconds {4};' + `
    '}}') -f $ListenerIP, $ListenerPort, $Message, $NumberOfAttempts, $WaitSeconds

    $Output = Invoke-Command -Session $Session -ScriptBlock {
        docker exec $Using:ContainerName powershell "$Using:UDPSendCommand"
    }
    Write-Log "Send UDP output from remote session: $Output"
}

function Test-UDP {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session1,
        [Parameter(Mandatory=$true)] [PSSessionT] $Session2,
        [Parameter(Mandatory=$true)] [String] $Container1Name,
        [Parameter(Mandatory=$true)] [String] $Container2Name,
        [Parameter(Mandatory=$true)] [String] $Container1IP,
        [Parameter(Mandatory=$true)] [String] $Container2IP,
        [Parameter(Mandatory=$true)] [String] $Message,
        [Parameter(Mandatory=$false)] [Int16] $UDPServerPort = 1111,
        [Parameter(Mandatory=$false)] [Int16] $UDPClientPort = 2222
    )

    Write-Log "Starting UDP Echo server on container $Container1Name ..."
    Start-UDPEchoServerInContainer `
        -Session $Session1 `
        -ContainerName $Container1Name `
        -ServerPort $UDPServerPort `
        -ClientPort $UDPClientPort

    Write-Log "Starting UDP listener on container $Container2Name..."
    Start-UDPListenerInContainer `
        -Session $Session2 `
        -ContainerName $Container2Name `
        -ListenerPort $UDPClientPort

    Write-Log "Sending UDP packet from container $Container2Name..."
    Send-UDPFromContainer `
        -Session $Session2 `
        -ContainerName $Container2Name `
        -Message $Message `
        -ListenerIP $Container1IP `
        -ListenerPort $UDPServerPort `
        -NumberOfAttempts 10 `
        -WaitSeconds 1

    Write-Log "Fetching results from listener job..."
    $ReceivedMessage = Stop-UDPListenerInContainerAndFetchResult -Session $Session2
    Stop-EchoServerInContainer -Session $Session1

    Write-Log "Sent message: $Message"
    Write-Log "Received message: $ReceivedMessage"
    if ($ReceivedMessage -eq $Message) {
        return $true
    } else {
        return $false
    }
}

Describe "Tunnelling with Agent tests" {
    Context "Tunneling" {
        It "ICMP - Ping between containers on separate compute nodes succeeds" {
            Test-Ping `
                -Session $Sessions[0] `
                -SrcContainerName $Container1ID `
                -DstContainerName $Container2ID `
                -DstContainerIP $Container2NetInfo.IPAddress | Should Be 0

            Test-Ping `
                -Session $Sessions[1] `
                -SrcContainerName $Container2ID `
                -DstContainerName $Container1ID `
                -DstContainerIP $Container1NetInfo.IPAddress | Should Be 0

            # TODO: Uncomment these checks once we can actually control tunneling type.
            # Test-MPLSoGRE -Session $Sessions[0] | Should Be $true
            # Test-MPLSoGRE -Session $Sessions[1] | Should Be $true
        }

        It "TCP - HTTP connection between containers on separate compute nodes succeeds" {
            Test-TCP `
                -Session $Sessions[1] `
                -SrcContainerName $Container2ID `
                -DstContainerName $Container1ID `
                -DstContainerIP $Container1NetInfo.IPAddress | Should Be 0

            # TODO: Uncomment these checks once we can actually control tunneling type.
            # Test-MPLSoGRE -Session $Sessions[0] | Should Be $true
            # Test-MPLSoGRE -Session $Sessions[1] | Should Be $true
        }

        It "UDP" {
            $MyMessage = "We are Tungsten Fabric. We come in peace."

            Test-UDP `
                -Session1 $Sessions[0] `
                -Session2 $Sessions[1] `
                -Container1Name $Container1ID `
                -Container2Name $Container2ID `
                -Container1IP $Container1NetInfo.IPAddress `
                -Container2IP $Container2NetInfo.IPAddress `
                -Message $MyMessage | Should Be $true

            # TODO: Uncomment these checks once we can actually control tunneling type.
            # Test-MPLSoGRE -Session $Sessions[0] | Should Be $true
            # Test-MPLSoGRE -Session $Sessions[1] | Should Be $true
        }
    }

    Context "MPLSoUDP" {
        # TODO: Enable this test once we can actually control tunneling type.
        It "ICMP - Ping between containers on separate compute nodes succeeds (MPLSoUDP)" -Pending {
            Test-Ping `
                -Session $Sessions[0] `
                -SrcContainerName $Container1ID `
                -DstContainerName $Container2ID `
                -DstContainerIP $Container2NetInfo.IPAddress | Should Be 0

            Test-Ping `
                -Session $Sessions[1] `
                -SrcContainerName $Container2ID `
                -DstContainerName $Container1ID `
                -DstContainerIP $Container1NetInfo.IPAddress | Should Be 0

            Test-MPLSoUDP -Session $Sessions[0] | Should Be $true
            Test-MPLSoUDP -Session $Sessions[1] | Should Be $true
        }
    }

    Context "IP fragmentation" {
        # TODO: Enable this test once fragmentation is properly implemented in vRouter
        It "ICMP - Ping with big buffer succeeds" -Pending {
            $Container1MsgFragmentationThreshold = Get-MaxICMPDataSizeForMTU -MTU $Container1NetInfo.MtuSize
            $Container2MsgFragmentationThreshold = Get-MaxICMPDataSizeForMTU -MTU $Container2NetInfo.MtuSize

            $SrcContainers = @($Container1ID, $Container2ID)
            $DstContainers = @($Container2ID, $Container1ID)
            $DstIPs = @($Container2NetInfo.IPAddress, $Container1NetInfo.IPAddress)
            $BufferSizes = @($Container1MsgFragmentationThreshold, $Container2MsgFragmentationThreshold)

            foreach ($ContainerIdx in @(0, 1)) {
                $BufferSizeLargerBeforeTunnelling = $BufferSizes[$ContainerIdx] + 1
                $BufferSizeLargerAfterTunnelling = $BufferSizes[$ContainerIdx] - 1
                foreach ($BufferSize in @($BufferSizeLargerBeforeTunnelling, $BufferSizeLargerAfterTunnelling)) {
                    Test-Ping `
                        -Session $Sessions[$ContainerIdx] `
                        -SrcContainerName $SrcContainers[$ContainerIdx] `
                        -DstContainerName $DstContainers[$ContainerIdx] `
                        -DstContainerIP $DstIPs[$ContainerIdx] `
                        -BufferSize $BufferSize | Should Be 0
                }
            }
        }

        # TODO: Enable this test once fragmentation is properly implemented in vRouter
        It "UDP - sending big buffer succeeds" -Pending {
            $MsgFragmentationThreshold = Get-MaxUDPDataSizeForMTU -MTU $Container1NetInfo.MtuSize

            $MessageLargerBeforeTunnelling = "a" * $($MsgFragmentationThreshold + 1)
            $MessageLargerAfterTunnelling = "a" * $($MsgFragmentationThreshold - 1)
            foreach ($Message in @($MessageLargerBeforeTunnelling, $MessageLargerAfterTunnelling)) {
                Test-UDP `
                    -Session1 $Sessions[0] `
                    -Session2 $Sessions[1] `
                    -Container1Name $Container1ID `
                    -Container2Name $Container2ID `
                    -Container1IP $Container1NetInfo.IPAddress `
                    -Container2IP $Container2NetInfo.IPAddress `
                    -Message $Message | Should Be $true
            }
        }
    }

    BeforeAll {
        $VMs = Read-TestbedsConfig -Path $TestenvConfFile
        $OpenStackConfig = Read-OpenStackConfig -Path $TestenvConfFile
        $ControllerConfig = Read-ControllerConfig -Path $TestenvConfFile
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments",
            "ContrailNetwork",
            Justification="It's actually used."
        )]
        $SystemConfig = Read-SystemConfig -Path $TestenvConfFile

        $Sessions = New-RemoteSessions -VMs $VMs

        Initialize-PesterLogger -OutDir $LogDir

        Write-Log "Installing components on testbeds..."
        Install-Components -Session $Sessions[0]
        Install-Components -Session $Sessions[1]

        $ContrailNM = [ContrailNetworkManager]::new($OpenStackConfig, $ControllerConfig)
        $ContrailNM.EnsureProject($ControllerConfig.DefaultProject)

        $Testbed1Address = $VMs[0].Address
        $Testbed1Name = $VMs[0].Name
        Write-Log "Creating virtual router. Name: $Testbed1Name; Address: $Testbed1Address"
        $VRouter1Uuid = $ContrailNM.AddVirtualRouter($Testbed1Name, $Testbed1Address)
        Write-Log "Reported UUID of new virtual router: $VRouter1Uuid"

        $Testbed2Address = $VMs[1].Address
        $Testbed2Name = $VMs[1].Name
        Write-Log "Creating virtual router. Name: $Testbed2Name; Address: $Testbed2Address"
        $VRouter2Uuid = $ContrailNM.AddVirtualRouter($Testbed2Name, $Testbed2Address)
        Write-Log "Reported UUID of new virtual router: $VRouter2Uuid"

        Write-Log "Creating virtual network: $NetworkName"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments",
            "ContrailNetwork",
            Justification="It's actually used."
        )]
        $ContrailNetwork = $ContrailNM.AddNetwork($null, $NetworkName, $Subnet)
    }

    AfterAll {
        if (-not (Get-Variable Sessions -ErrorAction SilentlyContinue)) { return }

        if(Get-Variable "VRouter1Uuid" -ErrorAction SilentlyContinue) {
            Write-Log "Removing virtual router: $VRouter1Uuid"
            $ContrailNM.RemoveVirtualRouter($VRouter1Uuid)
            Remove-Variable "VRouter1Uuid"
        }
        if(Get-Variable "VRouter2Uuid" -ErrorAction SilentlyContinue) {
            Write-Log "Removing virtual router: $VRouter2Uuid"
            $ContrailNM.RemoveVirtualRouter($VRouter2Uuid)
            Remove-Variable "VRouter2Uuid"
        }

        Write-Log "Uninstalling components from testbeds..."
        Uninstall-Components -Session $Sessions[0]
        Uninstall-Components -Session $Sessions[1]

        Write-Log "Deleting virtual network"
        if (Get-Variable ContrailNetwork -ErrorAction SilentlyContinue) {
            $ContrailNM.RemoveNetwork($ContrailNetwork)
        }

        Remove-PSSession $Sessions
    }

    BeforeEach {
        Initialize-ComputeNode -Session $Sessions[0] -Subnet $Subnet
        Initialize-ComputeNode -Session $Sessions[1] -Subnet $Subnet

        Write-Log "Creating containers"
        Write-Log "Creating container: $Container1ID"
        New-Container `
            -Session $Sessions[0] `
            -NetworkName $NetworkName `
            -Name $Container1ID `
            -Image $TCPServerDockerImage
        Write-Log "Creating container: $Container2ID"
        New-Container `
            -Session $Sessions[1] `
            -NetworkName $NetworkName `
            -Name $Container2ID `
            -Image "microsoft/windowsservercore"

        Write-Log "Getting containers' NetAdapter Information"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments",
            "Container1NetInfo",
            Justification="It's actually used."
        )]
        $Container1NetInfo = Get-RemoteContainerNetAdapterInformation `
            -Session $Sessions[0] -ContainerID $Container1ID
        $IP = $Container1NetInfo.IPAddress
        Write-Log "IP of ${Container1ID}: $IP"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments",
            "Container2NetInfo",
            Justification="It's actually used."
        )]
        $Container2NetInfo = Get-RemoteContainerNetAdapterInformation `
            -Session $Sessions[1] -ContainerID $Container2ID
        $IP = $Container2NetInfo.IPAddress
        Write-Log "IP of ${Container2ID}: $IP"
    }

    AfterEach {
        try {
            Merge-Logs -LogSources (
                (New-ContainerLogSource -Sessions $Sessions[0] -ContainerNames $Container1ID),
                (New-ContainerLogSource -Sessions $Sessions[1] -ContainerNames $Container2ID)
            )

            Write-Log "Removing all containers"
            Remove-AllContainers -Sessions $Sessions

            Clear-TestConfiguration -Session $Sessions[0] -SystemConfig $SystemConfig
            Clear-TestConfiguration -Session $Sessions[1] -SystemConfig $SystemConfig
        } finally {
            Merge-Logs -LogSources (New-FileLogSource -Path (Get-ComputeLogsPath) -Sessions $Sessions)
        }
    }
}
