. $PSScriptRoot\Backup-Infrastructure.ps1
. $PSScriptRoot\Remove-LastBackups.ps1

Add-PSSnapin VeeamPSSnapin

$Repository = "\\10.84.10.100\vol\winci_backup\Backups"
$PreserveCount = 5

$VirtualMachines = @(
    [VMSpec]@{Name="ci-vc"},
    [VMSpec]@{Name="ci-vc-um"},
    [VMSpec]@{Name="mgmt-dhcp"},
    [VMSpec]@{Name="winci-choco"},
    [VMSpec]@{Name="winci-drive"},
    [VMSpec]@{Name="winci-jenkins_restored-20180903-0139"},
    [VMSpec]@{Name="winci-mgmt"},
    [VMSpec]@{Name="winci-purgatory-1"},
    [VMSpec]@{Name="winci-purgatory-2"},
    [VMSpec]@{Name="winci-registry"},
    [VMSpec]@{Name="winci-zuulv2-production"},
    [VMSpec]@{Name="winci-vyos-mgmt"; SupportsQuiesce = $false}
)

Remove-LastBackups -Repository $Repository -PreserveCount $PreserveCount
Backup-Infrastructure -VirtualMachines $VirtualMachines -Repository $Repository
