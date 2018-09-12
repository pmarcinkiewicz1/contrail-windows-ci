. $PSScriptRoot/../CIScripts/Common/Init.ps1

function Remove-LastBackups {
    Param(
        [Parameter(Mandatory = $true)] [string] $Repository,
        [Parameter(Mandatory = $true)] [int32] $PreserveCount
    )

    $Backups = Get-ChildItem $Repository -Directory
    $ToPreserve = $Backups `
        | Sort-Object -Property CreationTime -Descending `
        | Select-Object -First $PreserveCount
    $ToDelete = $Backups `
        | Where-Object { $ToPreserve -NotContains $_ }

    foreach ($b in $ToDelete) {
        Remove-Item $b.FullName -Recurse
    }
}
