. $PSScriptRoot\..\Common\Init.ps1
. $PSScriptRoot\GenerateTestReport.ps1

function Invoke-FakeReportunit {
    Param([Parameter(Mandatory = $true)] [string] $NUnitDir)
    $Files = Get-ChildItem -Path $NUnitDir -File
    if ($Files.length -eq 0) {
        throw "Empty directory"
    }
    if ($Files.length -gt 1) {
        New-Item -Type File -Path (Join-Path $NUnitDir "Index.html")
    }
    $Files | ForEach-Object {
        New-Item -Type File -Path (Join-Path $NUnitDir ($_.BaseName + ".html"))
    }
}

function Invoke-ReportGenTests {
    Param($ReportunitWrapperFunc)

    function NormalizeXmlString {
        Param([Parameter(Mandatory = $true)] [string] $InputData)
        ([Xml] $InputData).OuterXml
    }

    function New-DummyFile {
        Param([Parameter(Mandatory = $true)] [string] $Path)
        @"
<?xml version="1.0"?>
<test-results>
<environment />
<culture-info current-culture="en-US" current-uiculture="en-US" />
<test-suite name="Pester" description="Pester">
<results>
    <test-suite name="C:\SomePath\SomeSuite.Tests.ps1" description="C:\SomePath\SomeSuite.Tests.ps1">
    <results>
        <test-suite name="A">
        <results>
            <test-suite name="1">
            <results>
                <test-case description="MyTestCase" name="MyTestCase" />
            </results>
            </test-suite>
        </results>
        </test-suite>
    </results>
    </test-suite>
    <test-suite name="C:\SomePath\OtherSuite.Tests.ps1" description="C:\SomePath\OtherSuite.Tests.ps1">
    <results>
        <test-suite name="B">
        <results>
            <test-suite name="2">
            <results>
                <test-case description="YourTestCase" name="YourTestCase" />
            </results>
            </test-suite>
        </results>
        </test-suite>
    </results>
    </test-suite>
</results>
</test-suite>
</test-results>
"@ | Set-Content -Path $Path
    }

    function New-TemporaryDirs {
        $InputDir = Join-Path $TestDrive "testReportInput"
        $OutputDir = Join-Path $TestDrive "testReportOutput"
        New-Item -Type Directory $InputDir | Out-Null
        return $InputDir, $OutputDir
    }

    function Clear-TemporaryDirs {
        Param([Parameter(Mandatory = $true)] [string[]] $Dirs)
        $Dirs | ForEach-Object {
            Remove-Item -Recurse -Force $_
        }
    }

    Context "single xml file" {
        BeforeAll {
            $InputDir, $OutputDir = New-TemporaryDirs
            $DummyReportPath = (Join-Path $InputDir "foo.xml")
            New-DummyFile -Path $DummyReportPath
            Convert-TestReportsToHtml -RawNUnitPath $DummyReportPath -OutputDir $OutputDir -GeneratorFunc $ReportunitWrapperFunc
        }

        AfterAll {
            Clear-TemporaryDirs -Dirs @($InputDir, $OutputDir)
        }

        It "creates appropriate subdirectories" {
            Join-Path $OutputDir "raw_NUnit" | Should Exist
            Join-Path $OutputDir "pretty_test_report" | Should Exist
        }

        It "creates appropriate files" {
            Join-Path $OutputDir "raw_NUnit/SomeSuite.xml" | Should Exist
            Join-Path $OutputDir "pretty_test_report/SomeSuite.html" | Should Exist
            Join-Path $OutputDir "pretty_test_report/OtherSuite.html" | Should Exist
            Join-Path $OutputDir "pretty_test_report/Index.html" | Should Exist
            Join-Path $OutputDir "reports-locations.json" | Should Exist
        }

        It "splits combined xml files and flattens the contents to max 1 level of test suites" {
            $ExpectedSomeSuiteXml = NormalizeXmlString @"
<?xml version="1.0"?>
<test-results>
<environment />
<culture-info current-culture="en-US" current-uiculture="en-US" />
    <test-suite name="1">
    <results>
        <test-case description="MyTestCase" name="MyTestCase" />
    </results>
    </test-suite>
</test-results>
"@
            $ExpectedOtherSuiteXml = NormalizeXmlString @"
<?xml version="1.0"?>
<test-results>
<environment />
<culture-info current-culture="en-US" current-uiculture="en-US" />
    <test-suite name="2">
    <results>
        <test-case description="YourTestCase" name="YourTestCase" />
    </results>
    </test-suite>
</test-results>
"@
            NormalizeXmlString (Get-Content -Raw (Join-Path $OutputDir "raw_NUnit/SomeSuite.xml")) `
                | Should BeExactly $ExpectedSomeSuiteXml
            NormalizeXmlString (Get-Content -Raw (Join-Path $OutputDir "raw_NUnit/OtherSuite.xml")) `
                | Should BeExactly $ExpectedOtherSuiteXml
        }

        It "json file for monitoring contains valid path to raw nunit reports" {
            $Json = Get-Content -Raw -Path (Join-Path $OutputDir "reports-locations.json") | ConvertFrom-Json
            "./raw_NUnit/SomeSuite.xml" | Should BeIn $Json.'xml_reports'
            "./raw_NUnit/OtherSuite.xml" | Should BeIn $Json.'xml_reports'
            $Json.'xml_reports'[0].GetType().Name | Should Be 'string'
        }

        It "json file for monitoring contains valid path to html report" {
            $Json = Get-Content -Raw -Path (Join-Path $OutputDir "reports-locations.json") | ConvertFrom-Json
            $Json.'html_report' | Should BeExactly './pretty_test_report/Index.html'
        }
    }
}


Describe "Generating test report - Unit tests" -Tags CI, Unit {
    Invoke-ReportGenTests -ReportunitWrapperFunc (Get-Item function:Invoke-FakeReportunit)
}

Describe "Generating test report - System tests" -Tags CI, Systest {
    Invoke-ReportGenTests -ReportunitWrapperFunc (Get-Item function:Invoke-RealReportunit)
}
