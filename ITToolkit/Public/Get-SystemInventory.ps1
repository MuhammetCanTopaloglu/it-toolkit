function Get-SystemInventory {
    <#
    .SYNOPSIS
        Collects hardware and operating system details: model, serial number, OS, CPU, memory and uptime.

    .DESCRIPTION
        Get-SystemInventory combines Win32_ComputerSystem, Win32_BIOS, Win32_OperatingSystem and
        Win32_Processor into one object per computer.

        Uptime is calculated from the computer's own clock (LocalDateTime - LastBootUpTime), so clock
        differences between the computers do not distort it.

    .PARAMETER ComputerName
        The computers to query. Defaults to the local computer. Accepts pipeline input, including
        objects with a ComputerName, DNSHostName or Name property (for example from Get-ADComputer).

    .PARAMETER Credential
        Credentials for remote computers. Ignored for the local computer.

    .PARAMETER TimeoutSeconds
        Seconds to wait for a computer to respond before it is reported as unreachable. Defaults to 15.

    .EXAMPLE
        Get-SystemInventory

        Shows the inventory of the local computer.

    .EXAMPLE
        Get-SystemInventory -ComputerName SRV01, SRV02 | Select-Object ComputerName, Model, SerialNumber, TotalMemoryGB, UptimeDays

        Shows a compact hardware overview of two servers.

    .EXAMPLE
        Get-ADComputer -Filter * -SearchBase 'OU=Workstations,DC=contoso,DC=com' | Get-SystemInventory -TimeoutSeconds 5 | Export-ITReport -Path .\inventory.csv

        Exports the inventory of every workstation in an OU and skips offline computers after 5 seconds.

    .INPUTS
        System.String

    .OUTPUTS
        ITToolkit.SystemInventory

    .LINK
        Export-ITReport
    #>
    [CmdletBinding()]
    [OutputType('ITToolkit.SystemInventory')]
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
                $query = @{ CimSession = $session; ErrorAction = 'Stop' }

                $system = Get-CimInstance @query -ClassName Win32_ComputerSystem | Select-Object -First 1
                $bios = Get-CimInstance @query -ClassName Win32_BIOS | Select-Object -First 1
                $os = Get-CimInstance @query -ClassName Win32_OperatingSystem | Select-Object -First 1
                $processors = @(Get-CimInstance @query -ClassName Win32_Processor)

                $uptime = $null
                if ($os.LastBootUpTime -and $os.LocalDateTime) {
                    $uptime = $os.LocalDateTime - $os.LastBootUpTime
                }
                $uptimeDays = $null
                if ($uptime) {
                    $uptimeDays = [math]::Round($uptime.TotalDays, 1)
                }

                $cores = 0
                $logical = 0
                foreach ($processor in $processors) {
                    $cores += [int]$processor.NumberOfCores
                    $logical += [int]$processor.NumberOfLogicalProcessors
                }

                [pscustomobject]@{
                    PSTypeName            = 'ITToolkit.SystemInventory'
                    ComputerName          = Resolve-ITComputerName -ComputerName $computer
                    Manufacturer          = $system.Manufacturer
                    Model                 = $system.Model
                    SerialNumber          = "$($bios.SerialNumber)".Trim()
                    BiosVersion           = $bios.SMBIOSBIOSVersion
                    Domain                = $system.Domain
                    OperatingSystem       = $os.Caption
                    OSVersion             = $os.Version
                    OSBuild               = $os.BuildNumber
                    OSArchitecture        = $os.OSArchitecture
                    Processor             = (@($processors | ForEach-Object { "$($_.Name)".Trim() }) | Select-Object -Unique) -join '; '
                    ProcessorCount        = $processors.Count
                    CoreCount             = $cores
                    LogicalProcessorCount = $logical
                    TotalMemoryGB         = [math]::Round([double]$system.TotalPhysicalMemory / 1GB, 2)
                    InstallDate           = $os.InstallDate
                    LastBootTime          = $os.LastBootUpTime
                    Uptime                = $uptime
                    UptimeDays            = $uptimeDays
                }
            }
            catch {
                Write-Error -Message "[$computer] Inventory query failed: $($_.Exception.Message)" -Exception $_.Exception -Category ConnectionError -ErrorId 'InventoryQueryFailed' -TargetObject $computer
            }
            finally {
                if ($session) {
                    Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
