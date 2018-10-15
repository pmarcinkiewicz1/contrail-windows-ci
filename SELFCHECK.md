# CI Selfcheck

CI has a set of unit and integration tests, called 'CI selfcheck'.

## Requirements

* "Pester" PowerShell test framework: `Pester 4.2.0`. See [this link](https://github.com/pester/Pester/wiki/Installation-and-Update) for installation instructions.

### Static analysis (optional)

* Requires at least `PSScriptAnalyzer 1.17.0`. See [this link](https://github.com/PowerShell/PSScriptAnalyzer) for installation instructions.

### Systest requirements:

* testenvconf.yaml
* Reportunit 1.5.0-beta present in PATH

## Running

```
.\Invoke-Selfcheck.ps1 [-TestenvConfFile './testenvconf.yaml'] [-$ReportPath './report'] [-SkipUnit] [-SkipStaticAnalysis] [-CodeCoverage]
```

Examples:

* run unit tests and static analysis of CI:

  ```
  .\Invoke-Selfcheck.ps1
  ```

* run unit and system tests of CI:

  ```
  .\Invoke-Selfcheck.ps1 -TestenvConfFile './path/to/testenvconf.yaml'
  ```
  Note: to make sure that system tests pass, some requirements must be met (consult Sytest requirements above).
  
* skip static analysis

  ```
  .\Invoke-Selfcheck.ps1 -SkipStaticAnalysis
  ```

* skip unit tests

  ```
  .\Invoke-Selfcheck.ps1 -SkipUnit
  ```

* generate NUnit reports

  ```
  .\Invoke-Selfcheck.ps1 -ReportPath out.xml
  ```

* collect code coverage stats

  ```
  .\Invoke-Selfcheck.ps1 -CodeCoverage
  ```
  Note: this may take a couple minutes.

------------------

# For developers

The idea behind this tool is that anyone can run the basic set of tests without ANY preparation
(except Pester).
A new developer should be able to run `.\Invoke-Selfcheck.ps1` and it should pass 100% of the time,
without any special requirements, like libraries, testbed machines etc.
Special flags may be passed to invoke more complicated tests (that have requirements), but
the default should require nothing.

### Tags

`.\Invoke-Selfcheck.ps1` will look for Pester `Describe` blocks tagged with `CI`.
Integration and unit tests can be differentiated using `Systest` and `Unit` tags.
If a test requires an external dependency (like running Contrail Controller, Windows Compute
nodes or even a binary present on the OS), then it's a systest. Otherwise, it's probably a unit test.
