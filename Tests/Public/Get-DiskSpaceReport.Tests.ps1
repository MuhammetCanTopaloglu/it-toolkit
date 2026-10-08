BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\Shared.ps1')
}

Describe 'Get-DiskSpaceReport' {
    BeforeAll {
        Mock -ModuleName ITToolkit Open-ITCimSession { New-MockObject -Type ([Microsoft.Management.Infrastructure.CimSession]) }
        Mock -ModuleName ITToolkit Remove-CimSession { }
        Mock -ModuleName ITToolkit Get-CimInstance {
            [pscustomobject]@{ DeviceID = 'C:'; VolumeName = 'System'; FileSystem = 'NTFS'; Size = 100GB; FreeSpace = 10GB }
            [pscustomobject]@{ DeviceID = 'D:'; VolumeName = 'Data'; FileSystem = 'NTFS'; Size = 200GB; FreeSpace = 150GB }
            [pscustomobject]@{ DeviceID = 'E:'; VolumeName = $null; FileSystem = $null; Size = $null; FreeSpace = $null }
        } -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' }
    }

    It 'queries only fixed disks' {
        $null = Get-DiskSpaceReport

        Should -Invoke -ModuleName ITToolkit Get-CimInstance -Times 1 -Exactly -ParameterFilter { $Filter -eq 'DriveType = 3' }
    }

    It 'calculates sizes and percentages' {
        $c = Get-DiskSpaceReport | Where-Object Drive -EQ 'C:'

        $c.SizeGB | Should -Be 100
        $c.FreeGB | Should -Be 10
        $c.FreePercent | Should -Be 10
        $c.UsedPercent | Should -Be 90
        $c.PSObject.TypeNames | Should -Contain 'ITToolkit.DiskSpace'
    }

    It 'flags disks below the default threshold of 15 percent' {
        $result = Get-DiskSpaceReport

        ($result | Where-Object Drive -EQ 'C:').BelowThreshold | Should -BeTrue
        ($result | Where-Object Drive -EQ 'D:').BelowThreshold | Should -BeFalse
    }

    It 'honours a custom threshold' {
        $result = Get-DiskSpaceReport -ThresholdPercent 80

        ($result | Where-Object Drive -EQ 'D:').BelowThreshold | Should -BeTrue
        ($result | Where-Object Drive -EQ 'D:').ThresholdPercent | Should -Be 80
    }

    It 'skips volumes without a size' {
        (Get-DiskSpaceReport).Drive | Should -Not -Contain 'E:'
    }

    It 'accepts computer names from the pipeline, including AD computer objects' {
        $result = @('SRV01', [pscustomobject]@{ DNSHostName = 'srv02.contoso.test' }) | Get-DiskSpaceReport

        ($result.ComputerName | Sort-Object -Unique) | Should -Be @('SRV01', 'srv02.contoso.test')
        Should -Invoke -ModuleName ITToolkit Open-ITCimSession -Times 2 -Exactly
    }

    It 'passes credential and timeout to the connection' {
        $credential = [System.Management.Automation.PSCredential]::new('CONTOSO\auditor', [System.Security.SecureString]::new())
        $server = 'SRV01'

        $null = Get-DiskSpaceReport -ComputerName $server -Credential $credential -TimeoutSeconds 5

        Should -Invoke -ModuleName ITToolkit Open-ITCimSession -Times 1 -Exactly -ParameterFilter {
            $ComputerName -eq 'SRV01' -and $TimeoutSeconds -eq 5 -and $Credential.UserName -eq 'CONTOSO\auditor'
        }
    }

    It 'always closes the CIM session' {
        $null = Get-DiskSpaceReport -ComputerName 'SRV01', 'SRV02'

        Should -Invoke -ModuleName ITToolkit Remove-CimSession -Times 2 -Exactly
    }

    It 'reports an unreachable computer as a non-terminating error and continues' {
        Mock -ModuleName ITToolkit Open-ITCimSession { throw 'did not respond' } -ParameterFilter { $ComputerName -eq 'OFFLINE01' }

        $output = Get-DiskSpaceReport -ComputerName 'OFFLINE01', 'SRV01' 2>&1
        $failures = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        $result = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

        $failures.Count | Should -Be 1
        $failures[0].FullyQualifiedErrorId | Should -BeLike 'DiskQueryFailed*'
        $failures[0].TargetObject | Should -Be 'OFFLINE01'
        $failures[0].Exception.Message | Should -Match 'did not respond'
        $result.ComputerName | Should -Contain 'SRV01'
        $result.ComputerName | Should -Not -Contain 'OFFLINE01'
    }
}
