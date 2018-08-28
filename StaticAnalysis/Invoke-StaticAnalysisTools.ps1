Param([Parameter(Mandatory = $true)] [string] $RootDir,
    [Parameter(Mandatory = $true)] [string] $ConfigDir)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$MinimumVersion = "1.17.0"
try {
    Get-Package -Name PSScriptAnalyzer -MinimumVersion $MinimumVersion | Out-Null
} catch {
    Write-Host "PSScriptAnalyzer not found. If you have installed it, make sure that it's at least version $MinimumVersion."
    exit 1
}

$PSLinterConfig = "$ConfigDir/PSScriptAnalyzerSettings.psd1"
Write-Host "Running PSScriptAnalyzer... (config from $PSLinterConfig)"


$Output = Invoke-ScriptAnalyzer $RootDir -Recurse -Setting $PSLinterConfig
if ($Output) {
    Write-Host ($Output | Format-Table | Out-String)
    exit 1
}

exit 0
