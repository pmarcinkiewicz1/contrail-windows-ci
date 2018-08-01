. $PSScriptRoot\..\..\..\CIScripts\Common\Init.ps1

Describe "SNAT manual setup" {
    It "cleans up VMA" -Pending {
        # Test-VMAShouldBeCleanedUp
    }

    It "cleans up VHDX" -Pending {
        # Test-VHDXShouldBeCleanedUp
    }

    It "can ping endhost from container via SNAT" -Pending {
        # Test-CanPingEndhostFromContainer
    }
}
