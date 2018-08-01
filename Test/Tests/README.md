# How to run tests from local machine on VMs in Juniper Windows CI Lab

1. Deploy dev env using `deploy-dev-env` job.

2. Install Pester:

    ```Install-Module -Name Pester -Force -SkipPublisherCheck -RequiredVersion 4.2.0```

3. Install `powershell-yaml`:

    ```Install-Module powershell-yaml```

4. Copy `testenv-conf.yaml.sample` to `testenv-conf.yaml` file and replace all occurences of:
    * `<CONTROLLER_IP>` - Controller IP address, accessible from local machine (network 10.84.12.0/24 in current setup)
    * `<TESTBED1_NAME>`, `<TESTBED2_NAME>` - Testbeds hostnames
    * `<TESTBED1_IP>`, `<TESTBED2_IP>` - Testbeds IP addresses, accessible from local machine (the same network as for Controller)

5. Run selected test, e.g.:

    ```Invoke-Pester -Script @{ Path = ".\TunnellingWithAgent.Tests.ps1"; Parameters = @{ TestenvConfFile = "testenv-conf.yaml"}; } -TestName 'Tunnelling with Agent tests'```

## CI Selfcheck

To run CI Selfcheck please see [this document](../../../SELFCHECK.md).
