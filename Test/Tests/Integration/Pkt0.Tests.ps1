. $PSScriptRoot\..\..\..\CIScripts\Common\Init.ps1

Describe "pkt0 interface" {
    It "pkt0 appears in vRouter when agent is started" -Pending {
        # Test-InitialPkt0Injection
    }

    It "pkt0 remains injected after agent stops" -Pending {
        # Test-Pkt0RemainsInjectedAfterAgentStops
    }

    It "only one pkt0 exists after agent is restarted" -Pending {
        # Test-OnePkt0ExistsAfterAgentIsRestarted
    }

    It "pkt0 receives traffic when agent is restarted" -Pending {
        # Test-Pkt0ReceivesTrafficAfterAgentIsStarted
    }

    It "gateway ARP is resolved in Agent through pkt0" -Pending {
        # Test-GatewayArpIsResolvedInAgent
    }
}
