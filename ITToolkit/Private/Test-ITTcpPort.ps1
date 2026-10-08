function Test-ITTcpPort {
    <#
    .SYNOPSIS
        Probes TCP ports in parallel and returns the ports that accepted a connection within the timeout.

    .DESCRIPTION
        Used before opening CIM sessions so that an unreachable computer fails after TimeoutSeconds
        instead of waiting for the much longer WSMan/DCOM transport timeouts.
        The first port in -Port is treated as preferred: as soon as it connects, the probe returns.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [int[]]$Port,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 15
    )

    $probes = foreach ($portNumber in $Port) {
        $client = New-Object -TypeName System.Net.Sockets.TcpClient
        $task = $null
        try {
            $task = $client.ConnectAsync($ComputerName, $portNumber)
        }
        catch {
            Write-Verbose -Message "[$ComputerName] TCP $portNumber connect failed: $($_.Exception.Message)"
        }
        [pscustomobject]@{ Port = $portNumber; Client = $client; Task = $task }
    }
    $probes = @($probes)

    try {
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            $preferred = $probes[0].Task
            if ($preferred -and $preferred.Status -eq 'RanToCompletion') {
                break
            }
            $running = @($probes | Where-Object { $_.Task -and -not $_.Task.IsCompleted })
            if ($running.Count -eq 0) {
                break
            }
            Start-Sleep -Milliseconds 50
        }

        foreach ($probe in $probes) {
            if ($probe.Task -and $probe.Task.Status -eq 'RanToCompletion') {
                $probe.Port
            }
        }
    }
    finally {
        foreach ($probe in $probes) {
            $probe.Client.Close()
        }
    }
}
