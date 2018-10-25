Import-Module Pester

. $PSScriptRoot\..\..\CIScripts\Common\Aliases.ps1
. $PSScriptRoot\..\..\CIScripts\Common\Invoke-UntilSucceeds.ps1

function Consistently {
    <#
    .SYNOPSIS
    Utility wrapper for Pester for making sure that the assert is consistently true.
    It works by retrying the assert every Interval seconds, up to Duration.
    .PARAMETER ScriptBlock
    ScriptBlock containing a Pester assertion.
    .PARAMETER Interval
    Interval (in seconds) between retries.
    .PARAMETER Duration
    Timeout (in seconds).
    #>
    Param (
        [Parameter(Mandatory=$true)] [ScriptBlock] $ScriptBlock,
        [Parameter(Mandatory=$false)] [int] $Interval = 1,
        [Parameter(Mandatory=$true)] [int] $Duration = 3
    )
    if ($Duration -lt $Interval) {
        throw [CITimeoutException] "Duration must be longer than interval"
    }
    if ($Interval -eq 0) {
        throw [CITimeoutException] "Interval must not be equal to zero"
    }
    $StartTime = Get-Date
    do {
        & $ScriptBlock
        Start-Sleep -s $Interval
    } while (((Get-Date) - $StartTime).Seconds -lt $Duration)
}

function Eventually {
    <#
    .SYNOPSIS
    Utility wrapper for Pester for making sure that the assert is eventually true.
    It works by retrying the assert every Interval seconds, up to Duration. If until then,
    the assert is not true, Eventually fails.

    It is guaranteed that that if Eventually had failed, there was
    at least one check performed at time T where T >= T_start + Duration
    .PARAMETER ScriptBlock
    ScriptBlock containing a Pester assertion.
    .PARAMETER Interval
    Interval (in seconds) between retries.
    .PARAMETER Duration
    Timeout (in seconds).
    #>
    Param (
        [Parameter(Mandatory=$true)] [ScriptBlock] $ScriptBlock,
        [Parameter(Mandatory=$false)] [int] $Interval = 1,
        [Parameter(Mandatory=$true)] [int] $Duration = 3
    )

    Invoke-UntilSucceeds `
            -ScriptBlock $ScriptBlock `
            -AssumeTrue `
            -Interval $Interval `
            -Duration $Duration `
            -Name "Eventually"
}

function Test-WithRetries {
    Param (
        [Parameter(Mandatory=$true, Position = 0)] [int] $MaxNumRetries,
        [Parameter(Mandatory=$true, Position = 1)] [ScriptBlock] $ScriptBlock
    )
    $NumRetry = 1
    $GoodJob = $false
    while ($NumRetry -le $MaxNumRetries -and -not $GoodJob) {
        $FailedCountBeforeRunningTests = InModuleScope Pester {
            return $Pester.FailedCount
        }
        $NumRetry += 1
        Invoke-Command $ScriptBlock
        $FailedCountAfterRunningTests = InModuleScope Pester {
            return $Pester.FailedCount
        }
        if ($FailedCountBeforeRunningTests -eq $FailedCountAfterRunningTests) {
            $GoodJob = $true
        }
    }
}

function Test-ResultsWithRetries {
    Param ([Parameter(Mandatory=$true)] [object] $Results)

    function Test-HasAnySuccess {
        Param (
            [Parameter(Mandatory=$true)] [String] $Describe,
            [Parameter(Mandatory=$true)] [String] $Context,
            [Parameter(Mandatory=$true)] [String] $Name
        )

        ForEach ($Result in $Results) {
            if ($Result.Describe -eq $Describe `
                -and $Result.Context -eq $Context `
                -and $Result.Name -eq $Name `
                -and $Result.Result -eq "Passed") {
                    return $true
            }
        }

        return $false
    }

    ForEach ($Result in $Results) {
        if ($Result.Result -eq "Failed") {
            $AnySuccess = Test-HasAnySuccess `
                -Describe $Result.Describe `
                -Context $Result.Context `
                -Name $Result.Name
            if (-not $AnySuccess) {
                return $false
            }
        }
    }

    return $true
}

function Suspend-PesterOnException {
    InModuleScope Pester {
        function global:InvokeTest_Changed {
            [CmdletBinding(DefaultParameterSetName = 'Normal')]
            param (
                [Parameter(Mandatory = $true)]
                [string] $Name,

                [Parameter(Mandatory = $true)]
                [ScriptBlock] $ScriptBlock,

                [scriptblock] $OutputScriptBlock,

                [System.Collections.IDictionary] $Parameters,
                [string] $ParameterizedSuiteName,

                [Parameter(ParameterSetName = 'Pending')]
                [Switch] $Pending,

                [Parameter(ParameterSetName = 'Skip')]
                [Alias('Ignore')] [Switch] $Skip
            )

            if ($null -eq $Parameters) { $Parameters = @{} }

            try {
                if ($Skip) { $Pester.AddTestResult($Name, "Skipped", $null) }
                elseif ($Pending) { $Pester.AddTestResult($Name, "Pending", $null) }
                else {
                    $errorRecord = $null
                    try {
                        $pester.EnterTest()
                        Invoke-TestCaseSetupBlocks
                        do { $null = & $ScriptBlock @Parameters } until ($true)
                    }
                    catch {
                        Write-Host "It failed, press any key to continue..." -ForegroundColor Red
                        [console]::beep(440,1000)
                        Read-Host
                        $errorRecord = $_
                    }
                    finally {
                        try { Invoke-TestCaseTeardownBlocks }
                        catch { $errorRecord = $_ }
                        $pester.LeaveTest()
                    }
                    $result = ConvertTo-PesterResult -Name $Name -ErrorRecord $errorRecord
                    $orderedParameters = Get-OrderedParameterDictionary -ScriptBlock $ScriptBlock -Dictionary $Parameters
                    $Pester.AddTestResult( $result.name, $result.Result, $null, $result.FailureMessage, $result.StackTrace, $ParameterizedSuiteName, $orderedParameters, $result.ErrorRecord )
                }
            }
            finally { Exit-MockScope -ExitTestCaseOnly }

            if ($null -ne $OutputScriptBlock) { $Pester.testresult[-1] | & $OutputScriptBlock }
        }

        New-Alias -Name 'Invoke-Test' -Value 'InvokeTest_Changed' -Scope Global -ErrorAction Ignore
    }
}
