Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(Mandatory=$false)] [string] $LogDir = "pesterLogs",
    [Parameter(ValueFromRemainingArguments=$true)] $AdditionalParams
)

. $PSScriptRoot\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\PesterHelpers\PesterHelpers.ps1

Describe "Test-ResultsWithRetries" -Tags CI, Systest {
    It "Reports success when all test succeed." {
        $Results = @(
            @{
                Describe="SeriousCarTests";
                Context="FactoryTests/Division1";
                Name="CheckEngine";
                Result="Passed";
            },
            @{
                Describe="SeriousCarTests";
                Context="FactoryTests/Division1";
                Name="CheckLights";
                Result="Passed";
            }
        )

        $Success = Test-ResultsWithRetries -Results $Results
        $Success | Should Be $true
    }

    It "Reports failure when some test consistently fails." {
        $Results = @(
            @{
                Describe="SeriousCarTests";
                Context="FactoryTests/Division1";
                Name="CheckEngine";
                Result="Passed";
            },
            @{
                Describe="SeriousCarTests";
                Context="FactoryTests/Division2";
                Name="CheckEngine";
                Result="Failed";
            },
            @{
                Describe="SeriousCarTests";
                Context="FactoryTests/Division1";
                Name="CheckEngine";
                Result="Passed";
            },
            @{
                Describe="SeriousCarTests";
                Context="FactoryTests/Division2";
                Name="CheckEngine";
                Result="Failed";
            }
        )

        $Success = Test-ResultsWithRetries -Results $Results
        $Success | Should Be $false
    }

    It "Reports success when all tests pass at least once." {
        $Results = @(
            @{
                Describe="SeriousCarTests";
                Context="FactoryTests/Division1";
                Name="CheckEngine";
                Result="Passed";
            },
            @{
                Describe="SeriousCarTests";
                Context="FactoryTests/Division2";
                Name="CheckLights";
                Result="Failed";
            },
            @{
                Describe="SeriousCarTests";
                Context="FactoryTests/Division1";
                Name="CheckEngine";
                Result="Failed";
            },
            @{
                Describe="SeriousCarTests";
                Context="FactoryTests/Division2";
                Name="CheckLights";
                Result="Passed";
            }
        )

        $Success = Test-ResultsWithRetries -Results $Results
        $Success | Should Be $true
    }
}
