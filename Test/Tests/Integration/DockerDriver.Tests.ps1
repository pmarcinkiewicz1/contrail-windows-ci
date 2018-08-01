Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(Mandatory=$false)] [string] $LogDir = "pesterLogs",
    [Parameter(Mandatory=$false)] [string] $AdditionalJUnitsDir = "AdditionalJUnitLogs",
    [Parameter(ValueFromRemainingArguments=$true)] $UnusedParams
)

. $PSScriptRoot\..\..\..\CIScripts\Common\Aliases.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Invoke-NativeCommand.ps1
. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testbed.ps1

. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\PesterLogger\RemoteLogCollector.ps1

# TODO: This path should probably come from TestenvConfFile.
$RemoteTestModulesDir = "C:\Artifacts\"

function Find-DockerDriverTests {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [string] $RemoteSearchDir
    )
    $TestModules = Invoke-Command -Session $Session {
        Get-ChildItem -Recurse -Filter "*.test.exe" -Path $Using:RemoteSearchDir `
            | Select-Object BaseName, FullName
    }
    Write-Log "Discovered test modules: $($TestModules.BaseName)"
    return $TestModules
}

function Invoke-DockerDriverUnitTest {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [string] $TestModulePath,
        [Parameter(Mandatory=$true)] [string] $RemoteJUnitOutputDir
    )

    $Command = @($TestModulePath, "--ginkgo.succinct", "--ginkgo.failFast")
    $Command = $Command -join " "

    $Res = Invoke-NativeCommand -CaptureOutput -AllowNonZero -Session $Session {
        Push-Location $Using:RemoteJUnitOutputDir
        try {
            Invoke-Expression -Command $Using:Command
        } finally {
            Pop-Location
        }
    }

    Write-Log $Res.Output

    return $Res.ExitCode
}

function Save-DockerDriverUnitTestReport {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $RemoteJUnitDir,
        [Parameter(Mandatory=$true)] [string] $LocalJUnitDir
    )

    if (-not (Test-Path $LocalJUnitDir)) {
        New-Item -ItemType Directory -Path $LocalJUnitDir | Out-Null
    }

    $FoundRemoteJUnitReports = Invoke-Command -Session $Session -ScriptBlock { 
        Get-ChildItem -Filter "*_junit.xml" -Recurse -Path $Using:RemoteJUnitDir
    }

    Copy-Item $FoundRemoteJUnitReports.FullName -Destination $LocalJUnitDir -FromSession $Session
}

Describe "Docker Driver" {
    BeforeAll {
        $Sessions = New-RemoteSessions -VMs (Read-TestbedsConfig -Path $TestenvConfFile)
        $Session = $Sessions[0]

        Initialize-PesterLogger -OutDir $LogDir

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $FoundTestModules = Find-DockerDriverTests -RemoteSearchDir $RemoteTestModulesDir -Session $Session
    }

    AfterAll {
        if (-not (Get-Variable Sessions -ErrorAction SilentlyContinue)) { return }
        Remove-PSSession $Sessions
    }

    foreach ($TestModule in $FoundTestModules) {
        Context "Tests for module in $($TestModule.BaseName)" {
            It "passes tests" {
                $TestResult = Invoke-DockerDriverUnitTest -Session $Session -TestModulePath $TestModule.FullName -RemoteJUnitOutputDir $RemoteTestModulesDir
                $TestResult | Should Be 0
            }

            AfterEach {
                Save-DockerDriverUnitTestReport -Session $Session -RemoteJUnitDir $RemoteTestModulesDir -LocalJUnitDir $AdditionalJUnitsDir
            }
        }
    }

    AfterEach {
        Merge-Logs -LogSources (New-FileLogSource -Path (Get-ComputeLogsPath) -Sessions $Session)
    }
}
