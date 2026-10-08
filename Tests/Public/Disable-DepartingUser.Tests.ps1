BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\Shared.ps1')

    $script:targetOU = 'OU=Disabled Users,DC=contoso,DC=test'
    $script:today = (Get-Date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $script:groupDns = @(
        'CN=Sales,OU=Groups,DC=contoso,DC=test'
        'CN=VPN Users,OU=Groups,DC=contoso,DC=test'
    )

    function script:New-TestUser {
        param(
            [string]$Sam = 'jdoe',
            [bool]$Enabled = $true,
            [string[]]$MemberOf = $script:groupDns,
            [string]$Description = 'Sales representative',
            [string]$ParentDn = 'OU=Sales,DC=contoso,DC=test'
        )
        [pscustomobject]@{
            SamAccountName    = $Sam
            DistinguishedName = "CN=$Sam,$ParentDn"
            ObjectGUID        = [guid]::NewGuid()
            Enabled           = $Enabled
            MemberOf          = $MemberOf
            Description       = $Description
        }
    }

    function script:Get-ErrorRecord {
        param($Output)
        @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    }

    function script:Get-Result {
        param($Output)
        @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
    }
}

Describe 'Disable-DepartingUser' {
    BeforeEach {
        $script:backupDir = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $script:logFile = Join-Path -Path $script:backupDir -ChildPath 'Disable-DepartingUser.log'
        $script:backupExistedAtRemoval = $null
        $script:user = New-TestUser

        Mock -ModuleName ITToolkit Assert-ITADModule { }
        Mock -ModuleName ITToolkit Get-ADObject { [pscustomobject]@{ DistinguishedName = $script:targetOU } }
        Mock -ModuleName ITToolkit Get-ADUser { $script:user }
        Mock -ModuleName ITToolkit Remove-ADGroupMember {
            if ($null -eq $script:backupExistedAtRemoval) {
                $script:backupExistedAtRemoval = @(Get-ChildItem -Path $script:backupDir -Filter '*_groups_*.csv' -ErrorAction SilentlyContinue).Count -gt 0
            }
        }
        Mock -ModuleName ITToolkit Disable-ADAccount { }
        Mock -ModuleName ITToolkit Set-ADUser { }
        Mock -ModuleName ITToolkit Move-ADObject { }
    }

    Context 'safety' {
        It 'supports -WhatIf/-Confirm with a high confirm impact' {
            $binding = (Get-Command -Name Disable-DepartingUser).ScriptBlock.Attributes |
                Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

            $binding.SupportsShouldProcess | Should -BeTrue
            $binding.ConfirmImpact | Should -Be 'High'
        }

        It 'changes nothing and writes no file with -WhatIf' {
            $output = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -TargetOU $script:targetOU -WhatIf

            $output | Should -BeNullOrEmpty
            Should -Invoke -ModuleName ITToolkit Remove-ADGroupMember -Times 0 -Exactly
            Should -Invoke -ModuleName ITToolkit Disable-ADAccount -Times 0 -Exactly
            Should -Invoke -ModuleName ITToolkit Set-ADUser -Times 0 -Exactly
            Should -Invoke -ModuleName ITToolkit Move-ADObject -Times 0 -Exactly
            Test-Path -Path $script:backupDir | Should -BeFalse
        }

        It 'writes the backup before removing any group membership' {
            $null = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -Confirm:$false

            $script:backupExistedAtRemoval | Should -BeTrue
        }

        It 'does not change the user when the backup cannot be written' {
            Mock -ModuleName ITToolkit Export-Csv { throw 'Disk full' }

            $output = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -TargetOU $script:targetOU -Confirm:$false 2>&1
            $errors = Get-ErrorRecord -Output $output

            $errors.Count | Should -Be 1
            $errors[0].FullyQualifiedErrorId | Should -BeLike 'DepartingUserBackupFailed*'
            Get-Result -Output $output | Should -BeNullOrEmpty
            Should -Invoke -ModuleName ITToolkit Remove-ADGroupMember -Times 0 -Exactly
            Should -Invoke -ModuleName ITToolkit Disable-ADAccount -Times 0 -Exactly
            Should -Invoke -ModuleName ITToolkit Set-ADUser -Times 0 -Exactly
            Should -Invoke -ModuleName ITToolkit Move-ADObject -Times 0 -Exactly
            Get-Content -Path $script:logFile -Raw | Should -Match '\| ERROR \|.*backup failed.*Disk full'
        }

        It 'stops before any change when the target OU does not exist' {
            Mock -ModuleName ITToolkit Get-ADObject { throw 'Directory object not found' }

            { Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -TargetOU 'OU=Missing,DC=contoso,DC=test' -Confirm:$false } |
                Should -Throw -ExpectedMessage "*Target OU 'OU=Missing,DC=contoso,DC=test' was not found*"
            Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 0 -Exactly
        }

        It 'stops when the ActiveDirectory module is missing' {
            Mock -ModuleName ITToolkit Assert-ITADModule { throw 'The ActiveDirectory PowerShell module is required but is not installed.' }

            { Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -Confirm:$false } | Should -Throw -ExpectedMessage '*ActiveDirectory*'
            Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 0 -Exactly
        }
    }

    Context 'full run' {
        BeforeEach {
            $script:result = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -TargetOU $script:targetOU -Confirm:$false
        }

        It 'backs up the group memberships to CSV' {
            $script:result.BackupFile | Should -Match '\\jdoe_groups_\d{8}-\d{6}\.csv$'
            $rows = @(Import-Csv -Path $script:result.BackupFile)
            $rows.GroupDistinguishedName | Should -Be $script:groupDns
            $rows[0].SamAccountName | Should -Be 'jdoe'
            $rows[0].UserDistinguishedName | Should -Be 'CN=jdoe,OU=Sales,DC=contoso,DC=test'
        }

        It 'removes the user from every group' {
            Should -Invoke -ModuleName ITToolkit Remove-ADGroupMember -Times 2 -Exactly
            foreach ($group in $script:groupDns) {
                Should -Invoke -ModuleName ITToolkit Remove-ADGroupMember -Times 1 -Exactly -ParameterFilter { $Identity -eq $group -and $Members[0].SamAccountName -eq 'jdoe' }
            }
            $script:result.GroupsRemoved | Should -Be $script:groupDns
            $script:result.GroupsFailed | Should -BeNullOrEmpty
        }

        It 'disables the account by its GUID' {
            Should -Invoke -ModuleName ITToolkit Disable-ADAccount -Times 1 -Exactly -ParameterFilter { $Identity -eq $script:user.ObjectGUID }
            $script:result.Disabled | Should -BeTrue
        }

        It 'writes the date in front of the previous description' {
            Should -Invoke -ModuleName ITToolkit Set-ADUser -Times 1 -Exactly -ParameterFilter {
                $Description -eq "Disabled $script:today - Sales representative"
            }
            $script:result.DescriptionUpdated | Should -BeTrue
        }

        It 'moves the account to the target OU' {
            Should -Invoke -ModuleName ITToolkit Move-ADObject -Times 1 -Exactly -ParameterFilter {
                $Identity -eq $script:user.ObjectGUID -and $TargetPath -eq $script:targetOU
            }
            $script:result.MovedTo | Should -Be $script:targetOU
        }

        It 'returns a completed result' {
            $script:result.PSObject.TypeNames | Should -Contain 'ITToolkit.DepartingUserResult'
            $script:result.Status | Should -Be 'Completed'
            $script:result.SamAccountName | Should -Be 'jdoe'
            $script:result.Errors | Should -BeNullOrEmpty
            $script:result.LogFile | Should -Be $script:logFile
        }

        It 'logs every action with operator and target' {
            $lines = @(Get-Content -Path $script:logFile)
            $operator = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

            $lines | Should -Not -BeNullOrEmpty
            $lines | ForEach-Object { $_ | Should -Match ('^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{2}:\d{2} \| INFO  \| ' + [regex]::Escape($operator) + ' \| jdoe \| ') }
            ($lines -join "`n") | Should -Match 'Backed up 2 group membership\(s\)'
            ($lines -join "`n") | Should -Match "Removed from group 'CN=Sales,"
            ($lines -join "`n") | Should -Match "Removed from group 'CN=VPN Users,"
            ($lines -join "`n") | Should -Match 'Account disabled\.'
            ($lines -join "`n") | Should -Match "Description changed from 'Sales representative' to 'Disabled $script:today - Sales representative'"
            ($lines -join "`n") | Should -Match "Moved from 'OU=Sales,DC=contoso,DC=test' to 'OU=Disabled Users,DC=contoso,DC=test'"
            ($lines -join "`n") | Should -Match 'Processing finished: Completed\.'
        }
    }

    Context 'partial failures and idempotency' {
        It 'continues after a failed group removal and reports it' {
            Mock -ModuleName ITToolkit Remove-ADGroupMember { throw 'Insufficient access rights' } -ParameterFilter { $Identity -like 'CN=Sales,*' }

            $output = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -TargetOU $script:targetOU -Confirm:$false 2>&1
            $result = Get-Result -Output $output

            (Get-ErrorRecord -Output $output).Count | Should -Be 1
            $result.Status | Should -Be 'CompletedWithErrors'
            $result.GroupsFailed | Should -Be @('CN=Sales,OU=Groups,DC=contoso,DC=test')
            $result.GroupsRemoved | Should -Be @('CN=VPN Users,OU=Groups,DC=contoso,DC=test')
            $result.Errors[0] | Should -Match 'Insufficient access rights'
            Should -Invoke -ModuleName ITToolkit Disable-ADAccount -Times 1 -Exactly
            Should -Invoke -ModuleName ITToolkit Move-ADObject -Times 1 -Exactly
            Get-Content -Path $script:logFile -Raw | Should -Match "\| ERROR \|.*Could not remove from group 'CN=Sales,"
        }

        It 'does not disable an account that is already disabled' {
            $script:user = New-TestUser -Enabled $false

            $result = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -Confirm:$false

            Should -Invoke -ModuleName ITToolkit Disable-ADAccount -Times 0 -Exactly
            $result.Disabled | Should -BeTrue
        }

        It 'does not stamp the description twice on the same day' {
            $script:user = New-TestUser -Description "Disabled $script:today - Sales representative"

            $result = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -Confirm:$false

            Should -Invoke -ModuleName ITToolkit Set-ADUser -Times 0 -Exactly
            $result.DescriptionUpdated | Should -BeTrue
        }

        It 'uses a custom description prefix and handles an empty description' {
            $script:user = New-TestUser -Description ''

            $null = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -DescriptionPrefix 'Left the company' -Confirm:$false

            Should -Invoke -ModuleName ITToolkit Set-ADUser -Times 1 -Exactly -ParameterFilter { $Description -eq "Left the company $script:today" }
        }

        It 'does not move an account that is already in the target OU' {
            $script:user = New-TestUser -ParentDn $script:targetOU

            $result = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -TargetOU $script:targetOU -Confirm:$false

            Should -Invoke -ModuleName ITToolkit Move-ADObject -Times 0 -Exactly
            $result.MovedTo | Should -Be $script:targetOU
        }

        It 'does not move the account without -TargetOU' {
            $result = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -Confirm:$false

            Should -Invoke -ModuleName ITToolkit Move-ADObject -Times 0 -Exactly
            Should -Invoke -ModuleName ITToolkit Get-ADObject -Times 0 -Exactly
            $result.MovedTo | Should -BeNullOrEmpty
        }

        It 'creates no backup file for a user without group memberships' {
            $script:user = New-TestUser -MemberOf @()

            $result = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -Confirm:$false

            $result.BackupFile | Should -BeNullOrEmpty
            Should -Invoke -ModuleName ITToolkit Remove-ADGroupMember -Times 0 -Exactly
            Should -Invoke -ModuleName ITToolkit Disable-ADAccount -Times 1 -Exactly
        }
    }

    Context 'input and options' {
        It 'processes users from the pipeline and continues after an unknown user' {
            Mock -ModuleName ITToolkit Get-ADUser { throw 'Cannot find an object with identity' } -ParameterFilter { $Identity -eq 'ghost' }
            $script:user = New-TestUser -Sam 'jdoe'
            $leavers = @(
                [pscustomobject]@{ SamAccountName = 'ghost' }
                [pscustomobject]@{ SamAccountName = 'jdoe' }
            )

            $output = $leavers | Disable-DepartingUser -BackupDirectory $script:backupDir -Confirm:$false 2>&1
            $errors = Get-ErrorRecord -Output $output

            $errors.Count | Should -Be 1
            $errors[0].FullyQualifiedErrorId | Should -BeLike 'DepartingUserNotFound*'
            $errors[0].TargetObject | Should -Be 'ghost'
            (Get-Result -Output $output).SamAccountName | Should -Be 'jdoe'
        }

        It 'passes -Server and -Credential to every Active Directory call' {
            $credential = [System.Management.Automation.PSCredential]::new('CONTOSO\hr-admin', [System.Security.SecureString]::new())

            $null = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -TargetOU $script:targetOU -Server 'dc01.contoso.test' -Credential $credential -Confirm:$false

            $filter = { $Server -eq 'dc01.contoso.test' -and $Credential.UserName -eq 'CONTOSO\hr-admin' }
            Should -Invoke -ModuleName ITToolkit Get-ADObject -Times 1 -Exactly -ParameterFilter $filter
            Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 1 -Exactly -ParameterFilter $filter
            Should -Invoke -ModuleName ITToolkit Remove-ADGroupMember -Times 2 -Exactly -ParameterFilter $filter
            Should -Invoke -ModuleName ITToolkit Disable-ADAccount -Times 1 -Exactly -ParameterFilter $filter
            Should -Invoke -ModuleName ITToolkit Set-ADUser -Times 1 -Exactly -ParameterFilter $filter
            Should -Invoke -ModuleName ITToolkit Move-ADObject -Times 1 -Exactly -ParameterFilter $filter
            Get-Content -Path $script:logFile -Raw | Should -Match '\(as CONTOSO\\hr-admin\)'
        }

        It 'writes the log to -LogPath when given' {
            $customLog = Join-Path -Path $TestDrive -ChildPath 'logs\offboarding.log'

            $result = Disable-DepartingUser -Identity 'jdoe' -BackupDirectory $script:backupDir -LogPath $customLog -Confirm:$false

            $result.LogFile | Should -Be $customLog
            Get-Content -Path $customLog -Raw | Should -Match 'Account disabled\.'
        }
    }
}

Describe 'Write-ITLog' {
    It 'creates the folder and appends formatted lines' {
        $path = Join-Path -Path $TestDrive -ChildPath 'new\folder\test.log'

        InModuleScope ITToolkit -Parameters @{ Path = $path } {
            Write-ITLog -Path $Path -Message 'first' -Target 'jdoe' -Operator 'CONTOSO\admin'
            Write-ITLog -Path $Path -Message 'second' -Level ERROR -Target 'jdoe' -Operator 'CONTOSO\admin'
        }

        $lines = @(Get-Content -Path $path)
        $lines.Count | Should -Be 2
        $lines[0] | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{2}:\d{2} \| INFO  \| CONTOSO\\admin \| jdoe \| first$'
        $lines[1] | Should -Match '\| ERROR \| CONTOSO\\admin \| jdoe \| second$'
    }
}
