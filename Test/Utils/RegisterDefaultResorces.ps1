. $PSScriptRoot\..\..\CIScripts\Common\Init.ps1
. $PSScriptRoot\ContrailUtils.ps1

function Register-DefaultResourcesInContrail {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUserNameAndPassWordParams",
        "", Justification="We don't care that it's plaintext, it's just test env.")]
    Param (
        [Parameter(Mandatory = $true)] [string] $ContrailIp,
        [string] $TenantName = "admin",
        [string] $Username = "admin",
        [string] $Password = "c0ntrail123"
    )

    $ContrailUrl = "http://" + $ContrailIp + ":8082"
    $AuthUrl = "http://" + $ContrailIp + ":5000/v2.0"
    $AuthToken = Get-AccessTokenFromKeystone -AuthUrl $AuthUrl -TenantName $TenantName -Username $Username -Password $Password

    Add-ContrailProject -ContrailUrl $ContrailUrl -AuthToken $AuthToken -ProjectName "ci_tests"
    Add-ContrailVirtualNetwork -ContrailUrl $ContrailUrl -AuthToken $AuthToken -TenantName "ci_tests" -NetworkName "testnet1"
}
