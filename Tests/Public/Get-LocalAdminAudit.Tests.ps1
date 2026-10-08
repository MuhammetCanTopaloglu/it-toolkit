BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\Shared.ps1')

    function script:New-TestAccount {
        param(
            [string]$ClassName,
            [string]$Domain,
            [string]$Name,
            [string]$Sid,
            [byte]$SidType,
            [bool]$LocalAccount
        )
        New-CimInstance -ClassName $ClassName -ClientOnly -Property @{
            Domain       = $Domain
            Name         = $Name
            SID          = $Sid
            SIDType      = $SidType
            LocalAccount = $LocalAccount
        }
    }

    function script:Get-ErrorRecord {
        param($Output)
        @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    }
}

Describe 'Get-LocalAdminAudit' {
    BeforeAll {
        Mock -ModuleName ITToolkit Open-ITCimSession { New-MockObject -Type ([Microsoft.Management.Infrastructure.CimSession]) }
        Mock -ModuleName ITToolkit Remove-CimSession { }

        # Turkish display name: the group must be found by SID, not by name.
        Mock -ModuleName ITToolkit Get-CimInstance {
            New-CimInstance -ClassName Win32_Group -ClientOnly -Property @{ Domain = 'SRV01'; Name = 'Yöneticiler'; SID = 'S-1-5-32-544' }
        } -ParameterFilter { $ClassName -eq 'Win32_Group' }

        Mock -ModuleName ITToolkit Get-CimAssociatedInstance {
            New-TestAccount -ClassName Win32_UserAccount -Domain 'SRV01' -Name 'Administrator' -Sid 'S-1-5-21-1-2-3-500' -SidType 1 -LocalAccount $true
            New-TestAccount -ClassName Win32_Group -Domain 'CONTOSO' -Name 'Domain Admins' -Sid 'S-1-5-21-9-8-7-512' -SidType 2 -LocalAccount $false
        }
    }

    It 'finds the Administrators group by its well-known SID' {
        $null = Get-LocalAdminAudit

        Should -Invoke -ModuleName ITToolkit Get-CimInstance -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq 'Win32_Group' -and $Filter -eq "LocalAccount = TRUE AND SID = 'S-1-5-32-544'"
        }
    }

    It 'reads members with Get-CimAssociatedInstance through Win32_GroupUser' {
        $null = Get-LocalAdminAudit

        Should -Invoke -ModuleName ITToolkit Get-CimAssociatedInstance -Times 1 -Exactly -ParameterFilter {
            $Association -eq 'Win32_GroupUser' -and $InputObject.SID -eq 'S-1-5-32-544'
        }
    }

    It 'returns one object per member with the localized group name' {
        $result = @(Get-LocalAdminAudit)

        $result.Count | Should -Be 2
        $result[0].Group | Should -Be 'SRV01\Yöneticiler'
        $result[0].Member | Should -Be 'SRV01\Administrator'
        $result[0].MemberType | Should -Be 'User'
        $result[0].IsLocal | Should -BeTrue
        $result[1].Member | Should -Be 'CONTOSO\Domain Admins'
        $result[1].MemberType | Should -Be 'Group'
        $result[1].IsLocal | Should -BeFalse
        $result.IsOrphaned | Should -Not -Contain $true
        $result[0].PSObject.TypeNames | Should -Contain 'ITToolkit.LocalAdminMember'
    }

    Context 'orphaned SIDs' {
        It 'flags a member that WMI reports as a deleted account (SIDType 6) without an error' {
            Mock -ModuleName ITToolkit Get-CimAssociatedInstance {
                New-TestAccount -ClassName Win32_UserAccount -Domain 'SRV01' -Name 'Administrator' -Sid 'S-1-5-21-1-2-3-500' -SidType 1 -LocalAccount $true
                New-TestAccount -ClassName Win32_Account -Domain 'CONTOSO' -Name 'old.user' -Sid 'S-1-5-21-9-8-7-4242' -SidType 6 -LocalAccount $false
            }

            $output = Get-LocalAdminAudit 2>&1
            $orphan = $output | Where-Object Name -EQ 'old.user'

            Get-ErrorRecord -Output $output | Should -BeNullOrEmpty
            $orphan.IsOrphaned | Should -BeTrue
            $orphan.MemberType | Should -Be 'Unknown'
            $orphan.SID | Should -Be 'S-1-5-21-9-8-7-4242'
        }

        It 'flags a member whose name is a bare SID' {
            Mock -ModuleName ITToolkit Get-CimAssociatedInstance {
                New-TestAccount -ClassName Win32_Account -Domain '' -Name 'S-1-5-21-9-8-7-1337' -Sid '' -SidType 8 -LocalAccount $false
            }

            $result = Get-LocalAdminAudit

            $result.IsOrphaned | Should -BeTrue
            $result.SID | Should -Be 'S-1-5-21-9-8-7-1337'
            $result.Member | Should -Be 'S-1-5-21-9-8-7-1337'
        }

        It 'reports members that the association cannot resolve as orphaned and keeps the others' {
            Mock -ModuleName ITToolkit Get-CimAssociatedInstance {
                New-TestAccount -ClassName Win32_UserAccount -Domain 'SRV01' -Name 'Administrator' -Sid 'S-1-5-21-1-2-3-500' -SidType 1 -LocalAccount $true
                # Behave like the CIM cmdlet: a non-terminating error that honours the caller's -ErrorAction.
                Write-Error -Message 'Not found' -ErrorAction $PesterBoundParameters['ErrorAction']
            }
            Mock -ModuleName ITToolkit Get-CimInstance {
                foreach ($part in @(
                        @{ Domain = 'SRV01'; Name = 'Administrator' }
                        @{ Domain = 'CONTOSO'; Name = 'S-1-5-21-9-8-7-5555' }
                        @{ Domain = 'CONTOSO'; Name = 'helpdesk' }
                    )) {
                    [pscustomobject]@{ PartComponent = [pscustomobject]$part }
                }
            } -ParameterFilter { $ClassName -eq 'Win32_GroupUser' }
            Mock -ModuleName ITToolkit Get-CimInstance { } -ParameterFilter { $ClassName -eq 'Win32_Account' }
            Mock -ModuleName ITToolkit Get-CimInstance {
                New-TestAccount -ClassName Win32_Group -Domain 'CONTOSO' -Name 'helpdesk' -Sid 'S-1-5-21-9-8-7-1100' -SidType 2 -LocalAccount $false
            } -ParameterFilter { $ClassName -eq 'Win32_Account' -and $Filter -like "*Name = 'helpdesk'" }

            $output = Get-LocalAdminAudit 2>&1
            $result = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            Get-ErrorRecord -Output $output | Should -BeNullOrEmpty
            $result.Count | Should -Be 3
            ($result | Where-Object Name -EQ 'Administrator').IsOrphaned | Should -BeFalse
            ($result | Where-Object Name -EQ 'helpdesk').IsOrphaned | Should -BeFalse
            ($result | Where-Object Name -EQ 'helpdesk').MemberType | Should -Be 'Group'

            $orphan = $result | Where-Object Name -EQ 'S-1-5-21-9-8-7-5555'
            $orphan.IsOrphaned | Should -BeTrue
            $orphan.MemberType | Should -Be 'Unknown'
            $orphan.SID | Should -Be 'S-1-5-21-9-8-7-5555'
            $orphan.Member | Should -Be 'CONTOSO\S-1-5-21-9-8-7-5555'

            Should -Invoke -ModuleName ITToolkit Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ClassName -eq 'Win32_GroupUser' -and $Filter -eq "GroupComponent = `"Win32_Group.Domain='SRV01',Name='Yöneticiler'`""
            }
        }

        It 'does not read references when every member resolves' {
            $null = Get-LocalAdminAudit

            Should -Invoke -ModuleName ITToolkit Get-CimInstance -Times 0 -Exactly -ParameterFilter { $ClassName -eq 'Win32_GroupUser' }
        }
    }

    Context 'expected members' {
        It 'leaves IsExpected empty when no list is given' {
            (Get-LocalAdminAudit).IsExpected | ForEach-Object { $_ | Should -BeNullOrEmpty }
        }

        It 'marks members that match the approved list, with wildcards' {
            $result = Get-LocalAdminAudit -ExpectedMember '*\Administrator'

            ($result | Where-Object Name -EQ 'Administrator').IsExpected | Should -BeTrue
            ($result | Where-Object Name -EQ 'Domain Admins').IsExpected | Should -BeFalse
        }

        It 'matches by SID' {
            $result = Get-LocalAdminAudit -ExpectedMember 'S-1-5-21-*-512'

            ($result | Where-Object Name -EQ 'Domain Admins').IsExpected | Should -BeTrue
        }
    }

    Context 'errors' {
        It 'reports a missing Administrators group as an error' {
            Mock -ModuleName ITToolkit Get-CimInstance { } -ParameterFilter { $ClassName -eq 'Win32_Group' }

            $errors = Get-ErrorRecord -Output (Get-LocalAdminAudit 2>&1)

            $errors.Count | Should -Be 1
            $errors[0].Exception.Message | Should -Match 'S-1-5-32-544'
        }

        It 'continues with the next computer when one is unreachable' {
            Mock -ModuleName ITToolkit Open-ITCimSession { throw 'did not respond' } -ParameterFilter { $ComputerName -eq 'OFFLINE01' }

            $output = Get-LocalAdminAudit -ComputerName 'OFFLINE01', 'SRV01' 2>&1
            $errors = Get-ErrorRecord -Output $output

            $errors.Count | Should -Be 1
            $errors[0].FullyQualifiedErrorId | Should -BeLike 'LocalAdminAuditFailed*'
            @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count | Should -Be 2
        }
    }
}

Describe 'ConvertTo-ITWqlString' {
    It 'escapes quotes and backslashes' {
        InModuleScope ITToolkit {
            ConvertTo-ITWqlString -Value "O'Brien\x" | Should -Be "O\'Brien\\x"
        }
    }
}
