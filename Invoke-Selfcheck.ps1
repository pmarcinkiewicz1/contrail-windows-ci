Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(Mandatory=$false)] [string] $ReportPath,
    [switch] $SkipUnit,
    [switch] $SkipStaticAnalysis,
    [switch] $CodeCoverage
)

. $PSScriptRoot\CIScripts\Common\Init.ps1
. $PSScriptRoot/CIScripts/TestRunner/Invoke-PesterTests.ps1

# NOTE TO DEVELOPERS
# ------------------
# The idea behind this tool is that anyone can run the basic set of tests without ANY preparation 
# (except Pester).
# A new developer should be able to run `.\Invoke-Selfcheck.ps1` and it should pass 100% of the time,
# without any special requirements, like libraries, testbed machines etc.
# Special flags may be passed to invoke more complicated tests (that have requirements), but
# the default should require nothing.


$nl = [Environment]::NewLine

function Write-VisibleMessage {
    param([string] $Message)
    Write-Host "$('='*80)$nl [Selfcheck] $Message$nl$('='*80)"
}

$IncludeTags = @("CI")
$ExcludeTags = @()

if ($SkipUnit) {
    Write-VisibleMessage "-SkipUnit flag set, skipping unit tests"
    $ExcludeTags += "Unit"
}

if (-not $TestenvConfFile) {
    Write-VisibleMessage "testenvconf file not provided, skipping system tests"
    $ExcludeTags += "Systest"
}

$FilesUnderTest = @()
if ($CodeCoverage) {
    $Dirs = Get-ChildItem -Directory -Exclude "_Old_Tests"
    $FilesUnderTest = Get-ChildItem $Dirs -File -Recurse -Include "*.ps1" -Exclude "*.Tests.ps1"
}

Write-VisibleMessage "Including tags: $IncludeTags; Excluding tags: $ExcludeTags"
$Results = Invoke-PesterTests -TestRootDir $pwd -ReportPath $ReportPath `
    -IncludeTags $IncludeTags -ExcludeTags $ExcludeTags `
    -AdditionalParams @{TestenvConfFile=$TestenvConfFile} `
    -CodeCovFiles $FilesUnderTest

if ($SkipStaticAnalysis) {
    Write-VisibleMessage "-SkipStaticAnalysis switch set, skipping static analysis"
} else {
    Write-VisibleMessage "running static analysis, this might take a while"
    try {
        .\StaticAnalysis\Invoke-StaticAnalysisTools.ps1 -RootDir . -ConfigDir $pwd/StaticAnalysis
    } catch {
        Write-VisibleMessage "static analysis failed (but continuing script):", $_
    }
}

if ($CodeCoverage) {
    $PercentCov = 100.0 * $Results.CodeCoverage.NumberOfCommandsExecuted / `
        $Results.CodeCoverage.NumberOfCommandsAnalyzed
    Write-VisibleMessage "Code coverage: $PercentCov%"
}
Write-VisibleMessage "done"

if ($Results.FailedCount -gt 0) {
    throw "Some tests failed"
}
