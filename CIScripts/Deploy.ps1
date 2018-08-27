Param(
    [Parameter(Mandatory = $true)] [string] $TestenvConfFile,
    [Parameter(Mandatory = $true)] [string] $ArtifactsDir
)

# Deploy copies required artifacts onto already provisioned machines.

. $PSScriptRoot\Common\Init.ps1
. $PSScriptRoot\Common\Job.ps1
. $PSScriptRoot\Testenv\Testenv.ps1
. $PSScriptRoot\Testenv\Testbed.ps1
. $PSScriptRoot\Deploy\Deployment.ps1

$Job = [Job]::new("Deploy")

$Sessions = New-RemoteSessions -VMs (Read-TestbedsConfig -Path $TestenvConfFile)
Copy-ArtifactsToTestbeds -Sessions $Sessions -ArtifactsDir $ArtifactsDir

$Job.Done()

exit 0
