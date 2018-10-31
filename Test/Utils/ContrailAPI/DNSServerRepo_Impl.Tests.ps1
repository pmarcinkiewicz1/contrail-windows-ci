Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(ValueFromRemainingArguments=$true)] $UnusedParams
)

. $PSScriptRoot\DNSServerRepo.ps1
. $PSScriptRoot\IPAMRepo.ps1
. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testenv.ps1

# TODO: Those tests run on working Controller.
#       Most probably they need to be rewritten
#       to use some fake.
Describe 'Contrail DNS API' -Tags CI, Systest {
    BeforeAll {
        $OpenStackConfig = Read-OpenStackConfig -Path $TestenvConfFile
        $ControllerConfig = Read-ControllerConfig -Path $TestenvConfFile
        $ContrailNM = [ContrailNetworkManager]::New($OpenStackConfig, $ControllerConfig)

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments",
            "DNSServer",
            Justification="It's actually used."
        )]
        $DNSServerRepo = [DNSServerRepo]::New($ContrailNM)
    }

    Context 'DNS server creation and removal' {

        It 'can add and remove not attached to ipam DNS server without records' {
            {
                $Server = [DNSServer]::New("CreatedByPS1ScriptEmpty")
                $DNSServerRepo.AddDNSServer($Server)
                $DNSServerRepo.RemoveDNSServer($Server)
            } | Should -Not -Throw
        }

        It 'can remove DNS server by name' {
            {
                $DNSServerRepo.AddDNSServer([DNSServer]::New("CreatedByPS1ScriptByName"))
                $DNSServerRepo.RemoveDNSServer([DNSServer]::New("CreatedByPS1ScriptByName"))
            } | Should -Not -Throw
        }

        It 'can add and remove DNS server records' {
            $Server = [DNSServer]::New("CreatedByPS1ScriptRecords")
            $DNSServerRepo.AddDNSServer($Server)
            {
                Try
                {
                    $Record1 = [DNSRecord]::New("host1", "1.2.3.4", "A", $Server.GetFQName())
                    $Record2 = [DNSRecord]::New("host2", "1.2.3.5", "A", $Server.GetFQName())

                    $DNSServerRepo.AddDNSRecord($Record1)
                    $DNSServerRepo.AddDNSRecord($Record2)

                    $DNSServerRepo.RemoveDNSRecord($Record1)
                    $DNSServerRepo.RemoveDNSRecord($Record2)
                }
                Finally
                {
                    $DNSServerRepo.RemoveDNSServerWithDependencies($Server)
                }
            } | Should -Not -Throw
        }

        # Until we will be able to determine record internal name,
        # this test should be pending
        It 'can remove DNS server records by name' -Pending {
            $Server = [DNSServer]::New("CreatedByPS1ScriptRecordsByName")
            $DNSServerRepo.AddDNSServer($Server)
            {
                Try
                {

                    $DNSServerRepo.AddDNSRecord([DNSRecord]::New("host1", "1.2.3.4", "A", $Server.GetFQName()))
                    $DNSServerRepo.AddDNSRecord([DNSRecord]::New("host2", "1.2.3.5", "A", $Server.GetFQName()))

                    $DNSServerRepo.RemoveDNSRecord([DNSRecord]::New("host1", "1.2.3.4", "A", $Server.GetFQName()))
                    $DNSServerRepo.RemoveDNSRecord([DNSRecord]::New("host2", "1.2.3.5", "A", $Server.GetFQName()))

                    $DNSServerRepo.RemoveDNSServer($Server)
                }
                Catch
                {
                    $DNSServerRepo.RemoveDNSServerWithDependencies($Server)
                    Throw
                }
            } | Should -Not -Throw
        }

        It 'can remove DNS server with dependencies' {
            $Server = [DNSServer]::New("CreatedByPS1ScriptForce")
            $Record1 = [DNSRecord]::New("host1", "1.2.3.4", "A", $Server.GetFQName())
            $Record2 = [DNSRecord]::New("host2", "1.2.3.5", "A", $Server.GetFQName())

            $DNSServerRepo.AddDNSServer($Server)
            $DNSServerRepo.AddDNSRecord($Record1)
            $DNSServerRepo.AddDNSRecord($Record2)

            $IPAMRepo = [IPAMRepo]::New($ContrailNM)
            $IPAM = [IPAM]::New()
            $IPAM.DNSSettings = [VirtualDNSSettings]::New($Server.GetFQName())
            $IPAMRepo.SetIpamDNSMode($IPAM)

            {
                $DNSServerRepo.RemoveDNSServer($Server)
            } | Should -Throw

            {
                $DNSServerRepo.RemoveDNSServerWithDependencies($Server)
            } | Should -Not -Throw

            $DNSServerRepo.AddDNSServer($Server)

            {
                $DNSServerRepo.RemoveDNSServerWithDependencies($Server)
            } | Should -Not -Throw
        }
    }
}
