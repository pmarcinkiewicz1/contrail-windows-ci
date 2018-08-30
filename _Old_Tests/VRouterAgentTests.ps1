. $PSScriptRoot\..\..\Common\Aliases.ps1

function New-WaitFileCommand {
    Param ([String] $Path)
    return "while (!(Test-Path $Path)) { Start-Sleep -Milliseconds 300 };"
}

function Wait-RemoteEvent {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [String] $ContainerName,
           [Parameter(Mandatory = $true)] [String] $EventName,
           [Parameter(Mandatory = $false)] [Int] $TimeoutSeconds = 120)

    Invoke-Command -Session $Session -ScriptBlock {
        $TimeoutMilliseconds = $Using:TimeoutSeconds * 1000
        $Command = '[System.Threading.EventWaitHandle]::new($False, [System.Threading.EventResetMode]::AutoReset, \"{0}\").WaitOne({1});' `
            -f $Using:EventName, $TimeoutMilliseconds

        $Res = docker exec $Using:ContainerName powershell -Command $Command
        $Res = [bool]::parse($Res)
        if (!$Res) {
            throw "Waiting for $Using:EventName on $Using:Containername timed out after $Using:TimeoutSeconds seconds"
        }
    }
}

function Set-RemoteEvent {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [String] $ContainerName,
           [Parameter(Mandatory = $true)] [String] $EventName)

    Invoke-Command -Session $Session -ScriptBlock {
        $Command = '[System.Threading.EventWaitHandle]::new($False, [System.Threading.EventResetMode]::AutoReset, \"{0}\").Set() | Out-Null;' `
            -f $Using:EventName

        docker exec $Using:ContainerName powershell -Command $Command
    }
}

function Test-VRouterAgentIntegration {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session1,
           [Parameter(Mandatory = $true)] [PSSessionT] $Session2,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfigurationUdp)

    . $PSScriptRoot\..\Utils\CommonTestCode.ps1
    . $PSScriptRoot\..\Utils\ContrailUtils.ps1

    $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS = 15
    $WAIT_TIME_FOR_FLOW_TABLE_UPDATE_IN_SECONDS = 5

    $AGENT_INSPECTOR_PROTO = "http"
    $AGENT_INSPECTOR_PORT = 8085
    $AGENT_ITF_REQ_PATH = "Snh_ItfReq"
    $AGENT_ARP_REQ_PATH = "Snh_NhListReq?type=arp"

    #
    # Private functions of Test-VRouterAgentIntegration
    #

    function Get-ContainerIPAddress {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [String] $ContainerName)

        return Invoke-Command -Session $Session -ScriptBlock {
            docker inspect -f '{{ range .NetworkSettings.Networks }}{{ .IPAddress }}{{ end }}' $Using:ContainerName
        }
    }

    function Get-TestbedIpAddressFromDns {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

        $testbedHostname = $Session.ComputerName
        $dnsEntries = Resolve-DnsName -Name $testbedHostname -Type A -ErrorVariable dnsError
        if ($dnsError) {
            Throw "Resolving testbed's IP address failed"
        }

        $dnsEntry = $dnsEntries | Where-Object IPAddress -Match "^10.7.0"
        if ($dnsEntry.Count -ne 1) {
            Throw "Expected testbed ${testbedHostname} to have only one IP address"
        }

        return $dnsEntry[0].IPAddress
    }

    function Out-AgentInspectorUri {
        Param ([Parameter(Mandatory = $true)] [string] $IpAddress)

        return "${AGENT_INSPECTOR_PROTO}://${IpAddress}:${AGENT_INSPECTOR_PORT}"
    }

    function Out-AgentInterfaceRequestUri {
        Param ([Parameter(Mandatory = $true)] [string] $IpAddress)

        return "$(Out-AgentInspectorUri $IpAddress)/${AGENT_ITF_REQ_PATH}"
    }

    function Out-AgentArpRequestUri {
        Param ([Parameter(Mandatory = $true)] [string] $IpAddress)

        return "$(Out-AgentInspectorUri $IpAddress)/${AGENT_ARP_REQ_PATH}"
    }

    function Get-PktInterfaceIndexFromAgent {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

        $testbedIpAddress = Get-TestbedIpAddressFromDns -Session $Session
        $uri = Out-AgentInterfaceRequestUri -IpAddress $testbedIpAddress

        # Invoke-RestMethod and Select-XML throw exceptions on error
        $output = Invoke-RestMethod $uri
        $indexNode = $output | Select-XML -XPath "//ItfSandeshData//index[..//type//text() = 'pkt']//text()"
        if (!$indexNode) {
            Throw "No pkt interface in Agent. EXPECTED: pkt interface in Agent"
        }
        $indexValue = [int]$indexNode.Node.Value;

        return $indexValue;
    }

    function Assert-ExtensionIsRunning {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $isEnabled = Test-IsVRouterExtensionEnabled `
            -Session $Session `
            -VMSwitchName $TestConfiguration.VMSwitchName `
            -ForwardingExtensionName $TestConfiguration.ForwardingExtensionName
        if (!$isEnabled) {
            throw "Hyper-V Extension is not running. EXPECTED: Hyper-V Extension is running"
        }
    }

    function Assert-NoVifs {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

        $vifOutput = Invoke-Command -Session $Session -ScriptBlock { vif.exe --list }
        if ($vifOutput -Match "vif") {
            throw "There are vifs registered in vRouter. EXPECTED: no vifs in vRouter"
        }
    }

    function Assert-IsPkt0Injected {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

        $vifOutput = Invoke-Command -Session $Session -ScriptBlock { vif.exe --list }
        $match = $($vifOutput -Match "Type:Agent")
        if (!$match) {
            throw "pkt0 interface is not injected. EXPECTED: pkt0 injected in vRouter"
        }
    }

    function Assert-IsOnlyOnePkt0Injected {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

        $vifOutput = Invoke-Command -Session $Session -ScriptBlock { vif.exe --list }
        $match = $($vifOutput -Match "Type:Agent")
        if (!$match) {
            throw "pkt0 interface is not injected. EXPECTED: pkt0 injected in vRouter"
        }
        if ($match.Count -gt 1) {
            throw "more than 1 pkt0 interfaces were injected. EXPECTED: only one pkt0 interface in vRouter"
        }
    }

    function Assert-IsGatewayArpResolvedInAgent {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

        $testbedIpAddress = Get-TestbedIpAddressFromDns -Session $Session
        $uri = Out-AgentArpRequestUri -IpAddress $testbedIpAddress

        $xpath = "//NhSandeshData//valid[..//sip//text() = '${TEST_NETWORK_GATEWAY}']//text()"
        $output = Invoke-RestMethod $uri
        $gateway = $output | Select-Xml -XPath $xpath
        if (!$gateway) {
            throw "Agent does not expect ARP from gateway, please check Agent config"
        }
        $resolveStatus = $gateway.Node.Value
        if ($resolveStatus -ne "true") {
            throw "ARP to gateway was not resolved. EXPECTED: ARP to gateway resolved by the Agent"
        }
    }

    function Assert-Pkt0HasTraffic {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

        Assert-IsPkt0Injected -Session $Session

        $pktIfIndex = Get-PktInterfaceIndexFromAgent -Session $Session
        $vifOutput = Invoke-Command -Session $Session -ScriptBlock {
            vif.exe --get $Using:pktIfIndex
        }

        $rxPacketsMatch = [regex]::Match($vifOutput, "RX packets:(\d+)")
        if (!$rxPacketsMatch.Success) {
            throw "RX packets metric not visible in vif output. EXPECTED: RX packets visible"
        }
        $rxPackets = [int]$rxPacketsMatch.groups[1].Value
        if ($rxPackets -eq 0) {
            throw "Registered RX packets equal to zero. EXPECTED: Registered RX packets greater than zero"
        }

        $txPacketsMatch = [regex]::Match($vifOutput, "TX packets:(\d+)")
        if (!$txPacketsMatch.Success) {
            throw "TX packets metric not visible in vif output. EXPECTED: TX packets visible"
        }
        $txPackets = [int]$txPacketsMatch.groups[1].Value
        if ($txPackets -eq 0) {
            throw "Registered TX packets equal to zero. EXPECTED: Registered TX packets greater than zero"
        }
    }

    function Assert-FlowEvictedSomeFlows {
        Param ([Parameter(Mandatory = $true)] [Object[]] $Output)

        Foreach ($line in $output) {
            if ($Line -Match "Action:D.*Flags:E") {
                return
            }
        }

        Write-Host "Flow output: $Output"
        throw "There are no evicted flows. EXPECTED: Some flows had been evicted"
    }

    function Assert-SomeFlowsEvicted {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $false)] [String] $Proto)

        if ($Proto) {
            $Output = Invoke-Command -Session $Session -ScriptBlock {
                & flow -l --match "proto $Using:Proto" --show-evicted
            }
        } else {
            $Output = Invoke-Command -Session $Session -ScriptBlock {
                & flow -l --show-evicted
            }
        }

        Assert-FlowEvictedSomeFlows -Output $Output
        Write-Host "        Successfully removed."
    }

    function Assert-FlowReturnedSomeFlows {
        Param ([Parameter(Mandatory = $true)] [Object[]] $Output)
        $ErrorMessage = "There are no flows. EXPECTED: Some flow(s) exist."
        Foreach ($Line in $Output) {
            if ($Line -match "Entries: Created (?<NumOfFlowsCreated>[\d]+) Added (?<NumOfFlowsAdded>[\d]+)[.]*") {
                if ($matches.NumOfFlowsCreated -gt 0 -or $matches.NumOfFlowsAdded -gt 0) {
                    return
                } else {
                    Write-Host "Flow output: $Output"
                    throw $ErrorMessage
                }
            }
        }

        Write-Host "Flow output: $Output"
        throw $ErrorMessage
    }

    function Assert-SomeFlowsReturned {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $false)] [String] $Proto)

        if ($Proto) {
            $FlowOutput = Invoke-Command -Session $Session -ScriptBlock {
                & flow -l --match "proto $Using:Proto"
            }
        } else {
            $FlowOutput = Invoke-Command -Session $Session -ScriptBlock {
                & flow -l
            }
        }

        Assert-FlowReturnedSomeFlows -Output $FlowOutput
        Write-Host "        Successfully created."
    }

    function Assert-ReceivedMessageMatches {
        Param ([Parameter(Mandatory = $true)] [String] $ReceivedMessage,
               [Parameter(Mandatory = $true)] [String] $Message,
               [Parameter(Mandatory = $false)] [Int] $TimeoutSeconds = 10)

        if ($Message -ne $ReceivedMessage) {
            Write-Host "        Sent message: $Message"
            Write-Host "        Received message: $ReceivedMessage"

            throw "Sent and received messages do not match."
        } else {
            Write-Host "        Match!"
        }
    }

    function Start-TcpListener {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [String] $ContainerName,
               [Parameter(Mandatory = $true)] [Int] $Port)

        $Command = (`
            ('$Server = New-Object System.Net.Sockets.TcpListener(\"0.0.0.0\", {0});' -f `
                $Port) +`
            '$Server.Start();' +`
            '[System.Threading.EventWaitHandle]::new($False, [System.Threading.EventResetMode]::AutoReset, \"ServerStarted\").set() | Out-Null;' +`
            '$Connection = $Server.AcceptTcpClient();' +`
            '$StreamReader = New-Object System.IO.StreamReader($Connection.GetStream());' +`
            '$Input = $StreamReader.ReadLine();' +`
            '[System.Threading.EventWaitHandle]::new($False, [System.Threading.EventResetMode]::AutoReset, \"FlowTested\").waitOne() | Out-Null;' +`
            '$StreamReader.Close();' +`
            '$Connection.Close();' +`
            '$Server.Stop();' +`
            'return $Input;'
        )

        Invoke-Command -Session $Session -ScriptBlock {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                "PSUseDeclaredVarsMoreThanAssignments", "",
                Justification="Issue #804 from PSScriptAnalyzer GitHub")]
            $JobListener = Start-Job -ScriptBlock {
                param($ContainerName, $Command)
                $Output = & docker exec $ContainerName powershell -Command $Command
                return $Output
            } -ArgumentList $Using:ContainerName, $Using:Command
        }
    }

    function Start-TcpSender {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [String] $ContainerName,
               [Parameter(Mandatory = $true)] [String] $Message,
               [Parameter(Mandatory = $true)] [String] $ServerIP,
               [Parameter(Mandatory = $true)] [Int] $Port)

        $Command = (`
            ('$Connection = New-Object System.Net.Sockets.TcpClient(\"{0}\", {1});' -f `
                $ServerIP, $Port) +`
            '[System.Threading.EventWaitHandle]::new($false, [System.Threading.EventResetMode]::AutoReset, \"ClientConnected\").set() | Out-Null;' +`
            '$StreamWriter = New-Object System.IO.StreamWriter($Connection.GetStream());' +`
            ('$StreamWriter.WriteLine(\"{0}\");' -f $Message) +`
            '$StreamWriter.Flush();' +`
            '[System.Threading.EventWaitHandle]::new($false, [System.Threading.EventResetMode]::AutoReset, \"FlowTested\").waitOne() | Out-Null;' +`
            '$StreamWriter.Close();' +`
            '$Connection.Close();'
        )

        Invoke-Command -Session $Session -ScriptBlock {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                "PSUseDeclaredVarsMoreThanAssignments", "",
                Justification="Issue #804 from PSScriptAnalyzer GitHub")]
            $JobSender = Start-Job -ScriptBlock {
                param($ContainerName, $Command)
                $Output = & docker exec $ContainerName powershell -Command $Command
                return $Output
            } -ArgumentList $Using:ContainerName, $Using:Command
        }
    }

    function Receive-TcpListener {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

        Invoke-Command -Session $Session {
            Wait-Job $JobListener -Timeout 60 | Out-Null
            Receive-Job $JobListener
            Stop-Job $JobListener
            Remove-Job $JobListener
        }
    }

    function Receive-TcpSender {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

        Invoke-Command -Session $Session {
            Wait-Job $JobSender -Timeout 60 | Out-Null
            Receive-Job $JobSender
            Stop-Job $JobSender
            Remove-Job $JobSender
        }
    }

    function New-ContainerInRemoteSession {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [string] $NetworkName,
               [Parameter(Mandatory = $true)] [string] $ContainerName,
               [Parameter(Mandatory = $false)] [string] $DockerImage = "microsoft/nanoserver")

        Write-Host "Creating container: name = $ContainerName; network = $NetworkName; image = $DockerImage."

        $Output = Invoke-Command -Session $Session -ScriptBlock {
            $DockerOutput = (& docker run -id --name $Using:ContainerName --network $Using:NetworkName $Using:DockerImage powershell 2>&1) | Out-String
            $LASTEXITCODE
            $DockerOutput
        }
        $ExitCode = $Output[0]
        $Message = $Output[1]
        if ($ExitCode -ne 0) {
            Write-Host "    Exit code: $ExitCode"
            Write-Host "    Docker output: $Message"
        }
        return $ExitCode
    }

    function Remove-ContainerInRemoteSession {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [string] $ContainerName)
        $ExitCode = Invoke-Command -Session $Session -ScriptBlock {
            & docker rm --force $Using:ContainerName | Out-Null
            $LASTEXITCODE
        }
        return $ExitCode
    }

    function Send-UDPPacket {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [string] $ContainerName,
               [Parameter(Mandatory = $true)] [string] $IP,
               [Parameter(Mandatory = $false)] [string] $Port,
               [Parameter(Mandatory = $false)] [string] $Message)
        if (!$Port) {
            $Port = "1337"
        }

        if (!$Message) {
            $Message = "Is anyone there!?"
        }

        $Command = (`
            '$IpAddress = [System.Net.IPAddress]::Parse(\"{0}\");' +`
            '$IpEndPoint = New-Object System.Net.IPEndPoint($IpAddress, {1});' +`
            '$UdpClient = New-Object System.Net.Sockets.UdpClient;' +`
            '$Data = [System.Text.Encoding]::UTF8.GetBytes(\"{2}\");' +`
            'Foreach ($num in 1..10) {{$UdpClient.SendAsync($Data, $Data.length, $IpEndPoint); Start-Sleep -Seconds 1}}') -f $IP, $Port, $Message
        Invoke-Command -Session $Session -ScriptBlock {
            & docker exec $Using:ContainerName powershell -Command $Using:Command | Out-Null
        }
    }

    function Test-Ping {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session1,
               [Parameter(Mandatory = $true)] [PSSessionT] $Session2,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration,
               [Parameter(Mandatory = $true)] [string] $Container1Name,
               [Parameter(Mandatory = $true)] [string] $Container2Name)
        Write-Host "======> Given Docker Driver and Extension are running"

        # 1st compute node
        Clear-TestConfiguration -Session $Session1 -TestConfiguration $TestConfiguration
        Initialize-TestConfiguration -Session $Session1 -TestConfiguration $TestConfiguration
        Assert-ExtensionIsRunning -Session $Session1 -TestConfiguration $TestConfiguration

        # 2nd compute node (if there actually is more than 1 compute node)
        if ($Session1 -ne $Session2) {
            Clear-TestConfiguration -Session $Session2 -TestConfiguration $TestConfiguration
            Initialize-TestConfiguration -Session $Session2 -TestConfiguration $TestConfiguration
            Assert-ExtensionIsRunning -Session $Session2 -TestConfiguration $TestConfiguration
        }

        Write-Host "======> Given Agent is running"

        # 1st compute node
        New-AgentConfigFile -Session $Session1 -TestConfiguration $TestConfiguration
        Enable-AgentService -Session $Session1
        Assert-IsAgentServiceEnabled -Session $Session1

        # 2nd compute node (if there actually is more than 1 compute node)
        if ($Session1 -ne $Session2) {
           New-AgentConfigFile -Session $Session2 -TestConfiguration $TestConfiguration
           Enable-AgentService -Session $Session2
           Assert-IsAgentServiceEnabled -Session $Session2
        }

        Start-Sleep -Seconds $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS

        Write-Host "======> When 2 containers belonging to the same network are running"
        $NetworkName = $TestConfiguration.DockerDriverConfiguration.TenantConfiguration.DefaultNetworkName

        $CreateContainer1Success = New-ContainerInRemoteSession `
            -Session $Session1 `
            -NetworkName $NetworkName `
            -ContainerName $Container1Name
        $CreateContainer2Success = New-ContainerInRemoteSession `
            -Session $Session2 `
            -NetworkName $NetworkName `
            -ContainerName $Container2Name

        if ($CreateContainer1Success -ne 0 -or $CreateContainer2Success -ne 0) {
            throw "Container creation failed. EXPECTED: succeeded."
        }
        $Container2IP = Get-ContainerIPAddress -Session $Session2 -ContainerName $Container2Name

        Write-Host "======> Then ping between them succeeds"
        Write-Host "$Container1Name is going to ping $Container2Name (IP: $Container2IP)."
        Ping-Container -Session $Session1 -ContainerName $Container1Name -IP $Container2IP

        Write-Host "Removing containers: $Container1Name and $Container2Name."
        Invoke-Command -Session $Session1 -ScriptBlock {
            & docker rm --force $Using:Container1Name | Out-Null
        }

        Invoke-Command -Session $Session2 -ScriptBlock {
            & docker rm --force $Using:Container2Name | Out-Null
        }
    }

    function Initialize-ComputeNode {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration,
               [Parameter(Mandatory = $true)] [NetworkConfiguration[]] $Networks)

        Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
        Initialize-ComputeServices -Session $Session -TestConfiguration $TestConfiguration -NoNetwork $true
        Foreach ($Network in $Networks) {
            New-DockerNetwork -Session $Session -TestConfiguration $TestConfiguration `
                -Name $Network.Name `
                -Network $Network.Name `
                -Subnet $Network.Subnets[0]
        }
    }
    function Initialize-ComputeNodes {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session1,
               [Parameter(Mandatory = $true)] [PSSessionT] $Session2,
               [Parameter(Mandatory = $true)] [NetworkConfiguration] $Network1,
               [Parameter(Mandatory = $true)] [NetworkConfiguration] $Network2,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        if ($Session1 -eq $Session2) {
            if ($Network1.Name -eq $Network2.Name) {
                $Networks = @($Network1)
            } else {
                $Networks = @($Network1, $Network2)
            }
            Initialize-ComputeNode -Session $Session1 -TestConfiguration $TestConfiguration -Networks $Networks
        } else {
            Initialize-ComputeNode -Session $Session1 -TestConfiguration $TestConfiguration -Networks @($Network1)
            Initialize-ComputeNode -Session $Session2 -TestConfiguration $TestConfiguration -Networks @($Network2)
        }
    }

    #
    # Tests definitions
    #

    function Test-InitialPkt0Injection {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Job.StepQuiet($MyInvocation.MyCommand.Name, {
            Write-Host "===> Running: Test-InitialPkt0Injection"

            Write-Host "======> Given Extension is running"
            Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
            Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
            Assert-ExtensionIsRunning -Session $Session -TestConfiguration $TestConfiguration

            New-AgentConfigFile -Session $Session -TestConfiguration $TestConfiguration

            Write-Host "======> Given clean vRouter"
            Assert-NoVifs -Session $Session

            Write-Host "======> When Agent is started"
            Enable-AgentService -Session $Session
            Assert-IsAgentServiceEnabled -Session $Session
            Start-Sleep -Seconds $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS

            Write-Host "======> Then pkt0 appears in vRouter"
            Assert-IsPkt0Injected -Session $Session

            Write-Host "===> PASSED: Test-InitialPkt0Injection"
        })
    }

    function Test-Pkt0RemainsInjectedAfterAgentStops {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Job.StepQuiet($MyInvocation.MyCommand.Name, {
            Write-Host "===> Running: Test-Pkt0RemainsInjectedAfterAgentStops"

            Write-Host "======> Given Extension is running"
            Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
            Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
            Assert-ExtensionIsRunning -Session $Session -TestConfiguration $TestConfiguration

            New-AgentConfigFile -Session $Session -TestConfiguration $TestConfiguration

            Write-Host "======> Given Agent is running"
            Enable-AgentService -Session $Session
            Assert-IsAgentServiceEnabled -Session $Session
            Start-Sleep -Seconds $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS

            Write-Host "======> Given pkt0 is injected"
            Assert-IsPkt0Injected -Session $Session

            Write-Host "======> When Agent is stopped"
            Disable-AgentService -Session $Session
            Assert-IsAgentServiceDisabled -Session $Session

            Write-Host "======> Then pk0 exists in vRouter"
            Assert-IsPkt0Injected -Session $Session

            Write-Host "===> PASSED: Test-Pkt0RemainsInjectedAfterAgentStops"
        })
    }

    function Test-OnePkt0ExistsAfterAgentIsRestarted {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Job.StepQuiet($MyInvocation.MyCommand.Name, {
            Write-Host "===> Running: Test-OnePkt0ExistsAfterAgentIsRestarted"

            Write-Host "======> Given Extension is running"
            Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
            Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
            Assert-ExtensionIsRunning -Session $Session -TestConfiguration $TestConfiguration

            New-AgentConfigFile -Session $Session -TestConfiguration $TestConfiguration

            Write-Host "======> Given Agent is running"
            Enable-AgentService -Session $Session
            Assert-IsAgentServiceEnabled -Session $Session
            Start-Sleep -Seconds $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS

            Write-Host "======> Given pkt0 is injected"
            Assert-IsPkt0Injected -Session $Session

            Write-Host "======> When Agent is Restarted"
            Disable-AgentService -Session $Session
            Assert-IsAgentServiceDisabled -Session $Session
            Enable-AgentService -Session $Session
            Assert-IsAgentServiceEnabled -Session $Session
            Start-Sleep -Seconds $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS

            Write-Host "======> Then pkt0 exists in vRouter"
            Assert-IsOnlyOnePkt0Injected -Session $Session
        })
    }

    function Test-Pkt0ReceivesTrafficAfterAgentIsStarted {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Job.StepQuiet($MyInvocation.MyCommand.Name, {
            Write-Host "===> Running: Test-Pkt0ReceivesTrafficAfterAgentIsStarted"

            Write-Host "======> Given Extension is running"
            Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
            Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
            Assert-ExtensionIsRunning -Session $Session -TestConfiguration $TestConfiguration

            Write-Host "======> When Agent is started"
            New-AgentConfigFile -Session $Session -TestConfiguration $TestConfiguration
            Enable-AgentService -Session $Session
            Assert-IsAgentServiceEnabled -Session $Session
            Start-Sleep -Seconds $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS  # Wait for KSync

            Write-Host "======> Then Pkt0 has traffic"
            Assert-Pkt0HasTraffic -Session $Session

            Write-Host "===> PASSED: Test-Pkt0ReceivesTrafficAfterAgentIsStarted"
        })
    }

    function Test-GatewayArpIsResolvedInAgent {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Job.StepQuiet($MyInvocation.MyCommand.Name, {
            Write-Host "===> Running: Test-Pkt0ReceivesTrafficAfterAgentIsStarted"

            Write-Host "======> Given Extension is running"
            Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
            Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
            Assert-ExtensionIsRunning -Session $Session -TestConfiguration $TestConfiguration

            Write-Host "======> When Agent is started"
            New-AgentConfigFile -Session $Session -TestConfiguration $TestConfiguration
            Enable-AgentService -Session $Session
            Assert-IsAgentServiceEnabled -Session $Session
            Start-Sleep -Seconds $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS  # Wait for KSync

            Write-Host "======> Then Gateway ARP was resolved through Pkt0"
            Assert-IsGatewayArpResolvedInAgent -Session $Session

            Write-Host "===> PASSED: Test-Pkt0ReceivesTrafficAfterAgentIsStarted"
        })
    }

    function Test-SingleComputeNodePing {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Job.StepQuiet($MyInvocation.MyCommand.Name, {
            Write-Host "===> Running: Test-SingleComputeNodePing"
            Test-Ping -Session1 $Session -Session2 $Session -TestConfiguration $TestConfiguration -Container1Name "container1" -Container2Name "container2"
            Write-Host "===> PASSED: Test-SingleComputeNodePing"
        })
    }

    function Get-VrfStats {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

        $VrfStats = Invoke-Command -Session $Session -ScriptBlock {
            $vrfstatsOutput = $(vrfstats --get 1)
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

    function Test-ICMPoMPLSoGRE {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session1,
               [Parameter(Mandatory = $true)] [PSSessionT] $Session2,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Job.StepQuiet($MyInvocation.MyCommand.Name, {
            Write-Host "===> Running: Test-ICMPoMPLSoGRE"

            Write-Host "======> Given Controller with default (MPLSoGRE) configuration"
            Test-Ping -Session1 $Session1 -Session2 $Session2 -TestConfiguration $TestConfiguration -Container1Name "container1" -Container2Name "container2"

            Write-Host "======> Then GRE tunnel is used"
            $VrfStats = Get-VrfStats -Session $Session1
            if ($VrfStats.MplsGrePktCount -eq 0 -or $VrfStats.MplsUdpPktCount -ne 0 -or $VrfStats.VxlanPktCount -ne 0) {
                throw "Containers pinged themselves correctly but used the wrong type of tunnel (VrfStats: Udp = {0}, Gre = {1}, Vxlan = {2})" `
                    -f $VrfStats.MplsUdpPktCount, $VrfStats.MplsGrePktCount, $VrfStats.VxlanPktCount
            }

            Write-Host "===> PASSED: Test-ICMPoMPLSoGRE"
        })
    }

    function Test-ICMPoMPLSoUDP {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session1,
               [Parameter(Mandatory = $true)] [PSSessionT] $Session2,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Job.StepQuiet($MyInvocation.MyCommand.Name, {
            Write-Host "===> Running: Test-ICMPoMPLSoUDP"

            Write-Host "======> Given Controller with MPLSoUPD configuration"

            $ContrailUrl = $TestConfiguration.ControllerIP + ":" + $TestConfiguration.ControllerRestPort
            $ContrailCredentials = $TestConfiguration.DockerDriverConfiguration
            $AuthToken = Get-AccessTokenFromKeystone -AuthUrl $ContrailCredentials.AuthUrl -TenantName $ContrailCredentials.TenantConfiguration.Name `
                -Username $ContrailCredentials.Username -Password $ContrailCredentials.Password
            $RouterIp1 = Invoke-Command -Session $Session1 -ScriptBlock {
                return $((Get-NetIPAddress -InterfaceAlias $Using:TestConfiguration.VHostName -AddressFamily IPv4).IpAddress)
            }
            $RouterIp2 = Invoke-Command -Session $Session2 -ScriptBlock {
                return $((Get-NetIPAddress -InterfaceAlias $Using:TestConfiguration.VHostName -AddressFamily IPv4).IpAddress)
            }
            $RouterUuid1 = Add-ContrailVirtualRouter -ContrailUrl $ContrailUrl -AuthToken $AuthToken -RouterName $Session1.ComputerName -RouterIp $RouterIp1
            $RouterUuid2 = Add-ContrailVirtualRouter -ContrailUrl $ContrailUrl -AuthToken $AuthToken -RouterName $Session2.ComputerName -RouterIp $RouterIp2

            Try {
                Test-Ping -Session1 $Session1 -Session2 $Session2 -TestConfiguration $TestConfiguration -Container1Name "container1" -Container2Name "container2"
            } Finally {
                Remove-ContrailVirtualRouter -ContrailUrl $ContrailUrl -AuthToken $AuthToken -RouterUuid $RouterUuid1
                Remove-ContrailVirtualRouter -ContrailUrl $ContrailUrl -AuthToken $AuthToken -RouterUuid $RouterUuid2
            }
            Write-Host "======> Then UDP tunnel is used"
            $VrfStats = Get-VrfStats -Session $Session1
            if ($VrfStats.MplsUdpPktCount -eq 0 -or $VrfStats.MplsGrePktCount -ne 0 -or $VrfStats.VxlanPktCount -ne 0) {
                throw "Containers pinged themselves correctly but used the wrong type of tunnel (VrfStats: Udp = {0}, Gre = {1}, Vxlan = {2})" `
                    -f $VrfStats.MplsUdpPktCount, $VrfStats.MplsGrePktCount, $VrfStats.VxlanPktCount
            }

            Write-Host "===> PASSED: Test-ICMPoMPLSoUDP"
        })
    }

    function Test-FlowsAreInjectedOnIcmpTraffic {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session1,
               [Parameter(Mandatory = $true)] [PSSessionT] $Session2,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Job.StepQuiet($MyInvocation.MyCommand.Name, {
            Write-Host "===> Running: Test-FlowsAreInjectedOnIcmpTraffic"

            $TenantConfiguration = $TestConfiguration.DockerDriverConfiguration.TenantConfiguration

            Write-Host "======> Given: Contrail compute services are started"
            Initialize-ComputeNodes -Session1 $Session1 -Session2 $Session2 `
                -Network1 $TenantConfiguration.NetworkWithPolicy1 -Network2 $TenantConfiguration.NetworkWithPolicy2 `
                -TestConfiguration $TestConfiguration
            Start-Sleep -Seconds $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS

            Write-Host "======> When 2 containers belonging to different networks are running"
            $Network1Name = $TenantConfiguration.NetworkWithPolicy1.Name
            $Network2Name = $TenantConfiguration.NetworkWithPolicy2.Name
            $Container1Name = "jolly-lumberjack"
            $Container2Name = "juniper-tree"

            $CreateContainer1Success = New-ContainerInRemoteSession `
                -Session $Session1 `
                -NetworkName $Network1Name `
                -ContainerName $Container1Name
            $CreateContainer2Success = New-ContainerInRemoteSession `
                -Session $Session2 `
                -NetworkName $Network2Name `
                -ContainerName $Container2Name

            if ($CreateContainer1Success -ne 0 -or $CreateContainer2Success -ne 0) {
                throw "Container creation failed. EXPECTED: succeeded."
            }

            $Container2IP = Get-ContainerIPAddress -Session $Session2 -ContainerName $Container2Name

            Write-Host "======> When: Container $Container1Name (network: $Network1Name)"
            Write-Host "        pings container $Container2Name (network: $Network2Name, IP: $Container2IP)"
            Ping-Container -Session $Session1 -ContainerName $Container1Name -IP $Container2IP

            Write-Host "======> Then: Flow should be created for ICMP protocol"
            Assert-SomeFlowsReturned -Session $Session1 -Proto "icmp"

            Write-Host "Removing containers: $Container1Name and $Container2Name."
            Remove-ContainerInRemoteSession -Session $Session1 -ContainerName $Container1Name | Out-Null
            Remove-ContainerInRemoteSession -Session $Session2 -ContainerName $Container2Name | Out-Null

            Write-Host "===> PASSED: Test-FlowsAreInjectedOnIcmpTraffic"
        })
    }
    function Test-FlowsAreInjectedAndEvictedOnTcpTraffic {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Name = $MyInvocation.MyCommand.Name

        $Job.StepQuiet($Name, {
            Test-Tcp `
                -Name $Name `
                -Session1 $Session `
                -Session2 $Session `
                -TestConfiguration $TestConfiguration
        })
    }

    function Test-MultihostTcpTraffic {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session1,
               [Parameter(Mandatory = $true)] [PSSessionT] $Session2,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Name = $MyInvocation.MyCommand.Name

        $Job.StepQuiet($Name, {
            Test-Tcp `
                -Name $Name `
                -Session1 $Session1 `
                -Session2 $Session2 `
                -TestConfiguration $TestConfiguration
         })
    }

    function Test-Tcp {
        Param ([Parameter(Mandatory = $true)] [String] $Name,
               [Parameter(Mandatory = $true)] [PSSessionT] $Session1,
               [Parameter(Mandatory = $true)] [PSSessionT] $Session2,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration,
               [Parameter(Mandatory = $false)] [NetworkConfiguration] $Network1,
               [Parameter(Mandatory = $false)] [NetworkConfiguration] $Network2,
               [Parameter(Mandatory = $false)] [Bool] $TestFlowInjection = $true,
               [Parameter(Mandatory = $false)] [Bool] $TestFlowEviction = $true)

        if (!$Network1) {
            $Network1 = $TestConfiguration.DockerDriverConfiguration.TenantConfiguration.NetworkWithPolicy1
        }

        if (!$Network2) {
            $Network2 = $TestConfiguration.DockerDriverConfiguration.TenantConfiguration.NetworkWithPolicy2
        }

        Write-Host "===> Running: $Name"

        Write-Host "======> Given: Contrail compute services are started"

        Initialize-ComputeNodes -Session1 $Session1 -Session2 $Session2 `
            -Network1 $Network1 -Network2 $Network2 -TestConfiguration $TestConfiguration
        Start-Sleep -Seconds $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS

        if ($Network1.Name -eq $Network2.Name) {
            $different = ""
        } else {
            $different = " belonging to different networks"
        }
        Write-Host "======> When 2 containers$different are running"

        $Container1Name = "jolly-lumberjack"
        $Container2Name = "juniper-tree"

        $CreateContainer1Success = New-ContainerInRemoteSession `
            -Session $Session1 `
            -NetworkName $Network1.Name `
            -ContainerName $Container1Name `
            -DockerImage 'microsoft/windowsservercore'
        $CreateContainer2Success = New-ContainerInRemoteSession `
            -Session $Session2 `
            -NetworkName $Network2.Name `
            -ContainerName $Container2Name `
            -DockerImage 'microsoft/windowsservercore'

        if ($CreateContainer1Success -ne 0 -or $CreateContainer2Success -ne 0) {
            throw "Container creation failed. EXPECTED: succeeded."
        }

        $Container2IP = Get-ContainerIPAddress -Session $Session2 -ContainerName $Container2Name

        Write-Host "======> When: Container $Container1Name (network: $($Network1.Name) is trying to"
        Write-Host "        open TCP connection to $Container2Name (network: $($Network2.Name), IP: $Container2IP)"
        Write-Host

        $Port = "1905"
        $Message = "Even diamonds require polishing."

        Write-Host "        Setting up TCP sender and listener on containers..."

        Start-TcpListener -Session $Session2 -ContainerName $Container2Name -Port $Port

        Write-Host "        Waiting for server-started"
        Wait-RemoteEvent -Session $Session2 -ContainerName $Container2Name -EventName "ServerStarted"

        Start-TcpSender -Session $Session1 -ContainerName $Container1Name `
            -Message $Message -ServerIP $Container2IP -Port $Port

        Write-Host "        Waiting for client-connected"
        Wait-RemoteEvent -Session $Session1 -ContainerName $Container1Name -EventName "ClientConnected"

        Start-Sleep -Seconds $WAIT_TIME_FOR_FLOW_TABLE_UPDATE_IN_SECONDS

        if ($TestFlowInjection) {
            Write-Host "======> Then: Flow should be created for TCP protocol"
            Assert-SomeFlowsReturned -Session $Session1 -Proto "tcp"
        }

        Set-RemoteEvent -Session $Session1 -ContainerName $Container1Name -EventName "FlowTested"
        Set-RemoteEvent -Session $Session2 -ContainerName $Container2Name -EventName "FlowTested"

        Write-Host "======> When: The TCP connection is closed"

        Receive-TcpSender -Session $Session1
        $ReceivedMessage = Receive-TcpListener -Session $Session2

        Write-Host "======> Then: Payload should be transferred correctly"
        Assert-ReceivedMessageMatches -Message $Message -ReceivedMessage $ReceivedMessage

        if ($TestFlowEviction) {
            Write-Host "======> Then: Flow should be removed"
            foreach ($Session in @($Session1, $Session2) | Get-Unique) {
                Assert-SomeFlowsEvicted -Session $Session1 -Proto "tcp"
            }
        }

        Write-Host "Removing containers: $Container1Name and $Container2Name."
        Remove-ContainerInRemoteSession -Session $Session1 -ContainerName $Container1Name | Out-Null
        Remove-ContainerInRemoteSession -Session $Session2 -ContainerName $Container2Name | Out-Null

        Write-Host "===> PASSED: $Name"
    }

    function Test-FlowsAreInjectedOnUdpTraffic {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Job.StepQuiet($MyInvocation.MyCommand.Name, {
            Write-Host "===> Running: Test-FlowsAreInjectedOnUdpTraffic"

            $TenantConfiguration = $TestConfiguration.DockerDriverConfiguration.TenantConfiguration

            Write-Host "======> Given: Contrail compute services are started"
            Initialize-ComputeNodes -Session1 $Session -Session2 $Session `
                -Network1 $TenantConfiguration.NetworkWithPolicy1 -Network2 $TenantConfiguration.NetworkWithPolicy2 `
                -TestConfiguration $TestConfiguration
            Start-Sleep -Seconds $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS

            Write-Host "======> When 2 containers belonging to different networks are running"
            $Network1Name = $TenantConfiguration.NetworkWithPolicy1.Name
            $Network2Name = $TenantConfiguration.NetworkWithPolicy2.Name
            $Container1Name = "jolly-lumberjack"
            $Container2Name = "juniper-tree"

            $CreateContainer1Success = New-ContainerInRemoteSession `
                -Session $Session `
                -NetworkName $Network1Name `
                -ContainerName $Container1Name
            $CreateContainer2Success = New-ContainerInRemoteSession `
                -Session $Session `
                -NetworkName $Network2Name `
                -ContainerName $Container2Name

            if ($CreateContainer1Success -ne 0 -or $CreateContainer2Success -ne 0) {
                throw "Container creation failed. EXPECTED: succeeded."
            }

            $Container2IP = Get-ContainerIPAddress -Session $Session -ContainerName $Container2Name

            Write-Host "======> When: Container $Container1Name (network: $Network1Name) is sending UDP"
            Write-Host "        packets to container $Container2Name (network: $Network2Name, IP: $Container2IP)"
            Send-UDPPacket -Session $Session -ContainerName $Container1Name -IP $Container2IP
            Start-Sleep -Seconds $WAIT_TIME_FOR_FLOW_TABLE_UPDATE_IN_SECONDS

            Write-Host "======> Then: Flow should be created for UDP protocol"
            Assert-SomeFlowsReturned -Session $Session -Proto "udp"

            Write-Host "Removing containers: $Container1Name and $Container2Name."
            Remove-ContainerInRemoteSession -Session $Session -ContainerName $Container1Name | Out-Null
            Remove-ContainerInRemoteSession -Session $Session -ContainerName $Container2Name | Out-Null

            Write-Host "===> PASSED: Test-FlowsAreInjectedOnUdpTraffic"
        })
    }

    function Test-MultihostUdpTraffic {
        Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session1,
               [Parameter(Mandatory = $true)] [PSSessionT] $Session2,
               [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

        $Job.StepQuiet($MyInvocation.MyCommand.Name, {
            Write-Host "===> Running: Test-MultihostUdpTraffic"

            $TenantConfiguration = $TestConfiguration.DockerDriverConfiguration.TenantConfiguration

            Write-Host "======> Given: Contrail compute services are started on two compute nodes"
            Initialize-ComputeNodes -Session1 $Session1 -Session2 $Session2 `
                -Network1 $TenantConfiguration.NetworkWithPolicy1 -Network2 $TenantConfiguration.NetworkWithPolicy2 `
                -TestConfiguration $TestConfiguration
            Start-Sleep -Seconds $WAIT_TIME_FOR_AGENT_INIT_IN_SECONDS

            Write-Host "======> When 2 containers belonging to different networks are running"
            $Network1Name = $TenantConfiguration.NetworkWithPolicy1.Name
            $Network2Name = $TenantConfiguration.NetworkWithPolicy2.Name

            $Container1Name = "jolly-lumberjack"
            $Container2Name = "juniper-tree"

            $CreateContainer1Success = New-ContainerInRemoteSession `
                -Session $Session1 `
                -NetworkName $Network1Name `
                -ContainerName $Container1Name `
                -DockerImage "microsoft/windowsservercore"
            $CreateContainer2Success = New-ContainerInRemoteSession `
                -Session $Session2 `
                -NetworkName $Network2Name `
                -ContainerName $Container2Name `
                -DockerImage "microsoft/windowsservercore"

            if ($CreateContainer1Success -ne 0 -or $CreateContainer2Success -ne 0) {
                throw "Container creation failed. EXPECTED: succeeded."
            }

            $Container2IP = Get-ContainerIPAddress -Session $Session2 -ContainerName $Container2Name

            Write-Host "======> When: Container $Container1Name (network: $Network1Name) is sending UDP"
            Write-Host "        packets to container $Container2Name (network: $Network2Name, IP: $Container2IP)"

            $Port = "1905"
            $Message = "Even diamonds require polishing."

            Write-Host "    Setting up a listener on container $Container2Name..."
            Invoke-Command -Session $Session2 -ScriptBlock {
                $Command = (`
                    '$IpEndPoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, {0});' +`
                    '$UdpClient = New-Object System.Net.Sockets.UdpClient {0};' +`
                    '$Task = $UdpClient.ReceiveAsync();' +`
                    '[System.Threading.EventWaitHandle]::new($False, [System.Threading.EventResetMode]::AutoReset, \"Listening\").Set() | Out-Null;' +`
                    '$Task.Wait();' +`
                    '$ReceivedMessage = [System.Text.Encoding]::UTF8.GetString($Task.Result.Buffer);' +`
                    'return $ReceivedMessage;') -f $Using:Port

                [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                    "PSUseDeclaredVarsMoreThanAssignments", "",
                    Justification="Issue #804 from PSScriptAnalyzer GitHub")]
                $JobListener = Start-Job -ScriptBlock {
                    Param ($ContainerName, $Command)
                    & docker exec $ContainerName powershell -Command $Command
                } -ArgumentList $Using:Container2Name, $Command
            }

            # I'm not sure if UdpClient is guaranteed to be already listening when ReceiveAsync returns,
            # so there might be a need for additional waiting after Wait-RemoteEvent
            # (althought testing shows that such a delay is probably not necessary).
            Wait-RemoteEvent -Session $Session2 -ContainerName $Container2Name -EventName "Listening"
            Write-Host "    Sending a message from container $Container1Name..."
            Send-UDPPacket -Session $Session1 -ContainerName $Container1Name -IP $Container2IP -Port $Port -Message $Message
            $ReceivedMessage = Invoke-Command -Session $Session2 -ScriptBlock {
                $JobListener | Wait-Job -Timeout 20 | Out-Null
                $JobListener | Stop-Job | Out-Null
                $JobListener | Receive-Job
                $JobListener | Remove-Job
            }
            $ReceivedMessage

            Start-Sleep -Seconds $WAIT_TIME_FOR_FLOW_TABLE_UPDATE_IN_SECONDS
            Write-Host "======> Then: Flow should be created for UDP protocol on the compute node of $Container1Name"
            Write-Host "        and container $Container2Name should receive the message."
            Assert-SomeFlowsReturned -Session $Session1 -Proto "udp"
            Assert-ReceivedMessageMatches -Message $Message -ReceivedMessage $ReceivedMessage

            Write-Host "Removing containers: $Container1Name and $Container2Name."
            Remove-ContainerInRemoteSession -Session $Session1 -ContainerName $Container1Name | Out-Null
            Remove-ContainerInRemoteSession -Session $Session2 -ContainerName $Container2Name | Out-Null

            Write-Host "===> PASSED: Test-MultihostUdpTraffic"
        })
    }

    $Job.StepQuiet($MyInvocation.MyCommand.Name, {
        Test-InitialPkt0Injection -Session $Session1 -TestConfiguration $TestConfiguration
        Test-Pkt0RemainsInjectedAfterAgentStops -Session $Session1 -TestConfiguration $TestConfiguration
        Test-OnePkt0ExistsAfterAgentIsRestarted -Session $Session1 -TestConfiguration $TestConfiguration
        Test-Pkt0ReceivesTrafficAfterAgentIsStarted -Session $Session1 -TestConfiguration $TestConfiguration
        Test-GatewayArpIsResolvedInAgent -Session $Session1 -TestConfiguration $TestConfiguration
        Test-SingleComputeNodePing -Session $Session1 -TestConfiguration $TestConfiguration
        Test-ICMPoMPLSoGRE -Session1 $Session1 -Session2 $Session2 -TestConfiguration $TestConfiguration
        Test-ICMPoMPLSoUDP -Session1 $Session1 -Session2 $Session2 -TestConfiguration $TestConfigurationUdp
        Test-FlowsAreInjectedOnIcmpTraffic -Session1 $Session1 -Session2 $Session2 -TestConfiguration $TestConfiguration
        Test-FlowsAreInjectedAndEvictedOnTcpTraffic -Session $Session1 -TestConfiguration $TestConfiguration
        Test-FlowsAreInjectedOnUdpTraffic -Session $Session1 -TestConfiguration $TestConfiguration
        Test-MultihostTcpTraffic -Session1 $Session1 -Session2 $Session2 -TestConfiguration $TestConfiguration
        Test-MultihostUdpTraffic -Session1 $Session1 -Session2 $Session2 -TestConfiguration $TestConfiguration
    })

    # Test cleanup
    Clear-TestConfiguration -Session $Session1 -TestConfiguration $TestConfiguration
    Clear-TestConfiguration -Session $Session2 -TestConfiguration $TestConfiguration
}
