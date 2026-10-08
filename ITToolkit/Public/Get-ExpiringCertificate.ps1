function Get-ExpiringCertificate {
    <#
    .SYNOPSIS
        Finds certificates in the LocalMachine certificate stores that expire within a number of days.

    .DESCRIPTION
        Get-ExpiringCertificate reads the LocalMachine certificate stores (Personal/My by default) and
        returns the certificates whose expiry date (NotAfter) falls within the next -Days days.
        Certificates that have already expired are only returned with -IncludeExpired.

        Certificate stores cannot be read through CIM. The local computer is read directly; remote
        computers are read with Invoke-Command, so PowerShell remoting (WinRM, TCP 5985) must be enabled
        on them. The WinRM port is probed first, so an unreachable computer fails after -TimeoutSeconds.

    .PARAMETER ComputerName
        The computers to query. Defaults to the local computer. Accepts pipeline input, including
        objects with a ComputerName, DNSHostName or Name property (for example from Get-ADComputer).

    .PARAMETER Days
        Report certificates that expire within this many days. Defaults to 30.

    .PARAMETER StoreName
        LocalMachine stores to read, for example My, WebHosting, Root, CA or 'Remote Desktop'.
        Defaults to My (Personal).

    .PARAMETER IncludeExpired
        Also return certificates that have already expired.

    .PARAMETER Credential
        Credentials for remote computers. Ignored for the local computer.

    .PARAMETER TimeoutSeconds
        Seconds to wait for a computer to respond before it is reported as unreachable. Defaults to 15.

    .EXAMPLE
        Get-ExpiringCertificate

        Lists certificates in LocalMachine\My on this computer that expire within 30 days.

    .EXAMPLE
        Get-ExpiringCertificate -ComputerName WEB01, WEB02 -Days 60 -StoreName My, WebHosting

        Checks the Personal and Web Hosting stores of two web servers for the next 60 days.

    .EXAMPLE
        Get-ADComputer -Filter 'OperatingSystem -like "*Server*"' | Get-ExpiringCertificate -Days 45 -IncludeExpired | Export-ITReport -Path .\certificates.html -HighlightProperty IsExpired

        Creates an HTML report of expiring and expired certificates on all servers.

    .INPUTS
        System.String

    .OUTPUTS
        ITToolkit.ExpiringCertificate

    .LINK
        Export-ITReport
    #>
    [CmdletBinding()]
    [OutputType('ITToolkit.ExpiringCertificate')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('CN', 'DNSHostName', 'Name')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [ValidateRange(0, 36500)]
        [int]$Days = 30,

        [ValidateNotNullOrEmpty()]
        [string[]]$StoreName = 'My',

        [switch]$IncludeExpired,

        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 15
    )

    begin {
        $winRmPort = 5985
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                if (Test-ITLocalComputer -ComputerName $computer) {
                    $certificates = @(Get-ITCertificateStoreItem -StoreName $StoreName)
                }
                else {
                    $openPorts = @(Test-ITTcpPort -ComputerName $computer -Port $winRmPort -TimeoutSeconds $TimeoutSeconds)
                    if ($openPorts.Count -eq 0) {
                        throw "Computer '$computer' did not respond on WinRM ($winRmPort) within $TimeoutSeconds second(s)."
                    }

                    $invokeParams = @{
                        ComputerName  = $computer
                        ScriptBlock   = ${function:Get-ITCertificateStoreItem}
                        ArgumentList  = (, $StoreName)
                        SessionOption = New-PSSessionOption -OpenTimeout ($TimeoutSeconds * 1000)
                        ErrorAction   = 'Stop'
                    }
                    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
                        $invokeParams.Credential = $Credential
                    }
                    $certificates = @(Invoke-Command @invokeParams)
                }

                $now = Get-Date
                $limit = $now.AddDays($Days)
                $displayName = Resolve-ITComputerName -ComputerName $computer

                foreach ($certificate in ($certificates | Sort-Object -Property NotAfter)) {
                    $notAfter = [datetime]$certificate.NotAfter
                    $isExpired = $notAfter -lt $now
                    if ($isExpired -and -not $IncludeExpired) {
                        continue
                    }
                    if ($notAfter -gt $limit) {
                        continue
                    }

                    [pscustomobject]@{
                        PSTypeName    = 'ITToolkit.ExpiringCertificate'
                        ComputerName  = $displayName
                        Store         = $certificate.Store
                        Subject       = $certificate.Subject
                        FriendlyName  = $certificate.FriendlyName
                        Issuer        = $certificate.Issuer
                        Thumbprint    = $certificate.Thumbprint
                        NotBefore     = [datetime]$certificate.NotBefore
                        NotAfter      = $notAfter
                        DaysRemaining = [int][math]::Floor(($notAfter - $now).TotalDays)
                        IsExpired     = $isExpired
                        HasPrivateKey = [bool]$certificate.HasPrivateKey
                    }
                }
            }
            catch {
                Write-Error -Message "[$computer] Certificate query failed: $($_.Exception.Message)" -Exception $_.Exception -Category ConnectionError -ErrorId 'CertificateQueryFailed' -TargetObject $computer
            }
        }
    }
}
