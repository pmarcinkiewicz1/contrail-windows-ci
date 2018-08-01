Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(Mandatory=$false)] [string] $LogDir = "pesterLogs",
    [Parameter(ValueFromRemainingArguments=$true)] $UnusedParams
)

. $PSScriptRoot\..\..\..\CIScripts\Common\Invoke-UntilSucceeds.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Init.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Aliases.ps1
. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testenv.ps1
. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testbed.ps1

. $PSScriptRoot\..\..\Utils\CommonTestCode.ps1
. $PSScriptRoot\..\..\Utils\ComponentsInstallation.ps1
. $PSScriptRoot\..\..\TestConfigurationUtils.ps1
. $PSScriptRoot\..\..\PesterHelpers\PesterHelpers.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\PesterLogger\RemoteLogCollector.ps1

Describe "vRouter Agent service" {
    
    Context "disabling" {
        It "is disabled" -Pending {
            Get-AgentServiceStatus -Session $Session | Should Be "Stopped"
        }

        It "does not restart" -Pending {
            Consistently {
                Get-AgentServiceStatus -Session $Session | Should Be "Stopped"
            } -Duration 3
        }

        BeforeEach {
            Enable-AgentService -Session $Session
            Invoke-UntilSucceeds {
                (Get-AgentServiceStatus -Session $Session) -eq 'Running'
            } -Duration 30
            Disable-AgentService -Session $Session
        }
    }

    Context "given vRouter Forwarding Extension is NOT running" {
        It "crashes" -Pending {
            Eventually {
                Read-SyslogForAgentCrash -Session $Session -After $BeforeCrash | Should Not BeNullOrEmpty
            } -Duration 60
        }

        BeforeEach {
            Disable-VRouterExtension -Session $Session -SystemConfig $SystemConfig

            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments",
                "", Justification="Issue #804 from PSScriptAnalyzer GitHub")]
            $BeforeCrash = Invoke-Command -Session $Session -ScriptBlock { Get-Date }
            Enable-AgentService -Session $Session
        }
    }

    Context "given vRouter Forwarding Extension is running" {
        It "runs correctly" -Pending {
            Eventually {
                Get-AgentServiceStatus -Session $Session | Should Be "Running"
            } -Duration 30
        }

        BeforeEach {
            Enable-AgentService -Session $Session
        }
    }
    
    Context "vRouter Forwarding Extension was disabled while Agent was running" {
        It "crashes" -Pending {
            Eventually {
                Read-SyslogForAgentCrash -Session $Session -After $BeforeCrash `
                    | Should Not BeNullOrEmpty
            } -Duration 30
        }

        BeforeEach {
            Enable-AgentService -Session $Session
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments",
                "", Justification="Issue #804 from PSScriptAnalyzer GitHub")]
            $BeforeCrash = Invoke-Command -Session $Session -ScriptBlock { Get-Date }
            Disable-VRouterExtension -Session $Session -SystemConfig $SystemConfig
        }
    }

    BeforeEach {
        Initialize-DriverAndExtension -Session $Session `
            -SystemConfig $SystemConfig `
            -OpenStackConfig $OpenStackConfig `
            -ControllerConfig $ControllerConfig

        New-AgentConfigFile -Session $Session `
            -ControllerConfig $ControllerConfig `
            -SystemConfig $SystemConfig
    }

    AfterEach {
        try {
            Clear-TestConfiguration -Session $Session -SystemConfig $SystemConfig
            if ((Get-AgentServiceStatus -Session $Session) -eq "Running") {
                Disable-AgentService -Session $Session
            }
        } finally {
            Merge-Logs -LogSources (New-FileLogSource -Path (Get-ComputeLogsPath) -Sessions $Session)
        }
    }

    BeforeAll {
        $Sessions = New-RemoteSessions -VMs (Read-TestbedsConfig -Path $TestenvConfFile)
        $Session = $Sessions[0]

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $ControllerConfig = Read-ControllerConfig -Path $TestenvConfFile
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $OpenStackConfig = Read-OpenStackConfig -Path $TestenvConfFile
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $SystemConfig = Read-SystemConfig -Path $TestenvConfFile

        Initialize-PesterLogger -OutDir $LogDir

        Install-DockerDriver -Session $Session
        Install-Agent -Session $Session
        Install-Extension -Session $Session
        Install-Utils -Session $Session
    }

    AfterAll {
        if (-not (Get-Variable Sessions -ErrorAction SilentlyContinue)) { return }
        Uninstall-DockerDriver -Session $Session
        Uninstall-Agent -Session $Session
        Uninstall-Extension -Session $Session
        Uninstall-Utils -Session $Session
        Remove-PSSession $Sessions
    }
}
