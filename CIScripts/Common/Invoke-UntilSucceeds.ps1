. $PSScriptRoot\Aliases.ps1
. $PSScriptRoot\Exceptions.ps1

class HardError : System.Exception {
    HardError([string] $msg) : base($msg) {}
    HardError([string] $msg, [System.Exception] $inner) : base($msg, $inner) {}
}

function Invoke-UntilSucceeds {
    <#
    .SYNOPSIS
    Repeatedly calls a script block until its return value evaluates to true. Subsequent calls
    happen after Interval seconds. Will catch any exceptions that occur in the meantime.
    If the exception being thrown is a HardError, no further retry attempps will be made.
    User has to specify a timeout after which the function fails by setting the Duration (or NumRetires) parameter.
    If the function fails, it throws an exception containing the last reason of failure.

    Invoke-UntilSucceeds can work in two modes: number of retries limit (-NumRetries)
    or retrying until timeout (-Duration). When Duration is set,
    it is guaranteed that that if Invoke-UntilSucceeds had failed and precondition was true,
    there was at least one check performed at time T where T >= T_start + Duration.

    .PARAMETER ScriptBlock
    ScriptBlock to repeatedly call.
    .PARAMETER Interval
    Interval (in seconds) between retries.
    .PARAMETER Duration
    Timeout (in seconds).
    .PARAMETER NumRetries
    Maximum number of retries to perform.
    .PARAMETER Name
    Name of the function to be used in exceptions' messages.
    .Parameter AssumeTrue
    If set, Invoke-UntilSucceeds doesn't check the returned value at all
    (it will still treat exceptions as failure though).
    #>
    Param (
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true)] [ScriptBlock] $ScriptBlock,
        [Parameter(Mandatory=$false)] [int] $Interval = 1,
        [Parameter(Mandatory=$false)] [int] $Duration,
        [Parameter(Mandatory=$false)] [int] $NumRetries,
        [Parameter(Mandatory=$false)] [ScriptBlock] $Precondition,
        [Parameter(Mandatory=$false)] [String] $Name = "Invoke-UntilSucceds",
        [Switch] $AssumeTrue
    )

    if ((-not $Duration) -and (-not $NumRetries)) {
        throw "Either non-zero -Duration or -NumRetries has to be specified"
    }

    if ($Duration) {
        if ($NumRetries) {
            throw "-Duration can't be used with -Retries"
        }

        if ($Duration -lt $Interval) {
            throw "Duration must be longer than interval"
        }
    }

    if ($Interval -eq 0) {
        throw "Interval must not be equal to zero"
    }
    $StartTime = Get-Date

    $NumRetry = 0

    while ($true) {
        $NumRetry += 1

        $LastCheck = if ($Duration) {
            ((Get-Date) - $StartTime).TotalSeconds -ge $Duration
        } else {
            $NumRetry -eq $NumRetries
        }

        try {
            $ReturnVal = Invoke-Command $ScriptBlock

            if ($AssumeTrue -or $ReturnVal) {
                return $ReturnVal
            } else {
                throw [CITimeoutException]::new(
                    "${Name}: Did not evaluate to True. Last return value encountered was: $ReturnVal."
                )
            }
        } catch [HardError] {
            throw [CITimeoutException]::new(
                "${Name}: Stopped retrying because HardError was thrown",
                $_.Exception.InnerException
            )
        } catch {
            if ($LastCheck) {
                throw [CITimeoutException]::new("$Name failed.", $_.Exception)
            } else {
                Start-Sleep -Seconds $Interval
            }
        }
    }
}
