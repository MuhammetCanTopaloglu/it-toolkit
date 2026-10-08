function Get-LocalAdminAudit {
    <#
    .SYNOPSIS
        Lists the members of the local Administrators group, including orphaned SIDs of deleted accounts.

    .DESCRIPTION
        Get-LocalAdminAudit finds the local Administrators group by its well-known SID (S-1-5-32-544),
        so it works on every display language (for example "Yöneticiler" on Turkish Windows), and reads
        its members with Get-CimAssociatedInstance through the Win32_GroupUser association.

        Members whose SID can no longer be resolved to an account (typically deleted domain accounts)
        do not cause an error. They are returned with IsOrphaned = $true and MemberType = Unknown so
        they can be cleaned up. If WMI cannot resolve such a member through the association, the
        membership references are read from Win32_GroupUser and every unresolvable member is reported
        as orphaned.

        With -ExpectedMember, IsExpected shows whether a member matches the approved list, which makes
        unexpected administrators easy to filter.

    .PARAMETER ComputerName
        The computers to query. Defaults to the local computer. Accepts pipeline input, including
        objects with a ComputerName, DNSHostName or Name property (for example from Get-ADComputer).

    .PARAMETER ExpectedMember
        Approved members. Each entry is compared with DOMAIN\Name, Name and SID and may contain
        wildcards, for example 'CONTOSO\Domain Admins', '*\Administrator' or 'S-1-5-21-*-512'.
        When omitted, IsExpected is empty.

    .PARAMETER Credential
        Credentials for remote computers. Ignored for the local computer.

    .PARAMETER TimeoutSeconds
        Seconds to wait for a computer to respond before it is reported as unreachable. Defaults to 15.

    .EXAMPLE
        Get-LocalAdminAudit

        Lists the local administrators of this computer.

    .EXAMPLE
        Get-LocalAdminAudit -ComputerName SRV01, SRV02 -ExpectedMember '*\Administrator', 'CONTOSO\Domain Admins' | Where-Object { -not $_.IsExpected }

        Shows administrators that are not on the approved list.

    .EXAMPLE
        Get-ADComputer -Filter * -SearchBase 'OU=Servers,DC=contoso,DC=com' | Get-LocalAdminAudit | Where-Object IsOrphaned | Export-ITReport -Path .\orphaned-admins.csv

        Exports every orphaned SID found in the Administrators group of the servers in an OU.

    .INPUTS
        System.String

    .OUTPUTS
        ITToolkit.LocalAdminMember

    .NOTES
        On domain controllers there is no local Administrators group; use Active Directory tools there.

    .LINK
        Export-ITReport
    #>
    [CmdletBinding()]
    [OutputType('ITToolkit.LocalAdminMember')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('CN', 'DNSHostName', 'Name')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [string[]]$ExpectedMember,

        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 15
    )

    begin {
        $administratorsSid = 'S-1-5-32-544'
    }

    process {
        foreach ($computer in $ComputerName) {
            $session = $null
            try {
                $session = Open-ITCimSession -ComputerName $computer -Credential $Credential -TimeoutSeconds $TimeoutSeconds
                $displayName = Resolve-ITComputerName -ComputerName $computer

                $group = Get-CimInstance -CimSession $session -ClassName Win32_Group -Filter "LocalAccount = TRUE AND SID = '$administratorsSid'" -ErrorAction Stop |
                    Select-Object -First 1
                if (-not $group) {
                    throw "The local Administrators group ($administratorsSid) was not found."
                }
                $groupName = "$($group.Domain)\$($group.Name)"
                $recordParams = @{ ComputerName = $displayName; Group = $groupName; ExpectedMember = $ExpectedMember }

                $associationErrors = $null
                $members = @(Get-CimAssociatedInstance -CimSession $session -InputObject $group -Association Win32_GroupUser -ErrorAction SilentlyContinue -ErrorVariable associationErrors)

                foreach ($member in $members) {
                    ConvertTo-ITLocalAdminRecord @recordParams -Member $member
                }

                if ($associationErrors) {
                    # At least one member could not be resolved (for example a deleted account). Read the
                    # raw membership references and report what the association could not return.
                    Write-Verbose -Message "[$displayName] $(@($associationErrors).Count) member(s) could not be resolved; reading Win32_GroupUser references."

                    $resolved = @($members | ForEach-Object { "$($_.Domain)\$($_.Name)" })
                    $groupPath = "Win32_Group.Domain='$(ConvertTo-ITWqlString -Value $group.Domain)',Name='$(ConvertTo-ITWqlString -Value $group.Name)'"
                    $references = @(Get-CimInstance -CimSession $session -ClassName Win32_GroupUser -Filter "GroupComponent = `"$groupPath`"" -ErrorAction Stop)

                    foreach ($reference in $references) {
                        $part = $reference.PartComponent
                        if ($resolved -contains "$($part.Domain)\$($part.Name)") {
                            continue
                        }

                        $accountFilter = "Domain = '$(ConvertTo-ITWqlString -Value $part.Domain)' AND Name = '$(ConvertTo-ITWqlString -Value $part.Name)'"
                        $account = Get-CimInstance -CimSession $session -ClassName Win32_Account -Filter $accountFilter -ErrorAction SilentlyContinue |
                            Select-Object -First 1

                        if ($account) {
                            ConvertTo-ITLocalAdminRecord @recordParams -Member $account
                        }
                        else {
                            ConvertTo-ITLocalAdminRecord @recordParams -Member $part -Unresolved
                        }
                    }
                }
            }
            catch {
                Write-Error -Message "[$computer] Local administrator audit failed: $($_.Exception.Message)" -Exception $_.Exception -Category ConnectionError -ErrorId 'LocalAdminAuditFailed' -TargetObject $computer
            }
            finally {
                if ($session) {
                    Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
