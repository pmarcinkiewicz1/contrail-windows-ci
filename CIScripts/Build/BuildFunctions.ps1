. $PSScriptRoot\..\Common\Invoke-NativeCommand.ps1
. $PSScriptRoot\..\Build\Repository.ps1

function Initialize-BuildEnvironment {
    Param ([Parameter(Mandatory = $true)] [string] $ThirdPartyCache)
    $Job.Step("Copying common third-party dependencies", {
        if (!(Test-Path -Path .\third_party)) {
            New-Item -ItemType Directory .\third_party | Out-Null
        }
        Get-ChildItem "$ThirdPartyCache\common" -Directory |
            Where-Object{$_.Name -notlike "boost*"} |
            Copy-Item -Destination third_party\ -Recurse -Force
    })

    $Job.Step("Copying SConstruct from tools\build", {
        Copy-Item tools\build\SConstruct .
    })
}

function Set-MSISignature {
    Param ([Parameter(Mandatory = $true)] [string] $SigntoolPath,
           [Parameter(Mandatory = $true)] [string] $CertPath,
           [Parameter(Mandatory = $true)] [string] $CertPasswordFilePath,
           [Parameter(Mandatory = $true)] [string] $MSIPath)
    $Job.Step("Signing MSI", {
        $cerp = Get-Content $CertPasswordFilePath
        Invoke-NativeCommand -ScriptBlock {
            & $SigntoolPath sign /f $CertPath /p $cerp $MSIPath
        }
    })
}

function Invoke-DockerDriverBuild {
    Param ([Parameter(Mandatory = $true)] [string] $DriverSrcPath,
           [Parameter(Mandatory = $true)] [string] $SigntoolPath,
           [Parameter(Mandatory = $true)] [string] $CertPath,
           [Parameter(Mandatory = $true)] [string] $CertPasswordFilePath,
           [Parameter(Mandatory = $true)] [string] $OutputPath,
           [Parameter(Mandatory = $true)] [string] $LogsPath)

    $Job.PushStep("Docker driver build")
    $GoPath = Get-Location
    if (Test-Path Env:GOPATH) {
        $GoPath +=  ";$Env:GOPATH"
    }
    $Env:GOPATH = $GoPath
    $srcPath = "$GoPath/src/$DriverSrcPath"

    New-Item -ItemType Directory ./bin | Out-Null

    Push-Location $srcPath
    $Job.Step("Fetch third party packages ", {
        Invoke-NativeCommand -ScriptBlock {
            & dep ensure -v
        }

        Invoke-NativeCommand -ScriptBlock {
            & dep prune -v
        }
    })
    Pop-Location # $srcPath

    $Job.Step("Contrail-go-api source code generation", {
        Invoke-NativeCommand -ScriptBlock {
            py src/contrail-api-client/generateds/generateDS.py -q -f `
                                    -o $srcPath/vendor/github.com/Juniper/contrail-go-api/types/ `
                                    -g golang-api src/contrail-api-client/schema/vnc_cfg.xsd

            # Workaround on https://github.com/golang/go/issues/18468
            Copy-Item -Path $srcPath/vendor/* -Destination $GoPath/src -Force -Recurse
            Remove-Item -Path $srcPath/vendor -Force -Recurse
        }
    })

    $Job.Step("Building driver and precompiling tests", {
        # TODO: Handle new name properly
        Push-Location $srcPath
        Invoke-NativeCommand -ScriptBlock {
            & $srcPath\Invoke-Build.ps1
        }
        Pop-Location # $srcPath
    })


    $Job.Step("Copying artifacts to $OutputPath", {
        Copy-Item -Path $srcPath\build\* -Include "*.msi", "*.exe" -Destination $OutputPath
    })

    $Job.Step("Signing MSI", {
        Push-Location $OutputPath
        Set-MSISignature -SigntoolPath $SigntoolPath `
                        -CertPath $CertPath `
                        -CertPasswordFilePath $CertPasswordFilePath `
                        -MSIPath (Get-ChildItem "*.msi").FullName
        Pop-Location # $OutputPath
    })

    $Job.PopStep()
}

function Invoke-ExtensionBuild {
    Param ([Parameter(Mandatory = $true)] [string] $ThirdPartyCache,
           [Parameter(Mandatory = $true)] [string] $SigntoolPath,
           [Parameter(Mandatory = $true)] [string] $CertPath,
           [Parameter(Mandatory = $true)] [string] $CertPasswordFilePath,
           [Parameter(Mandatory = $true)] [string] $OutputPath,
           [Parameter(Mandatory = $true)] [string] $LogsPath,
           [Parameter(Mandatory = $false)] [string] $BuildMode = "debug")

    $Job.PushStep("Extension build")

    $Job.Step("Copying Extension dependencies", {
        Copy-Item -Recurse "$ThirdPartyCache\extension\*" third_party\
    })

    $BuildModeOption = "--optimization=" + $BuildMode

    $Job.Step("Building Extension and Utils", {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments",
            "", Justification="Cerp env variable required by vRouter build.")]
        $Env:cerp = Get-Content $CertPasswordFilePath

        Invoke-NativeCommand -ScriptBlock {
            scons $BuildModeOption vrouter | Tee-Object -FilePath $LogsDir/vrouter_build.log
        }
    })

    $Job.Step("Running kernel unit tests", {
        Invoke-NativeCommand -ScriptBlock {
            scons $BuildModeOption kernel-tests | Tee-Object -FilePath $LogsDir/vrouter_unit_tests.log
        }
    })

    $vRouterBuildRoot = "build\{0}\vrouter" -f $BuildMode
    $vRouterMSI = "$vRouterBuildRoot\extension\vRouter.msi"
    $vRouterCert = "$vRouterBuildRoot\extension\vRouter.cer"
    $utilsMSI = "$vRouterBuildRoot\utils\utils.msi"

    Write-Host "Signing utilsMSI"
    Set-MSISignature -SigntoolPath $SigntoolPath `
                     -CertPath $CertPath `
                     -CertPasswordFilePath $CertPasswordFilePath `
                     -MSIPath $utilsMSI

    Write-Host "Signing vRouterMSI"
    Set-MSISignature -SigntoolPath $SigntoolPath `
                     -CertPath $CertPath `
                     -CertPasswordFilePath $CertPasswordFilePath `
                     -MSIPath $vRouterMSI

    $Job.Step("Copying artifacts to $OutputPath", {
        Copy-Item $utilsMSI $OutputPath -Recurse
        Copy-Item $vRouterMSI $OutputPath -Recurse
        Copy-Item $vRouterCert $OutputPath -Recurse
    })

    $Job.PopStep()
}

function Copy-VtestScenarios {
    Param ([Parameter(Mandatory = $true)] [string] $OutputPath)

    $Job.Step("Copying vtest scenarios to $OutputPath", {
        $vTestSrcPath = "vrouter\utils\vtest\"
        Copy-Item "$vTestSrcPath\tests" $OutputPath -Recurse -Filter "*.xml"
        Copy-Item "$vTestSrcPath\*.ps1" $OutputPath
    })
}

function Invoke-AgentBuild {
    Param ([Parameter(Mandatory = $true)] [string] $ThirdPartyCache,
           [Parameter(Mandatory = $true)] [string] $SigntoolPath,
           [Parameter(Mandatory = $true)] [string] $CertPath,
           [Parameter(Mandatory = $true)] [string] $CertPasswordFilePath,
           [Parameter(Mandatory = $true)] [string] $OutputPath,
           [Parameter(Mandatory = $true)] [string] $LogsPath,
           [Parameter(Mandatory = $false)] [string] $BuildMode = "debug")

    $Job.PushStep("Agent build")

    $Job.Step("Copying Agent dependencies", {
        Copy-Item -Recurse "$ThirdPartyCache\agent\*" third_party/
    })

    $Job.Step("Building contrail-vrouter-agent.exe and .msi", {
        if(Test-Path Env:AGENT_BUILD_THREADS) {
            $Threads = $Env:AGENT_BUILD_THREADS
        } else {
            $Threads = 1
        }
        $AgentBuildCommand = "scons -j {0} --opt={1} contrail-vrouter-agent.msi" -f $Threads, $BuildMode
        Invoke-NativeCommand -ScriptBlock {
            Invoke-Expression $AgentBuildCommand | Tee-Object -FilePath $LogsPath/build_agent.log
        }
    })

    $agentMSI = "build\$BuildMode\vnsw\agent\contrail\contrail-vrouter-agent.msi"

    Write-Host "Signing agentMSI"
    Set-MSISignature -SigntoolPath $SigntoolPath `
                     -CertPath $CertPath `
                     -CertPasswordFilePath $CertPasswordFilePath `
                     -MSIPath $agentMSI

    $Job.Step("Copying artifacts to $OutputPath", {
        Copy-Item $agentMSI $OutputPath -Recurse
    })

    $Job.PopStep()
}

function Invoke-NodemgrBuild {
    Param ([Parameter(Mandatory = $true)] [string] $OutputPath,
           [Parameter(Mandatory = $true)] [string] $LogsPath,
           [Parameter(Mandatory = $false)] [string] $BuildMode = "debug")

    $Job.PushStep("Nodemgr build")

    $Job.Step("Building nodemgr", {
        $Components = @(
            "database:node_mgr",
            "build/$BuildMode/sandesh/common/dist",
            "sandesh/library/python:pysandesh",
            "vrouter:node_mgr",
            "contrail-nodemgr"
        )

        Invoke-NativeCommand -ScriptBlock {
            scons --opt=$BuildMode @Components | Tee-Object -FilePath $LogsPath/build_nodemgr.log
        }
    })

    $Job.Step("Copying artifacts to $OutputPath", {
        $ArchivesFolders = @(
            "analytics\database",
            "sandesh\common",
            "tools\sandesh\library\python",
            "vnsw\agent\uve",
            "nodemgr"
        )
        ForEach ($ArchiveFolder in $ArchivesFolders) {
            Copy-Item "build\$BuildMode\$ArchiveFolder\dist\*.tar.gz" $OutputPath
        }
    })

    $Job.PopStep()
}

function Copy-DebugDlls {
    Param ([Parameter(Mandatory = $true)] [string] $OutputPath)

    $Job.Step("Copying dlls to $OutputPath", {
        foreach ($Lib in @("ucrtbased.dll", "vcruntime140d.dll", "msvcp140d.dll")) {
            Copy-Item "C:\Windows\System32\$Lib" $OutputPath
        }
    })
}

function Test-IfGTestOutputSuggestsThatAllTestsHavePassed {
    Param ([Parameter(Mandatory = $true)] [Object[]] $TestOutput)
    $NumberOfTests = -1
    Foreach ($Line in $TestOutput) {
        if ($Line -match "\[==========\] (?<HowManyTests>[\d]+) test[s]? from [\d]+ test [\w]* ran[.]*") {
            $NumberOfTests = $matches.HowManyTests
        }
        if ($Line -match "\[  PASSED  \] (?<HowManyTestsHavePassed>[\d]+) test[.]*" -and $NumberOfTests -ge 0) {
            return $($matches.HowManyTestsHavePassed -eq $NumberOfTests)
        }
    }
    return $False
}

function Invoke-AgentUnitTestRunner {
    Param ([Parameter(Mandatory = $true)] [String] $TestExecutable)
    Write-Host "===> Agent tests: running $TestExecutable..."
    $Res = Invoke-Command -ScriptBlock {
        $Command = Invoke-NativeCommand -AllowNonZero -CaptureOutput -ScriptBlock {
            Invoke-Expression $TestExecutable
        }

        # This is a workaround for the following bug:
        # https://bugs.launchpad.net/opencontrail/+bug/1714205
        # Even if all tests actually pass, test executables can sometimes
        # return non-zero exit code.
        # TODO: It should be removed once the bug is fixed (JW-1110).
        $SeemsLegitimate = Test-IfGTestOutputSuggestsThatAllTestsHavePassed -TestOutput $Command.Output
        if ($Command.ExitCode -eq 0 -or $SeemsLegitimate) {
            return 0
        } else {
            return $Command.ExitCode
        }
    }

    if ($Res -eq 0) {
        Write-Host "        Succeeded."
    } else {
        Write-Host "        Failed (exit code: $Res)."
    }
    return $Res
}

function Invoke-AgentTestsBuild {
    Param ([Parameter(Mandatory = $true)] [string] $LogsPath,
           [Parameter(Mandatory = $false)] [string] $BuildMode = "debug")

    $Job.PushStep("Agent Tests build")

    $BuildModeOption = "--optimization=" + $BuildMode

    $Job.Step("Building agent tests", {
        $Tests = @(
            "agent:test_ksync",
            "src/ksync:ksync_test",
            "src/dns:dns_bind_test",
            "src/dns:dns_config_test",
            "src/dns:dns_mgr_test",
            "controller/src/schema:test",
            "src/xml:xml_test",
            "controller/src/xmpp:test",
            "src/base:libtask_test",
            "src/base:bitset_test",
            "src/base:index_allocator_test",
            "src/base:dependency_test",
            "src/base:label_block_test",
            "src/base:queue_task_test",
            "src/base:subset_test",
            "src/base:patricia_test",
            "src/base:boost_US_test"

            # oper
            "agent:test_agent_sandesh",
            "agent:test_config_manager",
            "agent:test_intf",
            "agent:test_intf_policy",
            "agent:test_find_scale",
            "agent:test_logical_intf",
            "agent:test_vrf_assign",
            "agent:test_inet_interface",
            "agent:test_aap6",
            "agent:test_ipv6",
            "agent:test_forwarding_class",
            "agent:test_qos_config",
            "agent:test_oper_xml",
            "agent:ifmap_dependency_manager_test",
            "agent:test_physical_devices"
        )

        $TestsString = ""
        if ($Tests.count -gt 0) {
            $TestsString = $Tests -join " "
        }
        $TestsBuildCommand = "scons -j 4 {0} {1}" -f "$BuildModeOption", "$TestsString"

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments",
            "", Justification="Env variable is used by another executable")]
        $Env:BUILD_ONLY = "1"
        Invoke-NativeCommand -ScriptBlock {
            Invoke-Expression $TestsBuildCommand | Tee-Object -FilePath $LogsPath/build_agent_tests.log
        }
        Remove-Item Env:\BUILD_ONLY
    })

    $rootBuildDir = "build\$BuildMode"

    $Job.Step("Running agent tests", {
        $backupPath = $Env:Path
        $Env:Path += ";" + $(Get-Location).Path + "\build\bin"

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments",
            "", Justification="TASK_UTIL_WAIT_TIME is used agent tests for determining timeout's " +
            "threshold. They were copied from Linux unit test job.")]
        $Env:TASK_UTIL_WAIT_TIME = 10000

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments",
            "", Justification="TASK_UTIL_RETRY_COUNT is used agent tests for determining " +
            "timeout's threshold. They were copied from Linux unit test job.")]
        $Env:TASK_UTIL_RETRY_COUNT = 6000

        $TestsFolders = @(
            "base\test",
            "dns\test",
            "ksync\test",
            "schema\test",
            "vnsw\agent\cmn\test",
            "vnsw\agent\oper\test",
            "vnsw\agent\test",
            "xml\test",
            "xmpp\test"
        ) | ForEach-Object { "$rootBuildDir\$_" }

        $AgentExecutables = Get-ChildItem -Recurse $TestsFolders | Where-Object {$_.Name -match '.*\.exe$'}
        Foreach ($TestExecutable in $AgentExecutables) {
            $TestRes = Invoke-AgentUnitTestRunner -TestExecutable $TestExecutable.FullName
            if ($TestRes -ne 0) {
                throw "Running agent tests failed"
            }
        }

        $Env:Path = $backupPath
    })

    $Job.PopStep()
}
