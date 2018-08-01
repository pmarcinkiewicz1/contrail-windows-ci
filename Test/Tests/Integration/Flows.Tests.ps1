. $PSScriptRoot\..\..\..\CIScripts\Common\Init.ps1

Describe "Flows" {
    It "injects flows on ICMP traffic" -Pending {
        # Test-FlowsAreInjectedOnIcmpTraffic
    }

    It "flows are injected and evicted on TCP traffic when session is closed" -Pending {
        # TODO: Is test name correct?
        # Test-FlowsAreInjectedAndEvictedOnTcpTraffic
    }

    It "injects flows on UDP traffic" -Pending {
        # Test-FlowsAreInjectedOnUdpTraffic
    }
}
