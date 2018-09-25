# Runs diagnostic check against remote Windows hosts (if TestenvConfFile is defined) or against
# localhost (if TestenvConfFile is not defined).
# Verifies Windows Contrail services and other assumptions about the configuration.

Param(
    [Parameter(Mandatory = $false)] [string] $TestenvConfFile
)

function Test-RunningAsAdmin {
    $Principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Describe "Diagnostic check" {
    Context "vRouter forwarding extension" {
        It "is running" {

        }

        It "is enabled" {

        }

        It "didn't assert or panic lately" {

        }

        It "vhost vif is present" {

        }

        It "physical vif is present" {

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
            Get-Service "ContrailAgent" | Select-Object -ExpandProperty Status | Should Be "Running"
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
            Get-Service "contrail-vrouter-nodemgr" | Select-Object -ExpandProperty Status | Should Be "Running"
        }
    }

    Context "CNM plugin" {
        It "is running" {
            Get-Service "contrail-docker-driver" | Select-Object -ExpandProperty Status | Should Be "Running"
        }

        It "serves a named pipe API server" {
            Get-ChildItem "//./pipe/" | Where-Object Name -EQ "Contrail" | Should Not BeNullOrEmpty
        }

        It "responds to GetCapabilities CNM request" {

        }

        It "has created a root Contrail HNS network in Docker" {
            Get-ContainerNetwork | Where-Object Name -EQ "ContrailRootNetwork" | Should Not BeNullOrEmpty
        }
    }

    Context "Compute node" {
        It "VMSwitch exists" {
            if (-not(Test-RunningAsAdmin)) {
                Set-TestInconclusive "Test requires administrator priveleges"
            }
            Get-VMSwitch "Layered*" | Should Not BeNullOrEmpty
        }

        It "can ping Control node from Control interface" {

        }

        It "can ping other Compute node from Dataplane interface" {
            # Optional test
        }

        It "firewall is turned off" {
            # Optional test
        }

        It "test signing is ON" {
            # Optional test
        }
    }
    Context "IP fragmentation workaround" {
        It "WinNAT is not running" {
            Get-Service "WinNAT" | Select-Object -ExpandProperty "Status" | Should Be "Stopped"
        }

        It "WinNAT autostart is disabled" {
            Get-Service "WinNAT" | Select-Object -ExpandProperty "Starttype" | Should Be "Disabled"
        }

        It "there is no NAT network" {
            Get-NetNat | Should BeNullOrEmpty
        }
    }

    Context "Docker" {
        It "is running" {
            Get-Service "Docker" | Select-Object -ExpandProperty "Status" | Should Be "Running"
        }

        It "there are no Contrail networks in Docker with incorrect driver" {
            # After reboot, networks handled by 'Contrail' plugin will instead have 'transparent'
            # plugin assigned. Make sure there are no networks like this. 
            $Raw = docker network ls --filter 'driver=transparent'
            $Matches =  $Raw | Select-String "Contrail:.*"

            $Matches.Matches.Count | Should Be 0
        }

        It "there are no orphaned Contrail networks (present in HNS and absent in Docker)" {
            $OwnedNetworks = docker network ls --quiet --filter 'driver=Contrail'
            $ActualHNSNetworks = Get-ContainerNetwork | Where Name -Like "Contrail:*" `
                | Select -ExpandProperty Name
            foreach($HNSNet in $ActualHNSNetworks) {
                # Substring(0, 12) because docker network IDs are shortened to 12 characters.
                $AssociatedDockerNetID = ($HNSNet -split ":")[1].Substring(0, 12)

                $OwnedNetworks -Contains $AssociatedDockerNetID | Should Be $true
            }
        }
    }
}
