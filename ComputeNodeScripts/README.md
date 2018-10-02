# Compute node scripts

This directory contains utility scripts used for managing Contrail Windows compute nodes.

Hopefully, they should help in operations as well as development.

## Invoke-DiagnosticCheck.ps1

This script runs on localhost and performs a series of checks to verify that Windows compute node
is running correctly. It doesn't introduce any changes, so should be safe to run.

```
.\Invoke-DiagnosticCheck.ps1 -AdapterName "Ethernet0"
```

User must specify command line parameters depending on compute node configuration / deployment
method.

### Deployed via Contrail-Ansible-Deployer

You will need to specify `AdapterName` parameter to value of `WINDOWS_PHYSICAL_INTERFACE`.
Please refer to [official Contrail-Ansible-Deployer example](https://github.com/codilime/contrail-ansible-deployer/blob/master/config/instances.yaml.bms_win_example).

### Deployed in Windows Sanity tests

You will need to specify `AdapterName`, `VHostName` and `forwardingExtensionName` parameters to
their equivalent field under `system` section in `testenv-conf.yaml` file:

```
...
system:
  adapterName: Ethernet1
  vHostName: vEthernet (HNSTransparent)
  forwardingExtensionName: vRouter forwarding extension
...
```

