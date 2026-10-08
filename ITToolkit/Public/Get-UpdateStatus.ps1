function Get-UpdateStatus {
    <#
    .SYNOPSIS
        Shows when the last update was installed and whether a computer is waiting for a restart.

    .DESCRIPTION
        Get-UpdateStatus reads installed updates from Win32_QuickFixEngineering and reports the most
        recent installation date, its KB number and the number of days since then.

        PendingReboot is $true when at least one of these registry indicators is set
        (PendingRebootReason lists which ones):
          ComponentBasedServicing      Component Based Servicing\RebootPending
          WindowsUpdate                WindowsUpdate\Auto Update\RebootRequired
          PendingFileRenameOperations  files waiting to be replaced at the next restart
          ComputerRename               the computer was renamed and not restarted yet

        The registry is read with the StdRegProv CIM class, so the Remote Registry service and
        PowerShell remoting are not required.

    .PARAMETER ComputerName
        The computers to query. Defaults to the local computer. Accepts pipeline input, including
        objects with a ComputerName, DNSHostName or Name property (for example from Get-ADComputer).

    .PARAMETER Credential
        Credentials for remote computers. Ignored for the local computer.

    .PARAMETER TimeoutSeconds
        Seconds to wait for a computer to respond before it is reported as unreachable. Defaults to 15.

    .EXAMPLE
        Get-UpdateStatus

        Shows the update and restart status of the local computer.

    .EXAMPLE
        Get-UpdateStatus -ComputerName SRV01, SRV02 | Where-Object PendingReboot

        Lists the servers that are waiting for a restart.

    .EXAMPLE
        Get-Content .\servers.txt | Get-UpdateStatus | Where-Object DaysSinceLastUpdate -GT 45 | Export-ITReport -Path .\outdated.csv

        Exports the computers that have not installed an update for more than 45 days.

    .INPUTS
        System.String

    .OUTPUTS
        ITToolkit.UpdateStatus

    .NOTES
        Win32_QuickFixEngineering lists updates installed by Component Based Servicing (cumulative
        and security updates). Definition updates and Microsoft Store app updates are not included.

    .LINK
        Export-ITReport
    #>
    [CmdletBinding()]
    [OutputType('ITToolkit.UpdateStatus')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('CN', 'DNSHostName', 'Name')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 15
    )

    process {
        foreach ($computer in $ComputerName) {
            $session = $null
            try {
                $session = Open-ITCimSession -ComputerName $computer -Credential $Credential -TimeoutSeconds $TimeoutSeconds
                $hotFixes = @(Get-CimInstance -CimSession $session -ClassName Win32_QuickFixEngineering -ErrorAction Stop)

                $installed = foreach ($hotFix in $hotFixes) {
                    $date = $hotFix.InstalledOn
                    if ($date -and $date -isnot [datetime]) {
                        $parsed = [datetime]::MinValue
                        if ([datetime]::TryParse([string]$date, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                            $date = $parsed
                        }
                        else {
                            $date = $null
                        }
                    }
                    if ($date) {
                        [pscustomobject]@{ HotFixId = $hotFix.HotFixID; InstalledOn = $date }
                    }
                }
                $latest = $installed | Sort-Object -Property InstalledOn -Descending | Select-Object -First 1

                $reasons = @(Get-ITPendingRebootReason -CimSession $session)

                $lastInstalled = $null
                $daysSince = $null
                if ($latest) {
                    $lastInstalled = $latest.InstalledOn
                    $daysSince = [int][math]::Floor(((Get-Date) - $lastInstalled).TotalDays)
                }

                [pscustomobject]@{
                    PSTypeName          = 'ITToolkit.UpdateStatus'
                    ComputerName        = Resolve-ITComputerName -ComputerName $computer
                    LastUpdateInstalled = $lastInstalled
                    LastHotFixId        = $latest.HotFixId
                    DaysSinceLastUpdate = $daysSince
                    HotFixCount         = $hotFixes.Count
                    PendingReboot       = ($reasons.Count -gt 0)
                    PendingRebootReason = [string[]]$reasons
                }
            }
            catch {
                Write-Error -Message "[$computer] Update status query failed: $($_.Exception.Message)" -Exception $_.Exception -Category ConnectionError -ErrorId 'UpdateStatusQueryFailed' -TargetObject $computer
            }
            finally {
                if ($session) {
                    Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
