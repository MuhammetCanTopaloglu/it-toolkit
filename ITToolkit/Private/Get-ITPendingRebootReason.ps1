function Get-ITPendingRebootReason {
    <#
    .SYNOPSIS
        Returns the reasons why a computer is waiting for a restart, read from the registry over CIM (StdRegProv).

    .DESCRIPTION
        Possible values:
          ComponentBasedServicing      CBS\RebootPending key exists
          WindowsUpdate                WindowsUpdate\Auto Update\RebootRequired key exists
          PendingFileRenameOperations  Session Manager\PendingFileRenameOperations has entries
          ComputerRename               the active and the configured computer names differ
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [Microsoft.Management.Infrastructure.CimSession]$CimSession
    )

    $hklm = [uint32]2147483650
    $registry = @{
        CimSession  = $CimSession
        Namespace   = 'root/cimv2'
        ClassName   = 'StdRegProv'
        ErrorAction = 'Stop'
    }

    $cbs = Invoke-CimMethod @registry -MethodName EnumKey -Arguments @{
        hDefKey     = $hklm
        sSubKeyName = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'
    }
    if ($cbs.ReturnValue -eq 0 -and @($cbs.sNames) -contains 'RebootPending') {
        'ComponentBasedServicing'
    }

    $windowsUpdate = Invoke-CimMethod @registry -MethodName EnumKey -Arguments @{
        hDefKey     = $hklm
        sSubKeyName = 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update'
    }
    if ($windowsUpdate.ReturnValue -eq 0 -and @($windowsUpdate.sNames) -contains 'RebootRequired') {
        'WindowsUpdate'
    }

    $fileRename = Invoke-CimMethod @registry -MethodName GetMultiStringValue -Arguments @{
        hDefKey     = $hklm
        sSubKeyName = 'SYSTEM\CurrentControlSet\Control\Session Manager'
        sValueName  = 'PendingFileRenameOperations'
    }
    if ($fileRename.ReturnValue -eq 0 -and @($fileRename.sValue | Where-Object { $_ }).Count -gt 0) {
        'PendingFileRenameOperations'
    }

    $activeName = Invoke-CimMethod @registry -MethodName GetStringValue -Arguments @{
        hDefKey     = $hklm
        sSubKeyName = 'SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName'
        sValueName  = 'ComputerName'
    }
    $configuredName = Invoke-CimMethod @registry -MethodName GetStringValue -Arguments @{
        hDefKey     = $hklm
        sSubKeyName = 'SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName'
        sValueName  = 'ComputerName'
    }
    if ($activeName.ReturnValue -eq 0 -and $configuredName.ReturnValue -eq 0 -and
        $activeName.sValue -and $configuredName.sValue -and $activeName.sValue -ne $configuredName.sValue) {
        'ComputerRename'
    }
}
