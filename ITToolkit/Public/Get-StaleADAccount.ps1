function Get-StaleADAccount {
    <#
    .SYNOPSIS
        Finds Active Directory user and computer accounts that have not logged on for a number of days.

    .DESCRIPTION
        Get-StaleADAccount searches Active Directory for accounts whose last logon is older than -Days
        days. Accounts that have never logged on are included when they were created before that date,
        so freshly created accounts are not reported. Disabled accounts are skipped unless
        -IncludeDisabled is used.

        The last logon comes from the lastLogonTimestamp attribute (shown as LastLogonDate). It is
        replicated to every domain controller, so one query is enough, but it is only updated when the
        previous value is older than 9-14 days. Use thresholds well above 14 days.

        Requires the ActiveDirectory module (RSAT). If it is missing, a terminating error explains how
        to install it.

    .PARAMETER Days
        Report accounts that have not logged on for this many days. Defaults to 90.

    .PARAMETER AccountType
        User, Computer or All. Defaults to All.

    .PARAMETER SearchBase
        Distinguished names of the OUs or containers to search. Defaults to the whole domain.
        Accepts pipeline input, for example from Get-ADOrganizationalUnit.

    .PARAMETER IncludeDisabled
        Also report accounts that are already disabled.

    .PARAMETER Server
        The domain controller or domain to query. Defaults to the domain of the current session.

    .PARAMETER Credential
        Credentials for the Active Directory query.

    .EXAMPLE
        Get-StaleADAccount

        Lists enabled users and computers that have not logged on for 90 days.

    .EXAMPLE
        Get-StaleADAccount -Days 180 -AccountType Computer -SearchBase 'OU=Workstations,DC=contoso,DC=com'

        Lists workstations in one OU that have not logged on for 180 days.

    .EXAMPLE
        Get-ADOrganizationalUnit -Filter 'Name -like "Branch*"' | Get-StaleADAccount -AccountType User | Export-ITReport -Path .\stale-users.csv

        Checks every branch OU and exports the stale user accounts.

    .INPUTS
        System.String

    .OUTPUTS
        ITToolkit.StaleADAccount

    .LINK
        Disable-DepartingUser
    #>
    [CmdletBinding()]
    [OutputType('ITToolkit.StaleADAccount')]
    param(
        [ValidateRange(1, 36500)]
        [int]$Days = 90,

        [ValidateSet('User', 'Computer', 'All')]
        [string]$AccountType = 'All',

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('DistinguishedName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$SearchBase,

        [switch]$IncludeDisabled,

        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        try {
            Assert-ITADModule
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        $now = Get-Date
        $cutoff = $now.AddDays(-$Days)

        $staleFilter = "(|(lastLogonTimestamp<=$($cutoff.ToFileTimeUtc()))(!(lastLogonTimestamp=*)))"
        if ($IncludeDisabled) {
            $ldapFilter = $staleFilter
        }
        else {
            $ldapFilter = "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2))$staleFilter)"
        }

        $queryParams = @{
            LDAPFilter  = $ldapFilter
            Properties  = @('LastLogonDate', 'WhenCreated')
            ErrorAction = 'Stop'
        }
        if ($Server) {
            $queryParams.Server = $Server
        }
        if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
            $queryParams.Credential = $Credential
        }

        $types = @('User', 'Computer')
        if ($AccountType -ne 'All') {
            $types = @($AccountType)
        }
    }

    process {
        $bases = @($null)
        if ($SearchBase) {
            $bases = $SearchBase
        }

        foreach ($base in $bases) {
            $params = $queryParams.Clone()
            if ($base) {
                $params.SearchBase = $base
            }

            foreach ($type in $types) {
                try {
                    if ($type -eq 'User') {
                        $accounts = Get-ADUser @params
                    }
                    else {
                        $accounts = Get-ADComputer @params
                    }

                    foreach ($account in $accounts) {
                        if (-not $IncludeDisabled -and $account.Enabled -eq $false) {
                            continue
                        }

                        $lastLogon = $account.LastLogonDate
                        if ($lastLogon) {
                            if ($lastLogon -gt $cutoff) {
                                continue
                            }
                        }
                        elseif ($account.WhenCreated -and $account.WhenCreated -gt $cutoff) {
                            continue
                        }

                        $daysSince = $null
                        if ($lastLogon) {
                            $daysSince = [int][math]::Floor(($now - $lastLogon).TotalDays)
                        }

                        [pscustomobject]@{
                            PSTypeName         = 'ITToolkit.StaleADAccount'
                            Name               = $account.Name
                            SamAccountName     = $account.SamAccountName
                            ObjectClass        = $account.ObjectClass
                            Enabled            = $account.Enabled
                            LastLogonDate      = $lastLogon
                            DaysSinceLastLogon = $daysSince
                            NeverLoggedOn      = (-not $lastLogon)
                            WhenCreated        = $account.WhenCreated
                            DistinguishedName  = $account.DistinguishedName
                        }
                    }
                }
                catch {
                    $target = $base
                    if (-not $target) {
                        $target = 'domain'
                    }
                    Write-Error -Message "[$target] $type query failed: $($_.Exception.Message)" -Exception $_.Exception -Category ReadError -ErrorId 'StaleAccountQueryFailed' -TargetObject $target
                }
            }
        }
    }
}
