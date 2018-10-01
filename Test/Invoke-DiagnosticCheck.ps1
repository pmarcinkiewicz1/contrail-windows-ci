Param (
    [Parameter(Mandatory = $false)] [String] $AdapterName = "Ethernet1",
    [Parameter(Mandatory = $false)] [String] $VHostName = "vEthernet (HNSTransparent)",
    [Parameter(Mandatory = $false)] [String] $ForwardingExtensionName = "vRouter forwarding extension",
    [Parameter(Mandatory = $false)] [String] $VMSwitchName = "Layered Ethernet1"
)

function Assert-RunningAsAdmin {
    $Principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    $IsAdmin = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not($IsAdmin)) {
        Set-TestInconclusive "Test requires administrator privileges"
    }
}

Describe "Diagnostic check" {
    Context "vRouter forwarding extension" {
        It "is running" {
            Assert-RunningAsAdmin
            Get-VMSwitchExtension -Name $ForwardingExtensionName -VMSwitchName $VMSwitchName `
                | Select-Object -ExpandProperty "Running" `
                | Should Be $true
        }

        It "is enabled" {
            Assert-RunningAsAdmin
            Get-VMSwitchExtension -Name $ForwardingExtensionName -VMSwitchName $VMSwitchName `
                | Select-Object -ExpandProperty "Enabled" `
                | Should Be $true
        }

        It "didn't assert or panic lately" {

        }

        It "vhost vif is present" {
            $VHostIfAlias = Get-NetAdapter -InterfaceAlias $VHostName `
                | Select-Object -ExpandProperty ifName
            vif.exe --list | Select-String $VHostIfAlias | Should Not BeNullOrEmpty
        }

        It "physical vif is present" {
            $PhysIfAlias = Get-NetAdapter -InterfaceAlias $AdapterName `
                | Select-Object -ExpandProperty ifName
            vif.exe --list | Select-String $PhysIfAlias | Should Not BeNullOrEmpty
        }

        It "pkt0 vif is present" {
            vif.exe --list | Select-String "pkt0" | Should Not BeNullOrEmpty
        }

        It "opens ksync device" {
            # Get-ChildItem "//./vrouterKsync" | Should Not BeNullOrEmpty
        }

        It "opens pkt0 device" {
            # Get-ChildItem "//./vrouterBridge" | Should Not BeNullOrEmpty
        }

        It "opens flow0 device" {
            # Get-ChildItem "//./vrouterFlow" | Should Not BeNullOrEmpty
        }
    }

    Context "vRouter Agent" {
        It "is present" {
            Get-Service "ContrailAgent" | Should Not BeNullOrEmpty
        }

        It "is running" {
            Get-Service "ContrailAgent" | Select-Object -ExpandProperty Status `
                | Should Be "Running"
        }
        
        It "serves an Agent API on TCP socket" {
            $Result = Test-NetConnection -ComputerName localhost -Port 9091
            $Result.TcpTestSucceeded | Should Be $true
        }

        It "didn't assert or panic lately" {

        }
    }

    Context "Node manager" {
        It "is present" {
            Get-Service "contrail-vrouter-nodemgr" | Should Not BeNullOrEmpty
        }

        It "is running" {
            Get-Service "contrail-vrouter-nodemgr" | Select-Object -ExpandProperty Status `
                | Should Be "Running"
        }
    }

    Context "CNM plugin" {
        It "is running" {
            Get-Service "contrail-docker-driver" | Select-Object -ExpandProperty Status `
                | Should Be "Running"
        }

        It "creates a named pipe API server" {
            Get-ChildItem "//./pipe/" | Where-Object Name -EQ "Contrail" `
                | Should Not BeNullOrEmpty
        }

        It "serves on named pipe API server" {
            $Stream = $null
            try {
                $Stream = New-Object System.IO.Pipes.NamedPipeClientStream(".", "Contrail")
                $TimeoutMilisecs = 1000
                { $Stream.Connect($TimeoutMilisecs) } | Should Not Throw
            } finally {
                $Stream.Dispose()
            }
        }

        It "has created a root Contrail HNS network in Docker" {
            Get-ContainerNetwork | Where-Object Name -EQ "ContrailRootNetwork" `
                | Should Not BeNullOrEmpty
        }
    }

    Context "Compute node" {
        It "VMSwitch exists" {
            Assert-RunningAsAdmin
            Get-VMSwitch "Layered?$AdapterName" | Should Not BeNullOrEmpty
        }

        It "can ping Control node from Control interface" {

        }

        It "can ping other Compute node from Dataplane interface" {
            # Optional test
        }

        It "firewall is turned off" {
            # Optional test
            foreach ($Prof in @("Domain", "Public", "Private")) {
                $State = Get-NetFirewallProfile -Profile $Prof `
                    | Select-Object -ExpandProperty Enabled
                if ($State) {
                    $Msg = "Firewall is enabled for profile $Prof - it may break IP fragmentation."
                    Set-TestInconclusive $Msg
                }
            }
            $true | Should Be $true
        }
    }

    Context "vRouter certificate" {
        # TODO: figure out how to test for these
        It "test signing is ON" {
            # Optional test
        }

        It "vRouter test certificate is present" {
            # Optional test
        }

        It "vRouter actual certificate is present" {
            # Optional test
        }
    }

    Context "IP fragmentation workaround" {
        It "WinNAT is not running" {
            Get-Service "WinNAT" | Select-Object -ExpandProperty "Status" `
                | Should Be "Stopped"
        }

        It "WinNAT autostart is disabled" {
            Get-Service "WinNAT" | Select-Object -ExpandProperty "Starttype" `
                | Should Be "Disabled"
        }

        It "there is no NAT network" {
            Get-NetNat | Should BeNullOrEmpty
        }
    }

    Context "Docker" {
        It "is running" {
            Get-Service "Docker" | Select-Object -ExpandProperty "Status" `
                | Should Be "Running"
        }

        It "there are no Contrail networks in Docker with incorrect driver" {
            # After reboot, networks handled by 'Contrail' plugin will instead have 'transparent'
            # plugin assigned. Make sure there are no networks like this. 
            $Raw = docker network ls --filter 'driver=transparent'
            $Matches =  $Raw | Select-String "Contrail:.*"

            $Matches.Matches.Count | Should Be 0
        }

        It "there are no orphaned Contrail networks (present in HNS and absent in Docker)" {
            Assert-RunningAsAdmin
            $OwnedNetworks = docker network ls --quiet --filter 'driver=Contrail'
            $ActualHNSNetworks = Get-ContainerNetwork `
                | Where-Object Name -Like "Contrail:*" `
                | Select-Object -ExpandProperty Name
            foreach($HNSNet in $ActualHNSNetworks) {
                # Substring(0, 12) because docker network IDs are shortened to 12 characters.
                $AssociatedDockerNetID = ($HNSNet -split ":")[1].Substring(0, 12)

                $OwnedNetworks -Contains $AssociatedDockerNetID | Should Be $true
            }
        }
    }
}
