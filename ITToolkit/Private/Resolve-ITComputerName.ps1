function Resolve-ITComputerName {
    <#
    .SYNOPSIS
        Returns the name to show in reports: the real host name for local aliases, otherwise the input.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    if (Test-ITLocalComputer -ComputerName $ComputerName) {
        return $env:COMPUTERNAME
    }

    return $ComputerName
}
