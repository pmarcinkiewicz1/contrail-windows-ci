. $PSScriptRoot\..\Common\Aliases.ps1
. $PSScriptRoot\..\Common\Components.ps1

function Copy-ArtifactsToTestbeds {
    Param ([Parameter(Mandatory = $true)] [PSSessionT[]] $Sessions,
           [Parameter(Mandatory = $true)] [string] $ArtifactsDir)
    $Job.Step("Deploying testbeds", {
        $Sessions.ForEach({
            $Job.Step("Deploying testbed...", {
                Install-Artifacts -Session $_ -ArtifactsDir $ArtifactsDir
            })
        })
    })
}

function Install-Artifacts {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $ArtifactsDir)

    function Test-NonemptyDir {
        Param ([Parameter(Mandatory = $true)] [string] $Path)
        [bool](Get-ChildItem $Path -ErrorAction SilentlyContinue)
    }

    Push-Location $ArtifactsDir

    Invoke-Command -Session $Session -ScriptBlock {
        New-Item -ItemType Directory -Force C:\Artifacts | Out-Null
    }

    if (Test-NonemptyDir "docker-driver") {
        Write-Host "Copying Docker driver installer"
        Copy-Item -ToSession $Session -Path "docker-driver\docker-driver.msi" -Destination C:\Artifacts\

        Write-Host "Copying Docker driver tests"
        Copy-Item -ToSession $Session -Path "docker-driver\*.test.exe" -Destination "C:\Artifacts\"
    }

    if (Test-NonemptyDir "agent") {
        Write-Host "Copying Agent"
        Copy-Item -ToSession $Session -Path "agent\contrail-vrouter-agent.msi" -Destination C:\Artifacts\
    }

    if (Test-NonemptyDir "vrouter") {
        Write-Host "Copying vRouter and Utils MSIs"
        Copy-Item -ToSession $Session -Path "vrouter\vRouter.msi" -Destination C:\Artifacts\
        Copy-Item -ToSession $Session -Path "vrouter\utils.msi" -Destination C:\Artifacts\
        Copy-Item -ToSession $Session -Path "vrouter\*.cer" -Destination C:\Artifacts\ # TODO: Remove after JW-798

        Write-Host "Copying vtest scenarios"
        Copy-Item -ToSession $Session -Path "vtest" -Destination C:\Artifacts\ -Recurse -Force

        Invoke-Command -Session $Session -ScriptBlock {
            Write-Host "Installing certificates"
            Import-Certificate -CertStoreLocation Cert:\LocalMachine\Root\ "C:\Artifacts\vRouter.cer" | Out-Null # TODO: Remove after JW-798
            Import-Certificate -CertStoreLocation Cert:\LocalMachine\TrustedPublisher\ "C:\Artifacts\vRouter.cer" | Out-Null # TODO: Remove after JW-798
        }
    }

    if (Test-NonemptyDir "nodemgr") {
        Write-Host "Copying Node Manager"
        Copy-Item -ToSession $Session -Path "nodemgr" -Destination C:\Artifacts\ -Recurse
    }

    Write-Host "Copying dlls"
    Copy-Item -ToSession $Session -Path "dlls\*" -Destination "C:\Windows\System32\"

    Invoke-Command -Session $Session -ScriptBlock {
        # Refresh Path
        $Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    }

    Pop-Location
}

