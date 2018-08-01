. $PSScriptRoot\..\..\..\CIScripts\Common\Init.ps1

Describe "Windows Linux interoperation tests" {
    It "ICMP connectivity works" -Pending {
        # Test-IcmpLinuxWindowsConnectivity
    }

    It "TCP connectivity works" -Pending {
        # Test-TcpLinuxWindowsConnectivity
    }

    It "UDP connectivity works" -Pending {
        # Test-UdpLinuxWindowsConnectivity
    }
}
