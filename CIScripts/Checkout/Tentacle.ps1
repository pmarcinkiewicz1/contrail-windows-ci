# Tentacle is a component for running Jenkins jobs from Zuul v3
# It serves an HTTP server with repositories. We need to download and unpack them.

function Get-TentacleRepos {
    Param (
        [Parameter(Mandatory = $true)] [string] $ArchiveUrl
    )

    $Job.Step("Downloading tentacle repositories", {
        Invoke-WebRequest -Uri $ArchiveUrl -OutFile repos.zip
    })

    $Job.Step("Unpacking tentacle repositories", {
        Expand-Archive -Path repos.zip -DestinationPath .
    })
}
