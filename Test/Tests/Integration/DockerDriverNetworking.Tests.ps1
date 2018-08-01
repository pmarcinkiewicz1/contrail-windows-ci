. $PSScriptRoot\..\..\..\CIScripts\Common\Init.ps1

Describe "Docker driver networking" {
    Context "conflicting local IPs" {
        It "can create containers for different tenants with same IP" -Pending {
            # DockerDriverMultitenancyTests.ps1
        }
    }

    Context "network with single subnet" {
        It "creates a network with default, non-specified subnet correctly" -Pending {
            # Test-SingleNetworkSingleSubnetDefault
        }

        It "creates a network with explicitly specified subnet correctly" -Pending {
            # TODO: Does this mean that it's specified in controller? Test name
            # should probably be more expressive...
            # Test-SingleNetworkSingleSubnetExplicit
        }

        It "does not create a network with invalid subnet" -Pending {
            # TODO: What does "invalid" mean? Need to fix test name.
            # Test-SingleNetworkSingleSubnetInvalid
        }
    }

    Context "network with multiple subnets" {
        It "does not create a network without explicitly specifying a subnet" -Pending {
            # Test-SingleNetworkMultipleSubnetsDefault
        }

        It "creates a network with first subnet specified" -Pending {
            # Test-SingleNetworkMultipleSubnetsExplicitFirst
        }

        It "creates a network with second subnet specified" -Pending {
            # TODO: maybe merge this test with "creates a network with first
            # subnet specified" test?
            # Test-SingleNetworkMultipleSubnetsExplicitSecond
        }

        It "does not create a newtork with invalid subnet" -Pending {
            # TODO: again, what does "invalid" mean here?
            # Test-SingleNetworkMultipleSubnetsInvalid
        }
    }

    Context "multiple networks with multiple subnets each" {
        It "creates multiple networks with multiple subnets correctly" -Pending {
            # TODO: this test case seems to broad maybe?
            # Test-MultipleNetworksMultipleSubnetsAllSimultaneously
        }
    }
}
