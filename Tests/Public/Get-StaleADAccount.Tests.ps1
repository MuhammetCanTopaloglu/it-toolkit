BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\Shared.ps1')

    function script:New-TestADAccount {
        param(
            [string]$Name,
            [string]$ObjectClass = 'user',
            [bool]$Enabled = $true,
            [object]$LastLogonDaysAgo,
            [int]$CreatedDaysAgo = 1000
        )
        $lastLogon = $null
        if ($null -ne $LastLogonDaysAgo) {
            $lastLogon = (Get-Date).AddDays(-$LastLogonDaysAgo).AddMinutes(-1)
        }
        [pscustomobject]@{
            Name              = $Name
            SamAccountName    = $Name
            ObjectClass       = $ObjectClass
            Enabled           = $Enabled
            LastLogonDate     = $lastLogon
            WhenCreated       = (Get-Date).AddDays(-$CreatedDaysAgo)
            DistinguishedName = "CN=$Name,OU=Test,DC=contoso,DC=test"
        }
    }
}

Describe 'Get-StaleADAccount' {
    BeforeAll {
        Mock -ModuleName ITToolkit Assert-ITADModule { }
        Mock -ModuleName ITToolkit Get-ADUser {
            New-TestADAccount -Name 'stale.user' -LastLogonDaysAgo 120
            New-TestADAccount -Name 'active.user' -LastLogonDaysAgo 3
            New-TestADAccount -Name 'never.old' -CreatedDaysAgo 200
            New-TestADAccount -Name 'never.new' -CreatedDaysAgo 5
            New-TestADAccount -Name 'disabled.user' -Enabled $false -LastLogonDaysAgo 400
        }
        Mock -ModuleName ITToolkit Get-ADComputer {
            New-TestADAccount -Name 'OLDPC01$' -ObjectClass computer -LastLogonDaysAgo 95
            New-TestADAccount -Name 'NEWPC01$' -ObjectClass computer -LastLogonDaysAgo 1
        }
    }

    It 'returns enabled users and computers older than 90 days, including old never-used accounts' {
        $result = Get-StaleADAccount

        ($result.SamAccountName | Sort-Object) | Should -Be @('never.old', 'OLDPC01$', 'stale.user')
    }

    It 'calculates the days since the last logon' {
        $result = Get-StaleADAccount -AccountType User

        ($result | Where-Object SamAccountName -EQ 'stale.user').DaysSinceLastLogon | Should -Be 120
        ($result | Where-Object SamAccountName -EQ 'stale.user').NeverLoggedOn | Should -BeFalse
        ($result | Where-Object SamAccountName -EQ 'never.old').DaysSinceLastLogon | Should -BeNullOrEmpty
        ($result | Where-Object SamAccountName -EQ 'never.old').NeverLoggedOn | Should -BeTrue
        $result[0].PSObject.TypeNames | Should -Contain 'ITToolkit.StaleADAccount'
    }

    It 'honours -Days' {
        $result = Get-StaleADAccount -Days 100 -AccountType User

        $result.SamAccountName | Should -Contain 'stale.user'
        $result.SamAccountName | Should -Contain 'never.old'
        (Get-StaleADAccount -Days 150 -AccountType User).SamAccountName | Should -Not -Contain 'stale.user'
    }

    It 'queries only the requested account type' {
        $null = Get-StaleADAccount -AccountType Computer

        Should -Invoke -ModuleName ITToolkit Get-ADComputer -Times 1 -Exactly
        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 0 -Exactly
    }

    It 'filters on lastLogonTimestamp and excludes disabled accounts in LDAP' {
        $cutoff = (Get-Date).AddDays(-90).ToFileTimeUtc()

        $null = Get-StaleADAccount -AccountType User

        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 1 -Exactly -ParameterFilter {
            $LDAPFilter -like '*(!(userAccountControl:1.2.840.113556.1.4.803:=2))*' -and
            $LDAPFilter -like '*(!(lastLogonTimestamp=*))*' -and
            [int64]([regex]::Match($LDAPFilter, 'lastLogonTimestamp<=(\d+)').Groups[1].Value) -ge $cutoff - 600000000 -and
            $Properties -contains 'LastLogonDate' -and $Properties -contains 'WhenCreated'
        }
    }

    It 'includes disabled accounts with -IncludeDisabled' {
        $result = Get-StaleADAccount -AccountType User -IncludeDisabled

        $result.SamAccountName | Should -Contain 'disabled.user'
        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 1 -Exactly -ParameterFilter { $LDAPFilter -notlike '*userAccountControl*' }
    }

    It 'searches every OU received from the pipeline' {
        $ous = @(
            [pscustomobject]@{ DistinguishedName = 'OU=Branch1,DC=contoso,DC=test' }
            [pscustomobject]@{ DistinguishedName = 'OU=Branch2,DC=contoso,DC=test' }
        )

        $null = $ous | Get-StaleADAccount -AccountType User

        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 1 -Exactly -ParameterFilter { $SearchBase -eq 'OU=Branch1,DC=contoso,DC=test' }
        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 1 -Exactly -ParameterFilter { $SearchBase -eq 'OU=Branch2,DC=contoso,DC=test' }
    }

    It 'passes -Server and -Credential to Active Directory' {
        $credential = [System.Management.Automation.PSCredential]::new('CONTOSO\auditor', [System.Security.SecureString]::new())

        $null = Get-StaleADAccount -AccountType User -Server 'dc01.contoso.test' -Credential $credential

        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 1 -Exactly -ParameterFilter {
            $Server -eq 'dc01.contoso.test' -and $Credential.UserName -eq 'CONTOSO\auditor'
        }
    }

    It 'reports a failed query as a non-terminating error and continues' {
        Mock -ModuleName ITToolkit Get-ADUser { throw 'Unable to contact the server.' }

        $output = Get-StaleADAccount -ErrorAction Continue 2>&1
        $failures = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

        $failures.Count | Should -Be 1
        $failures[0].FullyQualifiedErrorId | Should -BeLike 'StaleAccountQueryFailed*'
        @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).SamAccountName | Should -Be 'OLDPC01$'
    }

    It 'stops with installation guidance when the ActiveDirectory module is missing' {
        Mock -ModuleName ITToolkit Assert-ITADModule { throw 'The ActiveDirectory PowerShell module is required but is not installed. RSAT' }

        { Get-StaleADAccount } | Should -Throw -ExpectedMessage '*ActiveDirectory*RSAT*'
        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 0 -Exactly
    }
}

Describe 'Assert-ITADModule' {
    It 'explains how to install RSAT when the module is not available' {
        Mock -ModuleName ITToolkit Get-Module { }

        $thrown = $null
        try {
            InModuleScope ITToolkit { Assert-ITADModule }
        }
        catch {
            $thrown = $_
        }

        $thrown | Should -Not -BeNullOrEmpty
        $thrown.FullyQualifiedErrorId | Should -Be 'ActiveDirectoryModuleNotFound'
        $thrown.CategoryInfo.Category | Should -Be 'NotInstalled'
        $thrown.Exception.Message | Should -Match 'Add-WindowsCapability -Online -Name Rsat\.ActiveDirectory'
        $thrown.Exception.Message | Should -Match 'Install-WindowsFeature -Name RSAT-AD-PowerShell'
    }

    It 'imports the module when it is installed but not loaded' {
        Mock -ModuleName ITToolkit Get-Module { } -ParameterFilter { -not $ListAvailable }
        Mock -ModuleName ITToolkit Get-Module { [pscustomobject]@{ Name = 'ActiveDirectory' } } -ParameterFilter { $ListAvailable }
        Mock -ModuleName ITToolkit Import-Module { }

        InModuleScope ITToolkit { Assert-ITADModule }

        Should -Invoke -ModuleName ITToolkit Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'ActiveDirectory' }
    }

    It 'does nothing when the module is already loaded' {
        Mock -ModuleName ITToolkit Get-Module { [pscustomobject]@{ Name = 'ActiveDirectory' } }
        Mock -ModuleName ITToolkit Import-Module { }

        InModuleScope ITToolkit { Assert-ITADModule }

        Should -Invoke -ModuleName ITToolkit Import-Module -Times 0 -Exactly
    }
}
