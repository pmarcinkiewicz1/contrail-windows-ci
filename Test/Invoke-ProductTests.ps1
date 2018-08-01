Param(
    [Parameter(Mandatory = $false)] [string] $TestRootDir = ".",
    [Parameter(Mandatory = $true)] [string] $TestReportDir,
    [Parameter(Mandatory = $true)] [string] $TestenvConfFile
)

. $PSScriptRoot\TestRunner.ps1

if (-not (Test-Path $TestReportDir)) {
    New-Item -ItemType Directory -Path $TestReportDir | Out-Null
}

$DetailedLogsDir = Join-Path $TestReportDir "detailed_logs"
$DDriverJUnitLogsOutputDir = Join-Path $TestReportDir "ddriver_junit_test_logs"

$PesterOutReportDir = Join-Path $TestReportDir "raw_NUnit" 
$PesterOutReportPath = Join-Path $PesterOutReportDir "report.xml"

Invoke-IntegrationAndFunctionalTests `
    -TestRootDir $TestRootDir `
    -TestenvConfFile $TestenvConfFile `
    -PesterOutReportPath $PesterOutReportPath `
    -DetailedLogsOutputDir $DetailedLogsDir `
    -AdditionalJUnitsDir $DDriverJUnitLogsOutputDir
