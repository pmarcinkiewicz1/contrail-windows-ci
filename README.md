# contrail-windows-ci

Zuulv2 based CI system for testing Contrail on Windows platform.

Currently, the repo contains:
* infrastructure as code (mostly Ansible),
* backup scripts,
* CI job definitions and related scripts (Jenksinfiles, Groovy, PowerShell, Python),
* Dev/demo environment setup jobs (Jenkinsfiles)
* Windows Contrail system and integration tests, as well as unit test runners and static analysis tools (Note: they will probably be moved to a different repository in the future).

Useful links:

* [FAQ](https://github.com/Juniper/contrail-windows-ci/wiki/OpenContrail-Windows-CI-FAQ)
* [Windows CI documentation](https://juniper.github.io/contrail-windows-docs/For%20CI%20admins/Infra/Windows_CI_infrastructure/)
* [Windows Contrail documentation](https://juniper.github.io/contrail-windows-docs/)

## Windows CI - selfcheck tests

Windows CI has a set of unit and integration selfcheck tests. To learn how to run them [please read this document](SELFCHECK.md).

## Windows Contrail system & unit tests

Windows Contrail tests are located in Test/ directory. This directory will be extracted to a different repo in the future.
To learn how to run them manually [please read this document](./Test/README.md).

## Relation to Linux CI

Windows CI is a separate system from Linux CI, due to many reasons.
There are ongoing efforts to merge them together via Zuulv3.

If you are looking for Linux CI code then please check the following repositories:

* https://github.com/Juniper/contrail-project-config
* https://github.com/Juniper/contrail-infra-doc
* https://github.com/Juniper/contrail-infra
