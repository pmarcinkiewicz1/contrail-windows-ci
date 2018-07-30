. $PSScriptRoot\Backup-Infrastructure.ps1

# NOTE: Functions below are propertly defined only when Veeam snapin is loaded.
#       For tests, these dummy definitions are sufficient to enable mocking.
function Connect-VBRServer {}
function Find-VBRViEntity { Param($Name) return $Name }
function Start-VBRZip {
    Param(
        [string]$Folder,
        [string]$Entity,
        [string]$Compression,
        [switch]$DisableQuiesce)

    $path = Join-Path $Folder $Entity
    $path = $path + ".vbk"
    New-Item $path -ItemType File
}
function Disconnect-VBRServer {}

Describe 'Backup-Infrastructure' -Tags CI, Unit {
    BeforeEach {
        $backupRepository = "TestDrive:\Backups\"
        New-Item -ItemType Directory -Path $backupRepository

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "vmSpecList",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $vmSpecList = @(
            [VMSpec]@{Name = "vm1"},
            [VMSpec]@{Name = "vm2"}
        )
    }

    AfterEach {
        Get-ChildItem TestDrive:\ | Remove-Item -Force -Recurse
    }

    It 'creates backup directory in repository with virtual machines backups' {
        Backup-Infrastructure -VirtualMachines $vmSpecList -Repository $backupRepository

        $dir = Get-ChildItem $backupRepository -Directory
        $dir | Should -HaveCount 1

        $backupFiles = Get-ChildItem $dir.FullName -File -Filter "*.vbk"
        $backupFiles | Should -HaveCount $vmSpecList.Count
        ($backupFiles | Where-Object Name -Match "vm1").FullName | Should -Exist
        ($backupFiles | Where-Object Name -Match "vm2").FullName | Should -Exist
    }

    Context 'backup naming' {
        Mock Get-Date { return [datetime]::Parse("2018-01-01T01:02:03Z") }

        It 'creates backup directory named with UTC date' {

            Backup-Infrastructure -VirtualMachines $vmSpecList -Repository $backupRepository

            $dir = Get-ChildItem $backupRepository -Directory
            $dir.Name | Should -Be "20180101-010203"
        }

        It 'uses existing directory if it exists' {
            $backupPath = Join-Path $backupRepository "20180101-010203"

            New-Item -ItemType Directory -Path $backupPath
            Backup-Infrastructure -VirtualMachines $vmSpecList -Repository $backupRepository

            $dir = Get-ChildItem $backupRepository -Directory
            $dir | Should -HaveCount 1

            $backupFiles = Get-ChildItem $backupPath -File -Filter "*.vbk"
            $backupFiles | Should -HaveCount $vmSpecList.Count
        }
    }

    Context 'connecting to Veeam server' {
        Mock Connect-VBRServer {}
        Mock Disconnect-VBRServer {}

        It 'properly connects and disconnects from localhost Veeam Backup Server' {
            Backup-Infrastructure -VirtualMachines $vmSpecList -Repository $backupRepository

            Assert-MockCalled -Scope It Connect-VBRServer -Times 1 -Exactly
            Assert-MockCalled -Scope It Disconnect-VBRServer -Times 1 -Exactly
        }

        It 'should disconnect if one of the vms cannot be found' {
            Mock Find-VBRViEntity { return $null } -ParameterFilter { $Name -eq "vm1" }

            {
                Backup-Infrastructure -VirtualMachines $vmSpecList -Repository $backupRepository
            } | Should -Throw "Backup failed for vms: vm1"

            Assert-MockCalled -Scope It Connect-VBRServer -Times 1 -Exactly
            Assert-MockCalled -Scope It Disconnect-VBRServer -Times 1 -Exactly
        }
    }

    Context 'using VeeamZIP' {
        It 'uses VeeamZip to backup the virtual machines' {
            Mock Start-VBRZip {}

            Backup-Infrastructure -VirtualMachines $vmSpecList -Repository $backupRepository

            Assert-MockCalled -Scope It Start-VBRZip -Times 2 -Exactly
        }
    }

    Context 'respects quiescence support' {
        It 'disables quiescence for virtual machines which do not support it' {
            Mock Start-VBRZip { }

            $vmSpecList = @(
                [VMSpec]@{
                    Name = "vm1"
                    SupportsQuiesce = $true},
                [VMSpec]@{
                    Name = "vm2"
                    SupportsQuiesce = $false
                }
            )

            Backup-Infrastructure -VirtualMachines $vmSpecList -Repository $backupRepository

            Assert-MockCalled  Start-VBRZip `
                -Scope It `
                -ParameterFilter { $Entity -eq "vm1" -and -not $DisableQuiesce } `
                -Times 1 -Exactly
            Assert-MockCalled  Start-VBRZip `
                -Scope It `
                -ParameterFilter { $Entity -eq "vm2" -and $DisableQuiesce } `
                -Times 1 -Exactly
        }
    }

    Context 'resilience to missing VMs' {
        It 'should create backups for other VMs if the second VM cannot be found' {
            $vmSpecList = @(
                [VMSpec]@{Name = "vm1"},
                [VMSpec]@{Name = "vm2"},
                [VMSpec]@{Name = "vm3"}
            )

            Mock Find-VBRViEntity { return $null } -ParameterFilter { $Name -eq "vm2" }

            {
                Backup-Infrastructure -VirtualMachines $vmSpecList -Repository $backupRepository
            } | Should -Throw "Backup failed for vms: vm2"

            $dir = Get-ChildItem $backupRepository -Directory
            $dir | Should -HaveCount 1

            $backupFiles = Get-ChildItem $dir.FullName -File -Filter "*.vbk"
            $backupFiles | Should -HaveCount 2
            ($backupFiles | Where-Object Name -Match "vm1").FullName | Should -Exist
            ($backupFiles | Where-Object Name -Match "vm2") | Should -Be $null
            ($backupFiles | Where-Object Name -Match "vm3").FullName | Should -Exist
        }
    }

    Context 'resilience to Veeam errors' {
        It 'should create backups for other VMs if backing up vm1 has failed' {
            Mock Start-VBRZip { throw "Very bad Veeam error" } -ParameterFilter { $Entity -eq "vm1" }

            {
                Backup-Infrastructure -VirtualMachines $vmSpecList -Repository $backupRepository
            } | Should -Throw "Backup failed for vms: vm1"

            $dir = Get-ChildItem $backupRepository -Directory
            $dir | Should -HaveCount 1

            $backupFiles = Get-ChildItem $dir.FullName -File -Filter "*.vbk"
            $backupFiles | Should -HaveCount 1
            ($backupFiles | Where-Object Name -Match "vm1") | Should -Be $null
            ($backupFiles | Where-Object Name -Match "vm2").FullName | Should -Exist
        }
    }
}
