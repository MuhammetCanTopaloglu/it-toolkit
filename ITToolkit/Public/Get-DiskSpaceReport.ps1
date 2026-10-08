function Get-DiskSpaceReport {
    <#
    .SYNOPSIS
        Reports size, free space and usage of local fixed disks and flags disks below a free space threshold.

    .DESCRIPTION
        Get-DiskSpaceReport queries Win32_LogicalDisk (fixed disks only, DriveType 3) over CIM and
        returns one object per volume. BelowThreshold is $true when the free space percentage is lower
        than -ThresholdPercent.

        The local computer is queried without WinRM. Remote computers are queried over WSMan, with an
        automatic fallback to DCOM. A computer that cannot be reached produces a non-terminating error
        after -TimeoutSeconds and the remaining computers are still processed.

    .PARAMETER ComputerName
        The computers to query. Defaults to the local computer. Accepts pipeline input, including
        objects with a ComputerName, DNSHostName or Name property (for example from Get-ADComputer).

    .PARAMETER ThresholdPercent
        Free space percentage below which a disk is flagged. Defaults to 15.

    .PARAMETER Credential
        Credentials for remote computers. Ignored for the local computer.

    .PARAMETER TimeoutSeconds
        Seconds to wait for a computer to respond before it is reported as unreachable. Defaults to 15.

    .EXAMPLE
        Get-DiskSpaceReport

        Reports the fixed disks of the local computer.

    .EXAMPLE
        Get-DiskSpaceReport -ComputerName SRV01, SRV02 -ThresholdPercent 10 | Where-Object BelowThreshold

        Lists only the disks with less than 10 percent free space.

    .EXAMPLE
        Get-ADComputer -Filter 'OperatingSystem -like "*Server*"' | Get-DiskSpaceReport | Export-ITReport -Path .\disks.html -HighlightProperty BelowThreshold

        Checks every server in Active Directory and writes an HTML report with the low disks highlighted.

    .INPUTS
        System.String

    .OUTPUTS
        ITToolkit.DiskSpace

    .LINK
        Export-ITReport
    #>
    [CmdletBinding()]
    [OutputType('ITToolkit.DiskSpace')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('CN', 'DNSHostName', 'Name')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [ValidateRange(0, 100)]
        [double]$ThresholdPercent = 15,

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
                $disks = Get-CimInstance -CimSession $session -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop
                $displayName = Resolve-ITComputerName -ComputerName $computer

                foreach ($disk in $disks) {
                    $size = [double]$disk.Size
                    if ($size -le 0) {
                        Write-Verbose -Message "[$displayName] Skipping $($disk.DeviceID): size is not available."
                        continue
                    }
                    $free = [double]$disk.FreeSpace
                    $freePercent = [math]::Round($free / $size * 100, 2)

                    [pscustomobject]@{
                        PSTypeName       = 'ITToolkit.DiskSpace'
                        ComputerName     = $displayName
                        Drive            = $disk.DeviceID
                        VolumeName       = $disk.VolumeName
                        FileSystem       = $disk.FileSystem
                        SizeGB           = [math]::Round($size / 1GB, 2)
                        FreeGB           = [math]::Round($free / 1GB, 2)
                        UsedPercent      = [math]::Round(100 - $freePercent, 2)
                        FreePercent      = $freePercent
                        ThresholdPercent = $ThresholdPercent
                        BelowThreshold   = ($freePercent -lt $ThresholdPercent)
                    }
                }
            }
            catch {
                Write-Error -Message "[$computer] Disk query failed: $($_.Exception.Message)" -Exception $_.Exception -Category ConnectionError -ErrorId 'DiskQueryFailed' -TargetObject $computer
            }
            finally {
                if ($session) {
                    Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
