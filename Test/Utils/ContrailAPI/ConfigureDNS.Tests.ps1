Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(ValueFromRemainingArguments=$true)] $UnusedParams
)

. $PSScriptRoot\ConfigureDNS.ps1
. $PSScriptRoot\..\ContrailUtils.ps1
. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testenv.ps1

# TODO: Those tests run on working Controller.
#       Most probably they need to be rewrote
#       to use some fake.
# NOTE: Because of the above they should not be run automatically
Describe 'Configure DNS API' -Tags CI, Systest {
    BeforeAll {
        $OpenStackConfig = Read-OpenStackConfig -Path $TestenvConfFile
        $ControllerConfig = Read-ControllerConfig -Path $TestenvConfFile

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments",
            "ContrailUrl",
            Justification="It's actually used."
        )]
        $ContrailUrl = $ControllerConfig.RestApiUrl()

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments",
            "AuthToken",
            Justification="It's actually used."
        )]
        $AuthToken = Get-AccessTokenFromKeystone `
            -AuthUrl $OpenStackConfig.AuthUrl() `
            -Username $OpenStackConfig.Username `
            -Password $OpenStackConfig.Password `
            -Tenant $OpenStackConfig.Project
    }

    Context 'DNS server creation and removal' {

        It 'can add and remove not attached to ipam DNS server without records' {
            {
                $ServerUUID = Add-ContrailDNSServer -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                    -DNSServerName "CreatedByPS1ScriptEmpty"
                Remove-ContrailDNSServer -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                    -DNSServerUuid $ServerUUID
            } | Should -Not -Throw
        }

        It 'can add and remove DNS server records' {
            $ServerUUID = Add-ContrailDNSServer -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                -DNSServerName "CreatedByPS1Script"

            {
                $Record1Data = [VirtualDNSRecordData]::new("host1", "1.2.3.4", "A")
                $Record1UUID = Add-ContrailDNSRecord -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                    -DNSServerName "CreatedByPS1Script" -VirtualDNSRecordData $Record1Data

                $Record2Data = [VirtualDNSRecordData]::new("host2", "1.2.3.5", "A")
                $Record2UUID = Add-ContrailDNSRecord -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                    -DNSServerName "CreatedByPS1Script" -VirtualDNSRecordData $Record2Data

                Remove-ContrailDNSRecord -ContrailUrl $ContrailUrl -AuthToken $AuthToken -DNSRecordUuid $Record1UUID
                Remove-ContrailDNSRecord -ContrailUrl $ContrailUrl -AuthToken $AuthToken -DNSRecordUuid $Record2UUID
            } | Should -Not -Throw

            Remove-ContrailDNSServer -ContrailUrl $ContrailUrl -AuthToken $AuthToken -DNSServerUuid $ServerUUID
        }

        It 'needs -Force switch to remove attached to ipam DNS Server with records' {
            $ServerUUID = Add-ContrailDNSServer -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                -DNSServerName "CreatedByPS1ScriptForce"

            $Record1Data = [VirtualDNSRecordData]::new("host1", "1.2.3.4", "A")
            Add-ContrailDNSRecord -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                -DNSServerName "CreatedByPS1ScriptForce" -VirtualDNSRecordData $Record1Data

            $Record2Data = [VirtualDNSRecordData]::new("host2", "1.2.3.5", "A")
            Add-ContrailDNSRecord -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                -DNSServerName "CreatedByPS1ScriptForce" -VirtualDNSRecordData $Record2Data

            Set-IpamDNSMode -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                -IpamFQName @("default-domain", "default-project", "default-network-ipam") `
                -DNSMode 'virtual-dns-server' -VirtualServerName "CreatedByPS1ScriptForce"

            {
                Remove-ContrailDNSServer -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                    -DNSServerUuid $ServerUUID
            } | Should -Throw

            {
                Remove-ContrailDNSServer -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                    -DNSServerUuid $ServerUUID -Force
            } | Should -Not -Throw
        }
    }

    Context 'Setting DNS modes' {
        It 'throws when wrong dns mode specified' {
            {
                Set-IpamDNSMode -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                    -IpamFQName @("default-domain", "default-project", "default-network-ipam") `
                    -DNSMode 'wrongdnsmode'
            } | Should -Throw
        }

        Context 'mode - none' {
            It 'can set DNS mode to none' {
                {
                    Set-IpamDNSMode -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                        -IpamFQName @("default-domain", "default-project", "default-network-ipam") `
                        -DNSMode 'none'
                } | Should -Not -Throw
            }
        }

        Context 'mode - default' {
            It 'can set DNS mode to default' {
                {
                    Set-IpamDNSMode -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                        -IpamFQName @("default-domain", "default-project", "default-network-ipam") `
                        -DNSMode 'default-dns-server'
                } | Should -Not -Throw
            }
        }

        Context 'mode - tenant' {
            It 'can set DNS mode to tenant without DNS servers' {
                {
                    Set-IpamDNSMode -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                        -IpamFQName @("default-domain", "default-project", "default-network-ipam") `
                        -DNSMode 'tenant-dns-server'
                } | Should -Not -Throw
            }

            It 'can set DNS mode to tenant with DNS servers' {
                {
                    Set-IpamDNSMode -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                        -IpamFQName @("default-domain", "default-project", "default-network-ipam") `
                        -DNSMode 'tenant-dns-server' -TenantServersIPAddresses @("1.1.1.1", "2.2.2.2")
                } | Should -Not -Throw
            }
        }

        Context 'mode - virtual' {
            It 'can set DNS "mode" to virtual' {
                $ServerUUID = Add-ContrailDNSServer -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                    -DNSServerName "CreatedByPS1ScriptForIpam"

                {
                    Set-IpamDNSMode -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                        -IpamFQName @("default-domain", "default-project", "default-network-ipam") `
                        -DNSMode 'virtual-dns-server' -VirtualServerName "CreatedByPS1ScriptForIpam"
                } | Should -Not -Throw

                Remove-ContrailDNSServer -ContrailUrl $ContrailUrl -AuthToken $AuthToken -DNSServerUuid $ServerUUID -Force
            }

            It 'throws when no virtual DNS server specified in virtual DNS mode' {
                {
                    Set-IpamDNSMode -ContrailUrl $ContrailUrl -AuthToken $AuthToken `
                        -IpamFQName @("default-domain", "default-project", "default-network-ipam") `
                        -DNSMode 'virtual-dns-server'
                } | Should -Throw
            }
        }
    }
}
