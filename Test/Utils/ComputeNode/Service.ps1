. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\..\CIScripts\Common\Invoke-NativeCommand.ps1
. $PSScriptRoot\..\..\..\CIScripts\Testenv\Testbed.ps1
. $PSScriptRoot\Configuration.ps1

function Install-ServiceWithNSSM {
    Param (
        [Parameter(Mandatory=$true)] $Session,
        [Parameter(Mandatory=$true)] $ServiceName,
        [Parameter(Mandatory=$true)] $ExecutablePath,
        [Parameter(Mandatory=$false)] [string[]] $CommandLineParams = @()
    )

    $Output = Invoke-NativeCommand -Session $Session -ScriptBlock {
            nssm install $using:ServiceName "$using:ExecutablePath" $using:CommandLineParams
    } -AllowNonZero -CaptureOutput

    $NSSMServiceAlreadyCreatedError = 5
    if ($Output.ExitCode -eq 0) {
        Write-Log $Output.Output
    }
    elseif ($Output.ExitCode -eq $NSSMServiceAlreadyCreatedError) {
        Write-Log "$ServiceName service already created, continuing..."
    }
    else {
        $ExceptionMessage = @"
Unknown (wild) error appeared while creating $ServiceName service.
ExitCode: $Output.ExitCode
NSSM output: $Output.Output
"@
        throw [HardError]::new($ExceptionMessage)
    }
}

function Remove-ServiceWithNSSM {
    Param (
        [Parameter(Mandatory=$true)] $Session,
        [Parameter(Mandatory=$true)] $ServiceName
    )

    $Output = Invoke-NativeCommand -Session $Session {
        nssm remove $using:ServiceName confirm
    } -CaptureOutput

    Write-Log $Output.Output
}

function Start-RemoteService {
    Param (
        [Parameter(Mandatory=$true)] $Session,
        [Parameter(Mandatory=$true)] $ServiceName
    )

    Write-Log "Starting $ServiceName"

    Invoke-Command -Session $Session -ScriptBlock {
        Start-Service $using:ServiceName
    } | Out-Null
}

function Stop-RemoteService {
    Param (
        [Parameter(Mandatory=$true)] $Session,
        [Parameter(Mandatory=$true)] $ServiceName
    )

    Write-Log "Stopping $ServiceName"

    Invoke-Command -Session $Session -ScriptBlock {
        # Some tests call, which don't use all components, use Clear-TestConfiguration function.
        # Ignoring errors here allows us to get rid of boilerplate code, which
        # would be needed to handle cases where not all services are present on testbed(s).
        Stop-Service $using:ServiceName -ErrorAction SilentlyContinue
    } | Out-Null
}

function Get-ServiceStatus {
    Param (
        [Parameter(Mandatory=$true)] $Session,
        [Parameter(Mandatory=$true)] $ServiceName
    )

    Invoke-Command -Session $Session -ScriptBlock {
        $Service = Get-Service $using:ServiceName -ErrorAction SilentlyContinue
        if ($Service -and $Service.Status) {
            return $Service.Status.ToString()
        } else {
            return $null
        }
    }
}

function Out-StdoutAndStderrToLogFile {
    Param (
        [Parameter(Mandatory=$true)] $Session,
        [Parameter(Mandatory=$true)] $ServiceName,
        [Parameter(Mandatory=$true)] $LogPath
    )

    $Output = Invoke-NativeCommand -Session $Session -ScriptBlock {
        nssm set $using:ServiceName AppStdout $using:LogPath
        nssm set $using:ServiceName AppStderr $using:LogPath
    } -CaptureOutput

    Write-Log $Output.Output
}

function Get-AgentServiceName {
    return "contrail-vrouter-agent"
}

function Get-AgentExecutablePath {
    return "C:\Program Files\Juniper Networks\agent\contrail-vrouter-agent.exe"
}

function Get-AgentServiceStatus {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    Get-ServiceStatus -Session $Session -ServiceName (Get-AgentServiceName)
}

function New-AgentService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    $LogDir = Get-ComputeLogsDir
    $LogPath = Join-Path $LogDir "contrail-vrouter-agent-service.log"
    $ServiceName = Get-AgentServiceName
    $ExecutablePath = Get-AgentExecutablePath

    $ConfigPath = Get-DefaultAgentConfigPath
    $ConfigFileParam = "--config_file=$ConfigPath"

    Install-ServiceWithNSSM -Session $Session `
        -ServiceName $ServiceName `
        -ExecutablePath $ExecutablePath `
        -CommandLineParams @($ConfigFileParam)

    Out-StdoutAndStderrToLogFile -Session $Session `
        -ServiceName $ServiceName `
        -LogPath $LogPath
}

function Start-AgentService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    Write-Log "Starting Agent"

    $AgentServiceName = Get-AgentServiceName
    $Output = Invoke-NativeCommand -Session $Session -ScriptBlock {
        $Output = netstat -abq  #dial tcp bug debug output
        #TODO: After the bugfix, use Enable-Service generic function here.
        Start-Service $using:AgentServiceName
        return $Output
    } -CaptureOutput
    Write-Log $Output.Output
}

function Stop-AgentService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    Stop-RemoteService -Session $Session -ServiceName (Get-AgentServiceName)
}

function Remove-AgentService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    $ServiceName = Get-AgentServiceName
    $ServiceStatus = Get-ServiceStatus -Session $Session -ServiceName $ServiceName

    if ($ServiceStatus -ne "Stopped") {
        Stop-AgentService -Session $Session
    }
    Remove-ServiceWithNSSM -Session $Session -ServiceName $ServiceName
}
