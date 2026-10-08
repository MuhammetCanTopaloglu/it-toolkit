function ConvertTo-ITLocalAdminRecord {
    <#
    .SYNOPSIS
        Builds an ITToolkit.LocalAdminMember object from a resolved or unresolved group member.

    .DESCRIPTION
        A member is orphaned when Windows can no longer translate its SID to an account: WMI reports
        SIDType 6 (deleted), 7 (invalid) or 8 (unknown), returns the bare SID as the account name, or
        the member cannot be resolved at all (-Unresolved).
    #>
    [CmdletBinding()]
    [OutputType('ITToolkit.LocalAdminMember')]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Group,

        [Parameter(Mandatory)]
        [psobject]$Member,

        [string[]]$ExpectedMember,

        [switch]$Unresolved
    )

    $sidPattern = '^S-1-\d+(-\d+)+$'
    $orphanSidTypes = @(6, 7, 8)

    $className = $null
    if ($Member.PSObject.Properties['CimSystemProperties'] -and $Member.CimSystemProperties) {
        $className = $Member.CimSystemProperties.ClassName
    }
    $sidType = $null
    if ($null -ne $Member.SIDType) {
        $sidType = [int]$Member.SIDType
    }

    $sid = $Member.SID
    if (-not $sid -and $Member.Name -match $sidPattern) {
        $sid = $Member.Name
    }

    $isOrphaned = $Unresolved.IsPresent -or ($orphanSidTypes -contains $sidType) -or ($Member.Name -match $sidPattern)

    $memberType = 'Unknown'
    if (-not $isOrphaned) {
        switch ($className) {
            'Win32_UserAccount' { $memberType = 'User' }
            'Win32_Group' { $memberType = 'Group' }
            'Win32_SystemAccount' { $memberType = 'SystemAccount' }
            default {
                switch ($sidType) {
                    1 { $memberType = 'User' }
                    2 { $memberType = 'Group' }
                    4 { $memberType = 'Group' }
                    5 { $memberType = 'WellKnownGroup' }
                    9 { $memberType = 'Computer' }
                }
            }
        }
    }

    $memberName = $Member.Name
    if ($Member.Domain) {
        $memberName = "$($Member.Domain)\$($Member.Name)"
    }

    $isLocal = $null
    if ($null -ne $Member.LocalAccount) {
        $isLocal = [bool]$Member.LocalAccount
    }

    $isExpected = $null
    if ($ExpectedMember) {
        $isExpected = $false
        foreach ($pattern in $ExpectedMember) {
            if ($memberName -like $pattern -or $Member.Name -like $pattern -or ($sid -and $sid -like $pattern)) {
                $isExpected = $true
                break
            }
        }
    }

    [pscustomobject]@{
        PSTypeName   = 'ITToolkit.LocalAdminMember'
        ComputerName = $ComputerName
        Group        = $Group
        Member       = $memberName
        Domain       = $Member.Domain
        Name         = $Member.Name
        MemberType   = $memberType
        SID          = $sid
        IsLocal      = $isLocal
        IsOrphaned   = [bool]$isOrphaned
        IsExpected   = $isExpected
    }
}
