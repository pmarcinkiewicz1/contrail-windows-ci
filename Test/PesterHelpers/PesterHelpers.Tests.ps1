. $PSScriptRoot\..\..\CIScripts\Common\Init.ps1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "PesterHelpers" -Tags CI, Unit {
    Context "Consistently" {
        It "works on trivial cases" {
            { Consistently { $true | Should Be $true } -Duration 3 } | Should Not Throw
            { Consistently { $true | Should Not Be $false } -Duration 3 } | Should Not Throw
            { Consistently { $true | Should Not Be $true } -Duration 3 } | Should Throw
        }

        It "calls assert multiple times until duration is reached" {
            $Script:Counter = 0
            Consistently { $Script:Counter += 1 } -Interval 1 -Duration 3
            $Script:Counter | Should Be 3
        }

        It "throws if inner assert is false at any time" {
            $Script:Counter = 0
            { Consistently { $Script:Counter += 1; $Script:Counter | Should Not Be 2 } `
                -Interval 1 -Duration 3 } | Should Throw
        }

        It "does not allow interval equal to zero" {
            { Consistently {} -Interval 0 -Duration 3 } | Should Throw
        }

        It "does not allow interval to be greater than duration" {
            { Consistently {} -Interval 3 -Duration 2 } | Should Throw
        }

        It "runs at least one time" {
            $Script:TimeCalled = 0
            Mock Get-Date {
                if ($Script:TimeCalled -eq 0) {
                    $Script:TimeCalled += 1
                    return $Script:MockStartDate.AddSeconds($Script:SecondsCounter)
                } else {
                    # simulate a lot of time has passed since the first call.
                    return $Script:MockStartDate.AddSeconds($Script:SecondsCounter + 100)
                }
            }
            $Script:WasCalled = $false
            Consistently { $Script:WasCalled = $true } -Duration 3
            $Script:WasCalled | Should Be $true
        }

        It "exception contains the same info as normal Pester exception" {
            try {
                "Foo" | Should Be "Bar"
            }
            catch {
                $OriginalMessage = $_.Exception.Message
            }

            try {
                Consistently { "Foo" | Should Be "Bar" } -Duration 3
            } catch {
                $_.Exception.Message | Should Match "Foo"
                $_.Exception.Message | Should Match "Bar"
                $_.Exception.Message | Should Be $OriginalMessage
            }
        }
    }

    Context "Eventually" {
        It "works on trivial cases" {
            { Eventually { $true | Should Be $true } -Duration 3 } | Should Not Throw
            { Eventually { $true | Should Not Be $false } -Duration 3 } | Should Not Throw
            { Eventually { $true | Should Not Be $true } -Duration 3 } | Should Throw
        }
        
        It "calls assert multiple times until it is true" {
            $Script:Counter = 0
            Eventually { $Script:Counter += 1; $Script:Counter | Should Be 3 } `
                -Interval 1 -Duration 5
            $Script:Counter | Should Be 3
        }

        It "throws if inner assert is never true" {
            $Script:Counter = 0
            { Eventually { $Script:Counter += 1; $Script:Counter | Should Be 6 } `
                -Interval 1 -Duration 4 } | Should Throw
        }

        It "does not allow interval equal to zero" {
            { Eventually {} -Interval 0 -Duration 3 } | Should Throw
        }

        It "does not allow interval to be greater than duration" {
            { Eventually {} -Interval 3 -Duration 2 } | Should Throw
        }

        It "rethrows the last exception that occurred" {
            $Script:Messages = @("E1", "E2", "E3", "E4", "E5")
            $Script:Counter = 0
            try {
                Eventually {
                    $Exception = $Script:Messages[$Script:Counter];
                    $Script:Counter += 1;
                    throw $Exception
                } -Duration 3
            } catch {
                $_.Exception.InnerException.Message | `
                    Should Be "E4"
            }
        }

        It "rethrows the last Pester exception in trivial case" {
            try {
                "Foo" | Should Be "Bar"
            }
            catch {
                $OriginalMessage = $_.Exception.Message
            }

            try {
                Eventually { "Foo" | Should Be "Bar" } -Duration 3
            } catch {
                $_.Exception.InnerException.Message | Should Match "Foo"
                $_.Exception.InnerException.Message | Should Match "Bar"
                $_.Exception.InnerException.Message | Should Be $OriginalMessage
            }
        }

        It "allows a long condition always to run twice" {
            $Script:Counter = 0

            Eventually {
                Start-Sleep -Seconds 20
                $Script:Counter += 1
                $Script:Counter | Should Be 2
            } -Duration 10
        }
    }

    BeforeEach {
        $Script:MockStartDate = Get-Date
        $Script:SecondsCounter = 0
        Mock Start-Sleep {
            Param($Seconds)
            $Script:SecondsCounter += $Seconds;
        }
        Mock Get-Date {
            return $Script:MockStartDate.AddSeconds($Script:SecondsCounter)
        }
    }
}
