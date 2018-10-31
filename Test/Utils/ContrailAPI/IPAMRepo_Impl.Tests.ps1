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
Describe 'Contrail IPAM API' -Tags CI, Systest {
    BeforeAll {
        $OpenStackConfig = Read-OpenStackConfig -Path $TestenvConfFile
        $ControllerConfig = Read-ControllerConfig -Path $TestenvConfFile
        $ContrailNM = [ContrailNetworkManager]::New($OpenStackConfig, $ControllerConfig)

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments",
            "IPAMRepo",
            Justification="It's actually used."
        )]
        $IPAMRepo = [IPAMRepo]::New($ContrailNM)
    }

    Context 'Setting DNS modes' {

        Context 'mode - none' {
            It 'can set DNS mode to none' {
                {
                    $IPAM = [IPAM]::New()
                    $IPAM.DNSSettings = [NoneDNSSettings]::New()
                    $IPAMRepo.SetIpamDNSMode($IPAM)
                } | Should -Not -Throw
            }
        }

        Context 'mode - default' {
            It 'can set DNS mode to default' {
                {
                    $IPAM = [IPAM]::New()
                    $IPAM.DNSSettings = [DefaultDNSSettings]::New()
                    $IPAMRepo.SetIpamDNSMode($IPAM)
                } | Should -Not -Throw
            }
        }

        Context 'mode - tenant' {
            It 'throws when no DNS server specified' {
                {
                    $IPAM = [IPAM]::New()
                    $IPAM.DNSSettings = [TenantDNSSettings]::New($null)
                    $IPAMRepo.SetIpamDNSMode($IPAM)
                } | Should -Throw
            }

            It 'can set DNS mode to tenant with DNS servers' {
                {
                    $IPAM = [IPAM]::New()
                    $IPAM.DNSSettings = [TenantDNSSettings]::New(@("1.1.1.1", "2.2.2.2"))
                    $IPAMRepo.SetIpamDNSMode($IPAM)
                } | Should -Not -Throw
            }
        }

        Context 'mode - virtual' {
            It 'throws when no virtual DNS server specified in virtual DNS mode' {
                {
                    $IPAM = [IPAM]::New()
                    $IPAM.DNSSettings = [VirtualDNSSettings]::New($null)
                    $IPAMRepo.SetIpamDNSMode($IPAM)
                } | Should -Throw
            }

            It 'can set DNS mode to virtual' {
                $Server = [DNSServer]::New("CreatedByPS1ScriptForIpam")
                $DNSServerRepo = [DNSServerRepo]::New($ContrailNM)
                $DNSServerRepo.AddDNSServer($Server)
                {
                    Try {
                        $IPAM = [IPAM]::New()
                        $IPAM.DNSSettings = [VirtualDNSSettings]::New($Server.GetFQName())
                        $IPAMRepo.SetIpamDNSMode($IPAM)
                    } Finally {
                        $DNSServerRepo.RemoveDNSServerWithDependencies($Server)
                    }
                } | Should -Not -Throw
            }
        }
    }
}
