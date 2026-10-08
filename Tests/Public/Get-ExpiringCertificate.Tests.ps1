BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\Shared.ps1')

    function script:New-TestCertificate {
        param([string]$Subject, [int]$ExpiresInDays, [string]$Store = 'LocalMachine\My')
        [pscustomobject]@{
            Store         = $Store
            Subject       = $Subject
            FriendlyName  = ''
            Issuer        = 'CN=Contoso Issuing CA'
            Thumbprint    = ('{0:X40}' -f [math]::Abs($Subject.GetHashCode()))
            NotBefore     = (Get-Date).AddDays(-365)
            NotAfter      = (Get-Date).AddDays($ExpiresInDays).AddHours(1)
            HasPrivateKey = $true
        }
    }
}

Describe 'Get-ExpiringCertificate' {
    BeforeAll {
        $script:certificates = @(
            New-TestCertificate -Subject 'CN=expired.contoso.test' -ExpiresInDays -5
            New-TestCertificate -Subject 'CN=soon.contoso.test' -ExpiresInDays 10
            New-TestCertificate -Subject 'CN=later.contoso.test' -ExpiresInDays 45
            New-TestCertificate -Subject 'CN=fine.contoso.test' -ExpiresInDays 400
        )
        Mock -ModuleName ITToolkit Get-ITCertificateStoreItem { $script:certificates }
        Mock -ModuleName ITToolkit Invoke-Command { $script:certificates }
        Mock -ModuleName ITToolkit Test-ITTcpPort { 5985 }
    }

    Context 'local computer' {
        It 'returns certificates that expire within the default 30 days' {
            $result = @(Get-ExpiringCertificate)

            $result.Subject | Should -Be @('CN=soon.contoso.test')
            $result[0].DaysRemaining | Should -Be 10
            $result[0].IsExpired | Should -BeFalse
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
            $result[0].PSObject.TypeNames | Should -Contain 'ITToolkit.ExpiringCertificate'
        }

        It 'honours -Days' {
            (Get-ExpiringCertificate -Days 60).Subject | Should -Be @('CN=soon.contoso.test', 'CN=later.contoso.test')
        }

        It 'includes expired certificates only with -IncludeExpired' {
            $result = @(Get-ExpiringCertificate -IncludeExpired)

            $result.Subject | Should -Be @('CN=expired.contoso.test', 'CN=soon.contoso.test')
            $result[0].IsExpired | Should -BeTrue
            $result[0].DaysRemaining | Should -BeLessThan 0
        }

        It 'reads the requested stores directly without remoting' {
            $null = Get-ExpiringCertificate -StoreName My, WebHosting

            Should -Invoke -ModuleName ITToolkit Get-ITCertificateStoreItem -Times 1 -Exactly -ParameterFilter {
                ($StoreName -join ',') -eq 'My,WebHosting'
            }
            Should -Invoke -ModuleName ITToolkit Invoke-Command -Times 0 -Exactly
        }
    }

    Context 'remote computers' {
        It 'uses Invoke-Command with the store reader and an open timeout' {
            $server = 'WEB01'

            $result = Get-ExpiringCertificate -ComputerName $server -StoreName My, WebHosting -TimeoutSeconds 4

            $result.ComputerName | Should -Be 'WEB01'
            Should -Invoke -ModuleName ITToolkit Invoke-Command -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'WEB01' -and
                $ScriptBlock.ToString() -match 'X509Store' -and
                ($ArgumentList[0] -join ',') -eq 'My,WebHosting' -and
                $SessionOption.OpenTimeout -eq [timespan]::FromSeconds(4)
            }
        }

        It 'passes credentials to Invoke-Command' {
            $credential = [System.Management.Automation.PSCredential]::new('CONTOSO\auditor', [System.Security.SecureString]::new())
            $server = 'WEB01'

            $null = Get-ExpiringCertificate -ComputerName $server -Credential $credential

            Should -Invoke -ModuleName ITToolkit Invoke-Command -Times 1 -Exactly -ParameterFilter { $Credential.UserName -eq 'CONTOSO\auditor' }
        }

        It 'fails fast when WinRM does not answer and continues with the next computer' {
            Mock -ModuleName ITToolkit Test-ITTcpPort { } -ParameterFilter { $ComputerName -eq 'OFFLINE01' }

            $output = Get-ExpiringCertificate -ComputerName 'OFFLINE01', 'WEB01' -TimeoutSeconds 2 2>&1
            $failures = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            $failures.Count | Should -Be 1
            $failures[0].FullyQualifiedErrorId | Should -BeLike 'CertificateQueryFailed*'
            $failures[0].Exception.Message | Should -Match 'WinRM \(5985\) within 2 second'
            Should -Invoke -ModuleName ITToolkit Invoke-Command -Times 1 -Exactly
            @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).ComputerName | Should -Be 'WEB01'
        }
    }
}

Describe 'Get-ITCertificateStoreItem' {
    It 'reads the local machine store and returns plain objects' {
        InModuleScope ITToolkit {
            $items = @(Get-ITCertificateStoreItem -StoreName Root)

            $items.Count | Should -BeGreaterThan 0
            $items[0].Store | Should -Be 'LocalMachine\Root'
            $items[0].NotAfter | Should -BeOfType [datetime]
            $items[0].Thumbprint | Should -Not -BeNullOrEmpty
        }
    }

    It 'warns instead of failing for a store that does not exist' {
        InModuleScope ITToolkit {
            $items = Get-ITCertificateStoreItem -StoreName 'ITToolkitMissingStore' -WarningVariable warnings -WarningAction SilentlyContinue

            $items | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }
    }
}
