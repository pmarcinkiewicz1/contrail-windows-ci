. $PSScriptRoot\..\..\CIScripts\Common\Aliases.ps1
. $PSScriptRoot\..\..\CIScripts\Common\Invoke-NativeCommand.ps1

. $PSScriptRoot\PesterLogger.ps1

class CollectedLog {
    [String] $Name
}

class ValidCollectedLog : CollectedLog {
    [String] $Name
    [String] $Tag
    [Object] $Content
}

class InvalidCollectedLog : CollectedLog {
    [Object] $Err
}

class LogSource {
    [System.Management.Automation.Runspaces.PSSession] $Session

    [CollectedLog[]] GetContent() {
        throw "LogSource is an abstract class, use specific log source instead"
    }

    ClearContent() {
        throw "LogSource is an abstract class, use specific log source instead"
    }
}

class FileLogSource : LogSource {
    [String] $Path

    [CollectedLog[]] GetContent() {
        $ContentGetterBody = {
            Param([Parameter(Mandatory = $true)] [string] $From)
            $Files = Get-ChildItem -Path $From -ErrorAction SilentlyContinue
            $Logs = @()
            if (-not $Files) {
                $Logs += @{
                    Name = $From
                    Err = "<FILE NOT FOUND>"
                }
            } else {
                foreach ($File in $Files) {
                    $Content = Get-Content -Raw $File
                    $Logs += @{
                        Name = $File
                        Tag = $File.BaseName
                        Content = $Content
                    }
                }
            }
            return $Logs
        }

        # We cannot create [ValidCollectedLog] and [InvalidCollectedLog] classes directly
        # in the closure, as it may be executed in remote session, so as a workaround
        # we need to fix the types afterwards.
        return Invoke-CommandRemoteOrLocal -Func $ContentGetterBody -Session $this.Session -Arguments $this.Path |
            ForEach-Object {
                if ($_['Err']) {
                    [InvalidCollectedLog] $_
                } else {
                    [ValidCollectedLog] $_
                }
            }
    }

    ClearContent() {
        $LogCleanerBody = {
            Param([Parameter(Mandatory = $true)] [string] $What)
            $Files = Get-ChildItem -Path $What -ErrorAction SilentlyContinue
            foreach ($File in $Files) {
                try {
                    Remove-Item $File
                }
                catch {
                    Write-Warning "$File was not removed due to $_"
                }
            }
        }
        Invoke-CommandRemoteOrLocal -Func $LogCleanerBody -Session $this.Session -Arguments $this.Path
    }
}

class ContainerLogSource : LogSource {
    [String] $Container

    [CollectedLog[]] GetContent() {
        $Command = Invoke-NativeCommand -Session $this.Session -CaptureOutput -AllowNonZero {
            docker logs $Using:this.Container
        }
        $Name = "$( $this.Container ) container logs"

        $Log = if ($Command.ExitCode -eq 0) {
            [ValidCollectedLog] @{
                Name = $Name
                Tag = $this.Container
                Content = $Command.Output
            }
        } else {
            [InvalidCollectedLog] @{
                Name = $Name
                Err = $Command.Output
            }
        }
        return $Log
    }

    ClearContent() {
        # It's not possible to clear docker container logs,
        # but the --since flag may be used in GetContent instead.
    }
}

function New-ContainerLogSource {
    Param([Parameter(Mandatory = $true)] [string[]] $ContainerNames,
          [Parameter(Mandatory = $false)] [PSSessionT[]] $Sessions)

    return $Sessions | ForEach-Object {
        $Session = $_
        $ContainerNames | ForEach-Object {
            [ContainerLogSource] @{
                Session = $Session
                Container = $_
            }
        }
    }
}

function New-FileLogSource {
    Param([Parameter(Mandatory = $true)] [string] $Path,
          [Parameter(Mandatory = $false)] [PSSessionT[]] $Sessions)

    return $Sessions | ForEach-Object {
        [FileLogSource] @{
            Session = $_
            Path = $Path
        }
    }
}

function Invoke-CommandRemoteOrLocal {
    param([ScriptBlock] $Func, [PSSessionT] $Session, [Object[]] $Arguments) 
    if ($Session) {
        Invoke-Command -Session $Session $Func -ArgumentList $Arguments
    } else {
        Invoke-Command $Func -ArgumentList $Arguments
    }
}

function Merge-Logs {
    Param([Parameter(Mandatory = $true)] [LogSource[]] $LogSources,
          [Parameter(Mandatory = $false)] [switch] $DontCleanUp)

    foreach ($LogSource in $LogSources) {
        $SourceHost = if ($LogSource.Session) {
            $LogSource.Session.ComputerName
        } else {
            "localhost"
        }
        $ComputerNamePrefix = "Logs from $($SourceHost): "
        Write-Log ("=" * 100)
        Write-Log $ComputerNamePrefix

        foreach ($Log in $LogSource.GetContent()) {
            if ($Log -is [ValidCollectedLog]) {
                Write-Log ("-" * 100)
                Write-Log "Contents of $( $Log.Name ):"
                if ($Log.Content) {
                    Write-Log -NoTimestamp -Tag $Log.Tag $Log.Content
                } else {
                    Write-Log "<EMPTY>"
                }
            } else {
                Write-Log "Error retrieving $( $Log.Name ):"
                Write-Log $Log.Err
            }
        }
        
        if (-not $DontCleanUp) {
            $LogSource.ClearContent()
        }
    }

    Write-Log ("=" * 100)
}
