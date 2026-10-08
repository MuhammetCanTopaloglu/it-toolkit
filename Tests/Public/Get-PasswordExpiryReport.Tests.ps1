BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\Shared.ps1')

    function script:New-TestADUser {
        param([string]$Name, [AllowNull()][object]$ExpiryFileTime)
        [pscustomobject]@{
            Name                                  = $Name
            DisplayName                           = "Display $Name"
            SamAccountName                        = $Name
            EmailAddress                          = "$Name@contoso.test"
            PasswordLastSet                       = (Get-Date).AddDays(-80)
            DistinguishedName                     = "CN=$Name,OU=Staff,DC=contoso,DC=test"
            'msDS-UserPasswordExpiryTimeComputed' = $ExpiryFileTime
        }
    }

    function script:Get-FileTimeIn {
        param([double]$Days)
        (Get-Date).AddDays($Days).AddMinutes(1).ToFileTime()
    }
}

Describe 'Get-PasswordExpiryReport' {
    BeforeAll {
        Mock -ModuleName ITToolkit Assert-ITADModule { }
        Mock -ModuleName ITToolkit Get-ADUser {
            New-TestADUser -Name 'soon' -ExpiryFileTime (Get-FileTimeIn -Days 5)
            New-TestADUser -Name 'later' -ExpiryFileTime (Get-FileTimeIn -Days 40)
            New-TestADUser -Name 'expired' -ExpiryFileTime (Get-FileTimeIn -Days -3)
            New-TestADUser -Name 'mustchange' -ExpiryFileTime ([int64]0)
            New-TestADUser -Name 'neverexpires' -ExpiryFileTime ([int64]::MaxValue)
            New-TestADUser -Name 'nodata' -ExpiryFileTime $null
        }
    }

    It 'reports passwords that expire within the default 14 days' {
        $soon = Get-PasswordExpiryReport | Where-Object SamAccountName -EQ 'soon'

        $soon.Status | Should -Be 'Expiring'
        $soon.DaysUntilExpiry | Should -Be 5
        $soon.PasswordExpires | Should -BeOfType [datetime]
        $soon.EmailAddress | Should -Be 'soon@contoso.test'
        $soon.PSObject.TypeNames | Should -Contain 'ITToolkit.PasswordExpiry'
    }

    It 'does not report passwords that expire later than -Days' {
        (Get-PasswordExpiryReport).SamAccountName | Should -Not -Contain 'later'
        (Get-PasswordExpiryReport -Days 60).SamAccountName | Should -Contain 'later'
    }

    It 'reports the value 0 as MustChangePassword' {
        $user = Get-PasswordExpiryReport | Where-Object SamAccountName -EQ 'mustchange'

        $user.Status | Should -Be 'MustChangePassword'
        $user.PasswordExpires | Should -BeNullOrEmpty
        $user.DaysUntilExpiry | Should -BeNullOrEmpty
    }

    It 'skips the maximum Int64 value (never expires) without an error' {
        $output = Get-PasswordExpiryReport 2>&1

        @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | Should -BeNullOrEmpty
        $output.SamAccountName | Should -Not -Contain 'neverexpires'
    }

    It 'skips users without a computed expiry time' {
        (Get-PasswordExpiryReport).SamAccountName | Should -Not -Contain 'nodata'
    }

    It 'reports expired passwords only with -IncludeExpired' {
        (Get-PasswordExpiryReport).SamAccountName | Should -Not -Contain 'expired'

        $expired = Get-PasswordExpiryReport -IncludeExpired | Where-Object SamAccountName -EQ 'expired'
        $expired.Status | Should -Be 'Expired'
        $expired.DaysUntilExpiry | Should -BeLessThan 0
    }

    It 'returns exactly the expiring and must-change users by default' {
        (Get-PasswordExpiryReport).SamAccountName | Sort-Object | Should -Be @('mustchange', 'soon')
    }

    It 'queries enabled users without "password never expires" and the computed attribute' {
        $null = Get-PasswordExpiryReport

        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 1 -Exactly -ParameterFilter {
            $LDAPFilter -like '*(!(userAccountControl:1.2.840.113556.1.4.803:=2))*' -and
            $LDAPFilter -like '*(!(userAccountControl:1.2.840.113556.1.4.803:=65536))*' -and
            $Properties -contains 'msDS-UserPasswordExpiryTimeComputed'
        }
    }

    It 'searches every OU received from the pipeline and passes -Server' {
        $null = 'OU=A,DC=contoso,DC=test', 'OU=B,DC=contoso,DC=test' | Get-PasswordExpiryReport -Server 'dc01.contoso.test'

        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 2 -Exactly -ParameterFilter { $Server -eq 'dc01.contoso.test' }
        Should -Invoke -ModuleName ITToolkit Get-ADUser -Times 1 -Exactly -ParameterFilter { $SearchBase -eq 'OU=B,DC=contoso,DC=test' }
    }

    It 'reports a failed query as a non-terminating error' {
        Mock -ModuleName ITToolkit Get-ADUser { throw 'Unable to contact the server.' }

        $failures = @(Get-PasswordExpiryReport 2>&1 | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

        $failures.Count | Should -Be 1
        $failures[0].FullyQualifiedErrorId | Should -BeLike 'PasswordExpiryQueryFailed*'
    }

    It 'stops when the ActiveDirectory module is missing' {
        Mock -ModuleName ITToolkit Assert-ITADModule { throw 'The ActiveDirectory PowerShell module is required but is not installed.' }

        { Get-PasswordExpiryReport } | Should -Throw -ExpectedMessage '*ActiveDirectory*'
    }
}
