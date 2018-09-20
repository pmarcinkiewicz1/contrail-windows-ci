# Run all available PowerShell linters

To run all available linters, execute the following command in this directory:

```
.\Invoke-StaticAnalysisTools.ps1 -RootDir .. -ConfigDir $pwd
```

## Powershell Script Analyzer (PSSCriptAnalyzer)

Requires at least `PSScriptAnalyzer 1.17.0`. See [this link](https://github.com/PowerShell/PSScriptAnalyzer) for installation instructions.
To run using our settings:

```
Invoke-ScriptAnalyzer .. -Recurse -Settings C:\Full\Path\To\contrail-windows-ci\StaticAnalysis\PSScriptAnalyzerSettings.psd1
```

## Run all available Ansible linters

To run all available linters, execute the following command in root directory:

```
./StaticAnalysis/ansible_linter.py
```
