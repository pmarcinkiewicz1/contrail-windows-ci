# CI Selfcheck

CI has a set of unit and integration tests, called 'CI selfcheck'.

## Requirements

### Tests

Requires PowerShell test framework: `Pester 4.2.0`. See [this link](https://github.com/pester/Pester/wiki/Installation-and-Update) for installation instructions.

### Static analysis (optional)

Requires at least `PSScriptAnalyzer 1.17.0`. See [this link](https://github.com/PowerShell/PSScriptAnalyzer) for installation instructions.

## To run unit tests and static analysis of CI:

```
.\Invoke-Selfcheck.ps1
```

## To also run system tests of CI:

```
.\Invoke-Selfcheck.ps1 -TestenvConfFile './path/to/testenvconf.yaml'
```

Note: to make sure that system tests pass, some requirements must be met.

### Systest requirements:

* testenvconf.yaml
* Reportunit 1.5.0-beta present in PATH

## Skip static analysis

```
.\Invoke-Selfcheck.ps1 -SkipStaticAnalysis
```

## Skip unit tests

```
.\Invoke-Selfcheck.ps1 -SkipUnit
```

## Generate NUnit reports

```
.\Invoke-Selfcheck.ps1 -ReportPath out.xml
```

## Collect code coverage stats

```
.\Invoke-Selfcheck.ps1 -CodeCoverage
```

## To manually run tests from local machine

Please see [this document](CIScripts/Test/Tests/README.md).

------------------

## Note to developers

The idea behind this tool is that anyone can run the basic set of tests without ANY preparation
(except Pester).
A new developer should be able to run `.\Invoke-Selfcheck.ps1` and it should pass 100% of the time,
without any special requirements, like libraries, testbed machines etc.
Special flags may be passed to invoke more complicated tests (that have requirements), but
the default should require nothing.
