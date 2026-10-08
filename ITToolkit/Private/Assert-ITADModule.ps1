function Assert-ITADModule {
    <#
    .SYNOPSIS
        Imports the ActiveDirectory module or throws an error that explains how to install it.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (Get-Module -Name ActiveDirectory) {
        return
    }

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        $message = @(
            'The ActiveDirectory PowerShell module is required but is not installed.'
            'Install the Remote Server Administration Tools (RSAT) for Active Directory:'
            '  Windows 10/11:  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
            '  Windows Server: Install-WindowsFeature -Name RSAT-AD-PowerShell'
        ) -join [Environment]::NewLine

        throw [System.Management.Automation.ErrorRecord]::new(
            [System.IO.FileNotFoundException]::new($message),
            'ActiveDirectoryModuleNotFound',
            [System.Management.Automation.ErrorCategory]::NotInstalled,
            'ActiveDirectory')
    }

    Import-Module -Name ActiveDirectory -ErrorAction Stop -Verbose:$false
}
