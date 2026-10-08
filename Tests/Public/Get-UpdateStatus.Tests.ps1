BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\Shared.ps1')

    # A real local CIM session (DCOM, no WinRM needed) instead of an uninitialised mock object;
    # every CIM query is still mocked.
    $script:TestCimSession = New-CimSession -ErrorAction Stop
}

Describe 'Get-UpdateStatus' {
    BeforeAll {
        Mock -ModuleName ITToolkit Open-ITCimSession { $script:TestCimSession }
        Mock -ModuleName ITToolkit Remove-CimSession { }
        Mock -ModuleName ITToolkit Get-ITPendingRebootReason { }
        Mock -ModuleName ITToolkit Get-CimInstance {
            [pscustomobject]@{ HotFixID = 'KB5000001'; InstalledOn = (Get-Date).Date.AddDays(-40) }
            [pscustomobject]@{ HotFixID = 'KB5000003'; InstalledOn = (Get-Date).Date.AddDays(-3) }
            [pscustomobject]@{ HotFixID = 'KB5000002'; InstalledOn = (Get-Date).Date.AddDays(-10) }
            [pscustomobject]@{ HotFixID = 'KB0000000'; InstalledOn = $null }
        } -ParameterFilter { $ClassName -eq 'Win32_QuickFixEngineering' }
    }

    It 'reports the most recent update' {
        $result = Get-UpdateStatus

        $result.LastHotFixId | Should -Be 'KB5000003'
        $result.LastUpdateInstalled | Should -Be (Get-Date).Date.AddDays(-3)
        $result.DaysSinceLastUpdate | Should -Be 3
        $result.HotFixCount | Should -Be 4
        $result.PSObject.TypeNames | Should -Contain 'ITToolkit.UpdateStatus'
    }

    It 'parses dates that arrive as text' {
        Mock -ModuleName ITToolkit Get-CimInstance {
            [pscustomobject]@{ HotFixID = 'KB1'; InstalledOn = '1/15/2026' }
            [pscustomobject]@{ HotFixID = 'KB2'; InstalledOn = 'not a date' }
        } -ParameterFilter { $ClassName -eq 'Win32_QuickFixEngineering' }

        $result = Get-UpdateStatus

        $result.LastHotFixId | Should -Be 'KB1'
        $result.LastUpdateInstalled | Should -Be ([datetime]'2026-01-15')
    }

    It 'returns empty values when no update has an installation date' {
        Mock -ModuleName ITToolkit Get-CimInstance { } -ParameterFilter { $ClassName -eq 'Win32_QuickFixEngineering' }

        $result = Get-UpdateStatus

        $result.LastUpdateInstalled | Should -BeNullOrEmpty
        $result.DaysSinceLastUpdate | Should -BeNullOrEmpty
        $result.HotFixCount | Should -Be 0
    }

    It 'reports no pending reboot when no indicator is set' {
        $result = Get-UpdateStatus

        $result.PendingReboot | Should -BeFalse
        $result.PendingRebootReason | Should -BeNullOrEmpty
    }

    It 'reports a pending reboot with its reasons' {
        Mock -ModuleName ITToolkit Get-ITPendingRebootReason { 'WindowsUpdate'; 'ComputerRename' }

        $result = Get-UpdateStatus

        $result.PendingReboot | Should -BeTrue
        $result.PendingRebootReason | Should -Be @('WindowsUpdate', 'ComputerRename')
    }

    It 'processes every computer from the pipeline' {
        $result = @('SRV01', 'SRV02') | Get-UpdateStatus

        $result.ComputerName | Should -Be @('SRV01', 'SRV02')
        Should -Invoke -ModuleName ITToolkit Remove-CimSession -Times 2 -Exactly
    }

    It 'reports an unreachable computer as a non-terminating error and continues' {
        Mock -ModuleName ITToolkit Open-ITCimSession { throw 'did not respond' } -ParameterFilter { $ComputerName -eq 'OFFLINE01' }

        $output = Get-UpdateStatus -ComputerName 'OFFLINE01', 'SRV01' -ErrorAction Continue 2>&1
        $failures = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

        $failures.Count | Should -Be 1
        $failures[0].FullyQualifiedErrorId | Should -BeLike 'UpdateStatusQueryFailed*'
        @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).ComputerName | Should -Be 'SRV01'
    }
}

Describe 'Get-ITPendingRebootReason' {
    BeforeAll {
        $script:session = $script:TestCimSession

        # Default: a clean computer with no pending restart indicators.
        Mock -ModuleName ITToolkit Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; sNames = @('Packages', 'SessionsPending') } } -ParameterFilter { $MethodName -eq 'EnumKey' }
        Mock -ModuleName ITToolkit Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 1; sValue = $null } } -ParameterFilter { $MethodName -eq 'GetMultiStringValue' }
        Mock -ModuleName ITToolkit Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; sValue = 'SRV01' } } -ParameterFilter { $MethodName -eq 'GetStringValue' }
    }

    It 'returns nothing for a clean computer' {
        InModuleScope ITToolkit -Parameters @{ Session = $script:session } {
            Get-ITPendingRebootReason -CimSession $Session | Should -BeNullOrEmpty
        }
    }

    It 'detects a pending Component Based Servicing restart' {
        Mock -ModuleName ITToolkit Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; sNames = @('Packages', 'RebootPending') } } -ParameterFilter {
            $MethodName -eq 'EnumKey' -and $Arguments.sSubKeyName -like '*Component Based Servicing'
        }

        InModuleScope ITToolkit -Parameters @{ Session = $script:session } {
            Get-ITPendingRebootReason -CimSession $Session | Should -Be 'ComponentBasedServicing'
        }
    }

    It 'detects a Windows Update restart request' {
        Mock -ModuleName ITToolkit Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; sNames = @('RebootRequired') } } -ParameterFilter {
            $MethodName -eq 'EnumKey' -and $Arguments.sSubKeyName -like '*WindowsUpdate\Auto Update'
        }

        InModuleScope ITToolkit -Parameters @{ Session = $script:session } {
            Get-ITPendingRebootReason -CimSession $Session | Should -Be 'WindowsUpdate'
        }
    }

    It 'detects pending file rename operations' {
        Mock -ModuleName ITToolkit Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; sValue = @('\??\C:\temp\a.dll', '') } } -ParameterFilter {
            $MethodName -eq 'GetMultiStringValue'
        }

        InModuleScope ITToolkit -Parameters @{ Session = $script:session } {
            Get-ITPendingRebootReason -CimSession $Session | Should -Be 'PendingFileRenameOperations'
        }
    }

    It 'ignores an empty PendingFileRenameOperations value' {
        Mock -ModuleName ITToolkit Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; sValue = @('') } } -ParameterFilter {
            $MethodName -eq 'GetMultiStringValue'
        }

        InModuleScope ITToolkit -Parameters @{ Session = $script:session } {
            Get-ITPendingRebootReason -CimSession $Session | Should -BeNullOrEmpty
        }
    }

    It 'detects a pending computer rename' {
        Mock -ModuleName ITToolkit Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; sValue = 'SRV01-NEW' } } -ParameterFilter {
            $MethodName -eq 'GetStringValue' -and $Arguments.sSubKeyName -like '*\ComputerName\ComputerName'
        }

        InModuleScope ITToolkit -Parameters @{ Session = $script:session } {
            Get-ITPendingRebootReason -CimSession $Session | Should -Be 'ComputerRename'
        }
    }

    It 'reads the registry through StdRegProv on HKEY_LOCAL_MACHINE' {
        InModuleScope ITToolkit -Parameters @{ Session = $script:session } {
            $null = Get-ITPendingRebootReason -CimSession $Session
        }

        Should -Invoke -ModuleName ITToolkit Invoke-CimMethod -Times 5 -Exactly -ParameterFilter {
            $ClassName -eq 'StdRegProv' -and $Arguments.hDefKey -eq [uint32]2147483650
        }
    }
}

AfterAll {
    Remove-CimSession -CimSession $script:TestCimSession -ErrorAction SilentlyContinue
}
