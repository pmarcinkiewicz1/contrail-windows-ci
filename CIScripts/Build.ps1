# Build builds selected Windows Compute components.
. $PSScriptRoot\Common\Init.ps1
. $PSScriptRoot\Common\Job.ps1
. $PSScriptRoot\Common\Components.ps1
. $PSScriptRoot\Build\BuildFunctions.ps1
. $PSScriptRoot\Build\BuildMode.ps1


$Job = [Job]::new("Build")

Initialize-BuildEnvironment -ThirdPartyCache $Env:THIRD_PARTY_CACHE_PATH

$SconsBuildMode = Resolve-BuildMode

$DockerDriverOutputDir = "output/docker-driver"
$vRouterOutputDir = "output/vrouter"
$vtestOutputDir = "output/vtest"
$AgentOutputDir = "output/agent"
$NodemgrOutputDir = "output/nodemgr"
$DllsOutputDir = "output/dlls"
$LogsDir = "logs"
$SconsTestsLogsDir = "unittests-logs"

$Directories = @(
    $DockerDriverOutputDir,
    $vRouterOutputDir,
    $vtestOutputDir,
    $AgentOutputDir,
    $NodemgrOutputDir,
    $DllsOutputDir,
    $LogsDir,
    $SconsTestsLogsDir
)

foreach ($Directory in $Directories) {
    if (-not (Test-Path $Directory)) {
        New-Item -ItemType directory -Path $Directory | Out-Null
    }
}

$ComponentsToBuild = Get-ComponentsToBuild

try {
    if ("DockerDriver" -In $ComponentsToBuild) {
        Invoke-DockerDriverBuild -DriverSrcPath $Env:DRIVER_SRC_PATH `
            -SigntoolPath $Env:SIGNTOOL_PATH `
            -CertPath $Env:CERT_PATH `
            -CertPasswordFilePath $Env:CERT_PASSWORD_FILE_PATH `
            -OutputPath $DockerDriverOutputDir `
            -LogsPath $LogsDir
    }

    if ("Extension" -In $ComponentsToBuild) {
        Invoke-ExtensionBuild -ThirdPartyCache $Env:THIRD_PARTY_CACHE_PATH `
            -SigntoolPath $Env:SIGNTOOL_PATH `
            -CertPath $Env:CERT_PATH `
            -CertPasswordFilePath $Env:CERT_PASSWORD_FILE_PATH `
            -BuildMode $SconsBuildMode `
            -OutputPath $vRouterOutputDir `
            -LogsPath $LogsDir

        Copy-VtestScenarios -OutputPath $vtestOutputDir
    }

    if ("Agent" -In $ComponentsToBuild) {
        Invoke-AgentBuild -ThirdPartyCache $Env:THIRD_PARTY_CACHE_PATH `
            -SigntoolPath $Env:SIGNTOOL_PATH `
            -CertPath $Env:CERT_PATH `
            -CertPasswordFilePath $Env:CERT_PASSWORD_FILE_PATH `
            -BuildMode $SconsBuildMode `
            -OutputPath $AgentOutputDir `
            -LogsPath $LogsDir
    }

    Invoke-NodemgrBuild -OutputPath $NodemgrOutputDir `
        -LogsPath $LogsDir `
        -BuildMode $SconsBuildMode

    if ("AgentTests" -In $ComponentsToBuild) {
        Invoke-AgentTestsBuild -LogsPath $LogsDir `
            -BuildMode $SconsBuildMode
    }

    if ($SconsBuildMode -eq "debug") {
        Copy-DebugDlls -OutputPath $DllsOutputDir
    }
} finally {
    $testDirs = Get-ChildItem ".\build\$SconsBuildMode" -Directory
    foreach ($d in $testDirs) {
        Copy-Item -Path $d.FullName -Destination $SconsTestsLogsDir `
            -Recurse -Filter "*.exe.log" -Container
    }
}

$Job.Done()

exit 0
