param([string[]]$SearchDirectory=@(),[switch]$OnlySearchDirectory)
. "$PSScriptRoot\ProxyDiscovery.ps1"
Find-GuardProxyConfig -SearchDirectory $SearchDirectory -OnlySearchDirectory:$OnlySearchDirectory
