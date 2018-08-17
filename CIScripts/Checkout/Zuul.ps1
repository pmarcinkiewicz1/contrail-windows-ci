. $PSScriptRoot\..\Common\Invoke-NativeCommand.ps1

function Get-ZuulRepos {
    Param (
        [Parameter(Mandatory = $true)] [string] $GerritUrl,
        [Parameter(Mandatory = $true)] [string] $ZuulBranch,
        [Parameter(Mandatory = $false)] [hashtable] $ZuulAdditionalParams
    )

    $ZuulClonerOptions = @(
        "--zuul-branch=$($ZuulBranch)",
        "--map=./CIScripts/clonemap.yml",
        $GerritUrl
    )

    if ($ZuulAdditionalParams) {
        $ZuulClonerOptions = @(
            "--zuul-url=$($ZuulAdditionalParams.Url)",
            "--zuul-project=$($ZuulAdditionalParams.Project)",
            "--zuul-ref=$($ZuulAdditionalParams.Ref)"
        ) + $ZuulClonerOptions
    }

    # TODO(sodar): Get project list from clonemap.yml
    $ProjectList = @(
        "Juniper/contrail-api-client",
        "Juniper/contrail-build",
        "Juniper/contrail-controller",
        "Juniper/contrail-vrouter",
        "Juniper/contrail-third-party",
        "Juniper/contrail-common",
        "Juniper/contrail-windows-docker-driver",
        "Juniper/contrail-windows"
    )

    $Job.Step("Cloning zuul repositories", {
        Invoke-NativeCommand -ScriptBlock {
            zuul-cloner.exe @ZuulClonerOptions @ProjectList
        }
    })
}
