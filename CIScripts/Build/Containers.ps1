. $PSScriptRoot\..\Common\Invoke-NativeCommand.ps1

class ContainerAttributes {
    [string] $Suffix;
    [string[]] $Folders;

    ContainerAttributes([string] $Suffix, [string[]] $Folders) {
        $this.Suffix = $Suffix;
        $this.Folders= $Folders;
    }
}

function Invoke-ContainerBuild {
    Param ([Parameter(Mandatory = $true)] [string] $WorkDir,
           [Parameter(Mandatory = $true)] [ContainerAttributes] $ContainerAttributes,
           [Parameter(Mandatory = $true)] [string] $ContainerTag,
           [Parameter(Mandatory = $true)] [string] $Registry)

    $ContainerSuffix = $ContainerAttributes.Suffix
    New-Item -Name $WorkDir\$ContainerSuffix -ItemType directory
    Compress-Archive -Path $ContainerAttributes.Folders -DestinationPath $WorkDir\$ContainerSuffix\artifacts.zip
    # Docker pre 18.03 needs Dockerfile to be within the build context
    Copy-Item $PSScriptRoot\Dockerfile $WorkDir\$ContainerSuffix
    # We use ${} to delimit the name before the colon
    $ContainerName = "contrail-windows-${ContainerSuffix}:$ContainerTag"
    Invoke-NativeCommand -ScriptBlock {
        docker build -t $ContainerName $WorkDir\$ContainerSuffix
    }
    Invoke-NativeCommand -ScriptBlock {
        docker tag $ContainerName $Registry/$ContainerName
    }
    Invoke-NativeCommand -ScriptBlock {
        docker push $Registry/$ContainerName
    }
    Invoke-NativeCommand -ScriptBlock {
        docker rmi $ContainerName $Registry/$ContainerName
    }
}

function Invoke-ContainersBuild {
    Param ([Parameter(Mandatory = $true)] [string] $WorkDir,
           [Parameter(Mandatory = $true)] [ContainerAttributes[]] $ContainersAttributes,
           [Parameter(Mandatory = $true)] [string] $ContainerTag,
           [Parameter(Mandatory = $true)] [string] $Registry)

    $Job.PushStep("Containers build")

    $Job.Step("add insecure registry", {
        $DockerConfig = @"
{
    "insecure-registries" : [ "$Registry" ]
}
"@
        Set-Content -Path "C:\ProgramData\Docker\config\daemon.json" -Value $DockerConfig
        Restart-Service docker
    })

    ForEach ($ContainerAttributes in $ContainersAttributes) {
        $Job.Step("Building contrail-windows-$($ContainerAttributes.Suffix)", {
            Invoke-ContainerBuild -WorkDir $WorkDir `
                -ContainerAttributes $ContainerAttributes `
                -ContainerTag $ContainerTag `
                -Registry $Registry
        })
    }

    $Job.PopStep()
}
