. $PSScriptRoot\Common\Init.ps1
. $PSScriptRoot\Common\Job.ps1
. $PSScriptRoot\Common\Aliases.ps1
. $PSScriptRoot\Common\Credentials.ps1

$Credentials = Get-MgmtCreds

$OutputRootDirectory = "output"
$NothingToBuild = $Env:COMPONENTS_TO_BUILD -eq "None"
$CopyDisabledArtifacts = Test-Path Env:COPY_DISABLED_ARTIFACTS

if (-not $NothingToBuild) {
    & $PSScriptRoot\Build.ps1
}

if ($NothingToBuild -or $CopyDisabledArtifacts) {
    $Job = [Job]::new("Copying ready artifacts")

    $ArtifactsPath = "\\$Env:SHARED_DRIVE_IP\SharedFiles\WindowsCI-Artifacts"
    if (Test-Path Env:READY_ARTIFACTS_PATH) {
        $ArtifactsPath = $Env:READY_ARTIFACTS_PATH
    }

    $DiskName = [Guid]::newGuid().Guid
    New-PSDrive -Name $DiskName -PSProvider "FileSystem" -Root $ArtifactsPath -Credential $Credentials

    if (-Not (Test-Path "$OutputRootDirectory")) {
        New-Item -Name $OutputRootDirectory -ItemType directory
    }

    foreach ($Item in Get-ChildItem "${DiskName}:\") {
        $OutputItem = "$OutputRootDirectory\$($Item.Name)"
        $IsFileOrNonemptyDir = [bool](Get-ChildItem $OutputItem -ErrorAction SilentlyContinue)

        if ($IsFileOrNonemptyDir) {
            continue
        }

        $Job.StepQuiet("Copying $($Item.Name)", {
            Copy-Item $Item.FullName -Destination "$OutputRootDirectory\" -Recurse -Container -Force
        })
    }

    $Job.Done()
}

if (Test-Path Env:UPLOAD_ARTIFACTS) {
    if ($Env:UPLOAD_ARTIFACTS -ne "0") {
        $ArtifactsPath = "\\$Env:SHARED_DRIVE_IP\SharedFiles\WindowsCI-UploadedArtifacts"
        $Subdir = "$Env:JOB_NAME\$Env:BUILD_NUMBER"
        $DiskName = [Guid]::newGuid().Guid
        New-PSDrive -Name $DiskName -PSProvider "FileSystem" -Root $ArtifactsPath -Credential $Credentials
        Push-Location
        Set-Location ($Diskname + ":\")
        New-Item -Name $Subdir -ItemType directory
        Pop-Location
        Copy-Item ($OutputRootDirectory + "\*") -Destination ("$DiskName" + ":\" + $Subdir) -Recurse -Container
    }
}

exit 0
