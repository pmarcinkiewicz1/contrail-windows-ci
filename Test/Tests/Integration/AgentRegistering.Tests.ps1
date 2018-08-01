. $PSScriptRoot\..\..\..\CIScripts\Common\Init.ps1

Describe "Agent registering" {
    Context "Compute node" {
        It "appears in DnsAgentList" -Pending {
            # Test-ComputeNodeAppearsInDnsAgentList
        }

        It "appears in XMPPDnsData" -Pending {
            # Test-ComputeNodeAppearsInXMPPDnsData
        }

        It "appears in ShowCollectorServer" -Pending {
            # Test-ComputeNodeAppearsInShowCollectorServer
        }
    }
}
