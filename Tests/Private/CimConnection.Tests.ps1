BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\Shared.ps1')
}

Describe 'Test-ITLocalComputer' {
    It 'recognises <_> as the local computer' -ForEach @('.', 'localhost', '127.0.0.1', $env:COMPUTERNAME) {
        InModuleScope ITToolkit -Parameters @{ Name = $_ } {
            Test-ITLocalComputer -ComputerName $Name | Should -BeTrue
        }
    }

    It 'treats other names as remote' {
        InModuleScope ITToolkit {
            $remote = 'REMOTE-SRV-01'
            Test-ITLocalComputer -ComputerName $remote | Should -BeFalse
        }
    }
}

Describe 'Resolve-ITComputerName' {
    It 'returns the real host name for local aliases' {
        InModuleScope ITToolkit {
            $alias = 'localhost'
            Resolve-ITComputerName -ComputerName $alias | Should -Be $env:COMPUTERNAME
        }
    }

    It 'returns remote names unchanged' {
        InModuleScope ITToolkit {
            $remote = 'srv01.contoso.test'
            Resolve-ITComputerName -ComputerName $remote | Should -Be 'srv01.contoso.test'
        }
    }
}

Describe 'Test-ITTcpPort' {
    BeforeAll {
        $script:listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $script:listener.Start()
        $script:openPort = $script:listener.LocalEndpoint.Port

        # Reserve and release a port so that nothing is listening on it.
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start()
        $script:closedPort = $probe.LocalEndpoint.Port
        $probe.Stop()
    }

    AfterAll {
        $script:listener.Stop()
    }

    It 'returns a port that accepts connections' {
        InModuleScope ITToolkit -Parameters @{ Port = $script:openPort } {
            Test-ITTcpPort -ComputerName '127.0.0.1' -Port $Port -TimeoutSeconds 5 | Should -Be $Port
        }
    }

    It 'returns nothing for a closed port' {
        InModuleScope ITToolkit -Parameters @{ Port = $script:closedPort } {
            Test-ITTcpPort -ComputerName '127.0.0.1' -Port $Port -TimeoutSeconds 2 | Should -BeNullOrEmpty
        }
    }

    It 'returns only the open ports when several are probed' {
        InModuleScope ITToolkit -Parameters @{ Open = $script:openPort; Closed = $script:closedPort } {
            $result = @(Test-ITTcpPort -ComputerName '127.0.0.1' -Port $Closed, $Open -TimeoutSeconds 5)
            $result | Should -Be @($Open)
        }
    }
}

Describe 'Open-ITCimSession' {
    BeforeAll {
        Mock -ModuleName ITToolkit New-CimSession { 'wsman-session' }
        Mock -ModuleName ITToolkit New-CimSession { 'dcom-session' } -ParameterFilter { $null -ne $SessionOption }
    }

    It 'opens a local session without probing ports or passing a computer name' {
        Mock -ModuleName ITToolkit Test-ITTcpPort { }

        InModuleScope ITToolkit {
            $local = 'localhost'
            $null = Open-ITCimSession -ComputerName $local -TimeoutSeconds 7
        }

        Should -Invoke -ModuleName ITToolkit Test-ITTcpPort -Times 0 -Exactly
        Should -Invoke -ModuleName ITToolkit New-CimSession -Times 1 -Exactly -ParameterFilter {
            [string]::IsNullOrEmpty($ComputerName) -and $OperationTimeoutSec -eq 7
        }
    }

    It 'fails fast when neither WSMan nor DCOM answers' {
        Mock -ModuleName ITToolkit Test-ITTcpPort { }

        {
            InModuleScope ITToolkit {
                $offline = 'OFFLINE01'
                Open-ITCimSession -ComputerName $offline -TimeoutSeconds 3
            }
        } | Should -Throw -ExpectedMessage '*OFFLINE01*within 3 second(s)*'
        Should -Invoke -ModuleName ITToolkit Test-ITTcpPort -Times 1 -Exactly -ParameterFilter { $TimeoutSeconds -eq 3 }
        Should -Invoke -ModuleName ITToolkit New-CimSession -Times 0 -Exactly
    }

    It 'uses WSMan when port 5985 is open' {
        Mock -ModuleName ITToolkit Test-ITTcpPort { 5985 }

        $session = InModuleScope ITToolkit {
            $remote = 'SRV01'
            Open-ITCimSession -ComputerName $remote
        }

        $session | Should -Be 'wsman-session'
        Should -Invoke -ModuleName ITToolkit New-CimSession -Times 1 -Exactly -ParameterFilter {
            $ComputerName -eq 'SRV01' -and $null -eq $SessionOption -and $OperationTimeoutSec -eq 15
        }
    }

    It 'uses DCOM when only port 135 is open' {
        Mock -ModuleName ITToolkit Test-ITTcpPort { 135 }

        $session = InModuleScope ITToolkit {
            $remote = 'SRV02'
            Open-ITCimSession -ComputerName $remote
        }

        $session | Should -Be 'dcom-session'
        Should -Invoke -ModuleName ITToolkit New-CimSession -Times 1 -Exactly -ParameterFilter {
            $SessionOption -is [Microsoft.Management.Infrastructure.Options.DComSessionOptions]
        }
    }

    It 'falls back to DCOM when the WSMan session cannot be created' {
        Mock -ModuleName ITToolkit Test-ITTcpPort { 5985, 135 }
        Mock -ModuleName ITToolkit New-CimSession { throw 'Access denied' } -ParameterFilter { $null -eq $SessionOption }

        $session = InModuleScope ITToolkit {
            $remote = 'SRV03'
            Open-ITCimSession -ComputerName $remote
        }

        $session | Should -Be 'dcom-session'
    }

    It 'rethrows the WSMan error when DCOM is not reachable' {
        Mock -ModuleName ITToolkit Test-ITTcpPort { 5985 }
        Mock -ModuleName ITToolkit New-CimSession { throw 'Access denied' } -ParameterFilter { $null -eq $SessionOption }

        {
            InModuleScope ITToolkit {
                $remote = 'SRV04'
                Open-ITCimSession -ComputerName $remote
            }
        } | Should -Throw -ExpectedMessage '*Access denied*'
    }

    It 'passes credentials to remote sessions' {
        Mock -ModuleName ITToolkit Test-ITTcpPort { 5985 }
        $credential = [System.Management.Automation.PSCredential]::new('CONTOSO\auditor', [System.Security.SecureString]::new())

        InModuleScope ITToolkit -Parameters @{ Credential = $credential } {
            $remote = 'SRV05'
            $null = Open-ITCimSession -ComputerName $remote -Credential $Credential
        }

        Should -Invoke -ModuleName ITToolkit New-CimSession -Times 1 -Exactly -ParameterFilter {
            $Credential.UserName -eq 'CONTOSO\auditor'
        }
    }
}
