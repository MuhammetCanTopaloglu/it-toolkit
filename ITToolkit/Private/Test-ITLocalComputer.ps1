function Test-ITLocalComputer {
    <#
    .SYNOPSIS
        Returns $true when the given name refers to the local computer.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    $localNames = @('.', 'localhost', '127.0.0.1', '::1', $env:COMPUTERNAME, [System.Net.Dns]::GetHostName())
    if ($env:USERDNSDOMAIN) {
        $localNames += "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
    }

    return ($localNames -contains $ComputerName)
}
