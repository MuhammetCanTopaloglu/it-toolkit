@{
    RootModule           = 'ITToolkit.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'c9cede3e-b39c-4b1e-b817-51e9c138cae5'
    Author               = 'Muhammet Can Topaloğlu'
    Copyright            = '(c) 2026 Muhammet Can Topaloğlu. Released under the MIT License.'
    Description          = 'Sysadmin toolkit for Windows and Active Directory: disk, update, local admin, inventory, certificate, stale account and password expiry reports, plus a safe offboarding command. Remote computers are queried over CIM.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'Export-ITReport'
        'Get-DiskSpaceReport'
        'Get-ExpiringCertificate'
        'Get-LocalAdminAudit'
        'Get-StaleADAccount'
        'Get-SystemInventory'
        'Get-UpdateStatus'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('Windows', 'ActiveDirectory', 'SysAdmin', 'Inventory', 'Audit', 'Report', 'CIM', 'PSEdition_Desktop', 'PSEdition_Core')
            LicenseUri   = 'https://github.com/MuhammetCanTopaloglu/it-toolkit/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/MuhammetCanTopaloglu/it-toolkit'
            ReleaseNotes = 'https://github.com/MuhammetCanTopaloglu/it-toolkit/blob/main/CHANGELOG.md'
        }
    }
}
