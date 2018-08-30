. $PSScriptRoot\..\..\..\CIScripts\Common\Aliases.ps1

class MultiNode {
    [ContrailNetworkManager] $NM;
    [TestenvConfigs] $Configs;
    [PSSessionT[]] $Sessions;
    [String[]] $VRoutersUuids;
    # TODO: Storing information about installed components this way is not very good.
    #       Number of booleans might implode in the future. Needs to be refactored, when better
    #       time comes.
    [Bool] $InstalledNodeMgr

    MultiNode([ContrailNetworkManager] $NM,
              [TestenvConfigs] $Configs,
              [PSSessionT[]] $Sessions,
              [String[]] $VRoutersUuids,
              [bool] $InstalledNodeMgr) {
        $this.NM = $NM
        $this.Configs = $Configs
        $this.Sessions = $Sessions
        $this.VRoutersUuids = $VRoutersUuids
        $this.InstalledNodeMgr = $InstalledNodeMgr
    }
}
