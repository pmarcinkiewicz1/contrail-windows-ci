. $PSScriptRoot\Common\Init.ps1
. $PSScriptRoot\Common\Job.ps1
. $PSScriptRoot\Checkout\Zuul.ps1

$Job = [Job]::new("Checkout")

if (Test-Path "Env:ZUUL_URL") {
    $ZuulAdditionalParams = @{
        Url = $Env:ZUUL_URL
        Project = $Env:ZUUL_PROJECT
        Ref = $Env:ZUUL_REF
    }
    Get-ZuulRepos -GerritUrl $Env:GERRIT_URL `
                  -ZuulBranch $Env:ZUUL_BRANCH `
                  -ZuulAdditionalParams $ZuulAdditionalParams
} else {
    Get-ZuulRepos -GerritUrl $Env:GERRIT_URL `
                  -ZuulBranch $Env:ZUUL_BRANCH
}

$Job.Done()
