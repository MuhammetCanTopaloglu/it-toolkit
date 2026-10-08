function Get-PasswordExpiryReport {
    <#
    .SYNOPSIS
        Lists Active Directory users whose password expires within a number of days or must be changed at next logon.

    .DESCRIPTION
        Get-PasswordExpiryReport reads the constructed attribute msDS-UserPasswordExpiryTimeComputed,
        which already applies the default domain policy and fine-grained password policies (PSOs).

        Special values are handled separately:
          0                    the user must change the password at next logon. These users are always
                               reported, with Status = MustChangePassword.
          9223372036854775807  (maximum Int64) the password never expires. These users are not reported.

        Other users are reported with Status = Expiring when the password expires within -Days days,
        and with Status = Expired (only with -IncludeExpired) when it has already expired.
        Disabled accounts and accounts with "Password never expires" are not queried.

        Requires the ActiveDirectory module (RSAT). If it is missing, a terminating error explains how
        to install it.

    .PARAMETER Days
        Report passwords that expire within this many days. Defaults to 14.

    .PARAMETER SearchBase
        Distinguished names of the OUs or containers to search. Defaults to the whole domain.
        Accepts pipeline input, for example from Get-ADOrganizationalUnit.

    .PARAMETER IncludeExpired
        Also report users whose password has already expired.

    .PARAMETER Server
        The domain controller or domain to query. Defaults to the domain of the current session.

    .PARAMETER Credential
        Credentials for the Active Directory query.

    .EXAMPLE
        Get-PasswordExpiryReport

        Lists users whose password expires within 14 days or who must change it at next logon.

    .EXAMPLE
        Get-PasswordExpiryReport -Days 7 | Where-Object Status -EQ 'Expiring' | Select-Object SamAccountName, EmailAddress, PasswordExpires

        Lists the users to remind this week, with their e-mail addresses.

    .EXAMPLE
        Get-PasswordExpiryReport -Days 30 -IncludeExpired -SearchBase 'OU=Staff,DC=contoso,DC=com' | Export-ITReport -Path .\password-expiry.html

        Creates an HTML report for one OU, including expired passwords.

    .INPUTS
        System.String

    .OUTPUTS
        ITToolkit.PasswordExpiry

    .LINK
        Export-ITReport
    #>
    [CmdletBinding()]
    [OutputType('ITToolkit.PasswordExpiry')]
    param(
        [ValidateRange(0, 36500)]
        [int]$Days = 14,

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('DistinguishedName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$SearchBase,

        [switch]$IncludeExpired,

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

        $expiryAttribute = 'msDS-UserPasswordExpiryTimeComputed'
        $mustChangeValue = [int64]0
        $neverExpiresValue = [int64]::MaxValue

        $now = Get-Date
        $limit = $now.AddDays($Days)

        # Enabled accounts without "Password never expires" (ADS_UF_DONT_EXPIRE_PASSWD = 65536).
        $queryParams = @{
            LDAPFilter  = '(&(!(userAccountControl:1.2.840.113556.1.4.803:=2))(!(userAccountControl:1.2.840.113556.1.4.803:=65536)))'
            Properties  = @($expiryAttribute, 'PasswordLastSet', 'EmailAddress', 'DisplayName')
            ErrorAction = 'Stop'
        }
        if ($Server) {
            $queryParams.Server = $Server
        }
        if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
            $queryParams.Credential = $Credential
        }

        $skippedNeverExpires = 0
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

            try {
                foreach ($user in (Get-ADUser @params)) {
                    $raw = $user.$expiryAttribute
                    if ($null -eq $raw) {
                        Write-Verbose -Message "Skipping $($user.SamAccountName): $expiryAttribute is not available."
                        continue
                    }
                    $raw = [int64]$raw

                    $expires = $null
                    $daysUntil = $null

                    if ($raw -eq $neverExpiresValue) {
                        $skippedNeverExpires++
                        continue
                    }
                    elseif ($raw -eq $mustChangeValue) {
                        $status = 'MustChangePassword'
                    }
                    else {
                        try {
                            $expires = [datetime]::FromFileTime($raw)
                        }
                        catch {
                            # Values beyond DateTime.MaxValue also mean "does not expire".
                            $skippedNeverExpires++
                            continue
                        }
                        $daysUntil = [int][math]::Floor(($expires - $now).TotalDays)

                        if ($expires -le $now) {
                            if (-not $IncludeExpired) {
                                continue
                            }
                            $status = 'Expired'
                        }
                        elseif ($expires -le $limit) {
                            $status = 'Expiring'
                        }
                        else {
                            continue
                        }
                    }

                    [pscustomobject]@{
                        PSTypeName        = 'ITToolkit.PasswordExpiry'
                        Name              = $user.Name
                        DisplayName       = $user.DisplayName
                        SamAccountName    = $user.SamAccountName
                        EmailAddress      = $user.EmailAddress
                        PasswordLastSet   = $user.PasswordLastSet
                        PasswordExpires   = $expires
                        DaysUntilExpiry   = $daysUntil
                        Status            = $status
                        DistinguishedName = $user.DistinguishedName
                    }
                }
            }
            catch {
                $target = $base
                if (-not $target) {
                    $target = 'domain'
                }
                Write-Error -Message "[$target] Password expiry query failed: $($_.Exception.Message)" -Exception $_.Exception -Category ReadError -ErrorId 'PasswordExpiryQueryFailed' -TargetObject $target
            }
        }
    }

    end {
        if ($skippedNeverExpires -gt 0) {
            Write-Verbose -Message "$skippedNeverExpires user(s) have passwords that do not expire and were not reported."
        }
    }
}
