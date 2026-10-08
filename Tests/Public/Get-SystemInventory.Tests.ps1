BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\Shared.ps1')
}

Describe 'Get-SystemInventory' {
    BeforeAll {
        Mock -ModuleName ITToolkit Open-ITCimSession { New-MockObject -Type ([Microsoft.Management.Infrastructure.CimSession]) }
        Mock -ModuleName ITToolkit Remove-CimSession { }

        Mock -ModuleName ITToolkit Get-CimInstance {
            [pscustomobject]@{ Manufacturer = 'Contoso Hardware'; Model = 'CH-2000'; Domain = 'contoso.test'; TotalPhysicalMemory = 34359738368 }
        } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        Mock -ModuleName ITToolkit Get-CimInstance {
            [pscustomobject]@{ SerialNumber = '  ABC1234  '; SMBIOSBIOSVersion = '1.20.0' }
        } -ParameterFilter { $ClassName -eq 'Win32_BIOS' }
        Mock -ModuleName ITToolkit Get-CimInstance {
            [pscustomobject]@{
                Caption        = 'Microsoft Windows Server 2022 Standard'
                Version        = '10.0.20348'
                BuildNumber    = '20348'
                OSArchitecture = '64-bit'
                InstallDate    = [datetime]'2024-01-10T08:00:00'
                LastBootUpTime = [datetime]'2026-10-01T06:00:00'
                LocalDateTime  = [datetime]'2026-10-08T18:00:00'
            }
        } -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }
        Mock -ModuleName ITToolkit Get-CimInstance {
            [pscustomobject]@{ Name = 'Contoso CPU 3.0GHz  '; NumberOfCores = 8; NumberOfLogicalProcessors = 16 }
            [pscustomobject]@{ Name = 'Contoso CPU 3.0GHz'; NumberOfCores = 8; NumberOfLogicalProcessors = 16 }
        } -ParameterFilter { $ClassName -eq 'Win32_Processor' }
    }

    It 'combines hardware and operating system details' {
        $result = Get-SystemInventory

        $result.Manufacturer | Should -Be 'Contoso Hardware'
        $result.Model | Should -Be 'CH-2000'
        $result.SerialNumber | Should -Be 'ABC1234'
        $result.BiosVersion | Should -Be '1.20.0'
        $result.Domain | Should -Be 'contoso.test'
        $result.OperatingSystem | Should -Be 'Microsoft Windows Server 2022 Standard'
        $result.OSBuild | Should -Be '20348'
        $result.OSArchitecture | Should -Be '64-bit'
        $result.PSObject.TypeNames | Should -Contain 'ITToolkit.SystemInventory'
    }

    It 'sums processor sockets, cores and logical processors' {
        $result = Get-SystemInventory

        $result.Processor | Should -Be 'Contoso CPU 3.0GHz'
        $result.ProcessorCount | Should -Be 2
        $result.CoreCount | Should -Be 16
        $result.LogicalProcessorCount | Should -Be 32
    }

    It 'reports memory in GB' {
        (Get-SystemInventory).TotalMemoryGB | Should -Be 32
    }

    It 'calculates uptime from the remote clock' {
        $result = Get-SystemInventory

        $result.LastBootTime | Should -Be ([datetime]'2026-10-01T06:00:00')
        $result.Uptime | Should -Be ([timespan]::FromHours(7 * 24 + 12))
        $result.UptimeDays | Should -Be 7.5
    }

    It 'processes every computer from the pipeline and closes each session' {
        $result = @('SRV01', 'SRV02') | Get-SystemInventory

        $result.ComputerName | Should -Be @('SRV01', 'SRV02')
        Should -Invoke -ModuleName ITToolkit Remove-CimSession -Times 2 -Exactly
    }

    It 'reports an unreachable computer as a non-terminating error and continues' {
        Mock -ModuleName ITToolkit Open-ITCimSession { throw 'did not respond' } -ParameterFilter { $ComputerName -eq 'OFFLINE01' }

        $output = Get-SystemInventory -ComputerName 'OFFLINE01', 'SRV01' 2>&1
        $failures = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

        $failures.Count | Should -Be 1
        $failures[0].FullyQualifiedErrorId | Should -BeLike 'InventoryQueryFailed*'
        @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).ComputerName | Should -Be 'SRV01'
    }
}
