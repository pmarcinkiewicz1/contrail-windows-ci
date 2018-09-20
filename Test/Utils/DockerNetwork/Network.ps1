class Network {
    [string] $Name;
    [SubnetConfiguration] $Subnet;

    Network([string] $Name, [SubnetConfiguration] $Subnet) {
        $this.Name = $Name
        $this.Subnet = $Subnet
    }
}
