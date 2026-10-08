function Open-ITCimSession {
    <#
    .SYNOPSIS
        Opens a CIM session to a computer, preferring WSMan and falling back to DCOM.

    .DESCRIPTION
        The local computer always gets a local (DCOM) session, so WinRM does not have to be enabled.
        For remote computers the WSMan (5985) and DCOM/RPC (135) ports are probed first, which bounds
        the wait for an unreachable computer to TimeoutSeconds. The same value is used as the
        operation timeout of the session.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimSession])]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 15
    )

    $wsmanPort = 5985
    $rpcPort = 135

    if (Test-ITLocalComputer -ComputerName $ComputerName) {
        if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
            Write-Verbose -Message "[$ComputerName] Credentials are ignored for the local computer."
        }
        return New-CimSession -OperationTimeoutSec $TimeoutSeconds -ErrorAction Stop
    }

    $openPorts = @(Test-ITTcpPort -ComputerName $ComputerName -Port $wsmanPort, $rpcPort -TimeoutSeconds $TimeoutSeconds)
    if ($openPorts.Count -eq 0) {
        throw "Computer '$ComputerName' did not respond on WSMan ($wsmanPort) or DCOM ($rpcPort) within $TimeoutSeconds second(s)."
    }

    $sessionParams = @{
        ComputerName        = $ComputerName
        OperationTimeoutSec = $TimeoutSeconds
        ErrorAction         = 'Stop'
    }
    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
        $sessionParams.Credential = $Credential
    }

    if ($openPorts -contains $wsmanPort) {
        try {
            return New-CimSession @sessionParams
        }
        catch {
            if ($openPorts -notcontains $rpcPort) {
                throw
            }
            Write-Verbose -Message "[$ComputerName] WSMan session failed ($($_.Exception.Message)); falling back to DCOM."
        }
    }

    $sessionParams.SessionOption = New-CimSessionOption -Protocol Dcom
    return New-CimSession @sessionParams
}
