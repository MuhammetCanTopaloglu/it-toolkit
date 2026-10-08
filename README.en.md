# it-toolkit

[![CI](https://github.com/MuhammetCanTopaloglu/it-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/MuhammetCanTopaloglu/it-toolkit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

English | **[Türkçe](README.md)**

A sysadmin toolkit for Windows and Active Directory environments. `ITToolkit` is a PowerShell module that works with Windows PowerShell 5.1 and PowerShell 7.

- Every command returns objects. Filter them with `Where-Object` or `Sort-Object`, or turn them into a CSV or HTML report with `Export-ITReport`.
- Remote computers are queried over **CIM** (WSMan first, DCOM as fallback). The WMI cmdlets are not used.
- An unreachable computer does not hold up a report. It fails after `-TimeoutSeconds` (default 15) and the next computer is processed.
- Nothing is specific to one organization. OUs, thresholds, paths and servers are all parameters.
- Every command has comment-based help with examples (`Get-Help`).

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Common parameters](#common-parameters)
- [Commands](#commands)
  - [Get-DiskSpaceReport](#get-diskspacereport)
  - [Get-UpdateStatus](#get-updatestatus)
  - [Get-LocalAdminAudit](#get-localadminaudit)
  - [Get-SystemInventory](#get-systeminventory)
  - [Get-ExpiringCertificate](#get-expiringcertificate)
  - [Get-StaleADAccount](#get-staleadaccount)
  - [Get-PasswordExpiryReport](#get-passwordexpiryreport)
  - [Disable-DepartingUser](#disable-departinguser)
  - [Export-ITReport](#export-itreport)
- [-WhatIf and -Confirm](#-whatif-and--confirm)
- [Tests and code quality](#tests-and-code-quality)
- [License](#license)

## Requirements

| Requirement | Needed for |
|---|---|
| Windows PowerShell 5.1 or PowerShell 7.x (on Windows) | All commands |
| WinRM (TCP 5985) **or** DCOM/RPC (TCP 135) plus WMI firewall rules on the remote computer | Remote queries with `-ComputerName` |
| PowerShell remoting (WinRM) on the remote computer | Remote `Get-ExpiringCertificate` only |
| Local administrator rights on the remote computer | Remote CIM queries |
| ActiveDirectory module (RSAT) | `Get-StaleADAccount`, `Get-PasswordExpiryReport`, `Disable-DepartingUser` |
| Rights to modify and move users and groups in AD | `Disable-DepartingUser` |

When the ActiveDirectory module is missing, the AD commands stop with an error that explains how to install it:

```powershell
# Windows 10/11
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
# Windows Server
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

## Installation

```powershell
git clone https://github.com/MuhammetCanTopaloglu/it-toolkit.git
Import-Module .\it-toolkit\ITToolkit\ITToolkit.psd1
Get-Command -Module ITToolkit
```

To load the module by name in every session, copy the `ITToolkit` folder into a module path:

```powershell
# Windows PowerShell 5.1: Documents\WindowsPowerShell\Modules
# PowerShell 7:           Documents\PowerShell\Modules
Copy-Item -Recurse .\it-toolkit\ITToolkit "$HOME\Documents\WindowsPowerShell\Modules\ITToolkit"
Import-Module ITToolkit
```

If you downloaded a ZIP file, unblock the files first so the execution policy does not block them:

```powershell
Get-ChildItem -Recurse .\it-toolkit | Unblock-File
```

## Common parameters

Every command that queries computers (`Get-DiskSpaceReport`, `Get-UpdateStatus`, `Get-LocalAdminAudit`, `Get-SystemInventory`, `Get-ExpiringCertificate`) has these parameters:

| Parameter | Description |
|---|---|
| `-ComputerName` | Defaults to the local computer. Accepts strings from the pipeline, and objects with a `ComputerName`, `DNSHostName` or `Name` property (for example `Get-ADComputer` output). |
| `-Credential` | Credentials for remote computers. Ignored for the local computer. |
| `-TimeoutSeconds` | How long to wait for a computer to respond (default 15). The ports are probed with this timeout before connecting, so an offline computer does not hold up the report. |

The local computer is queried without WinRM. An unreachable computer produces a *non-terminating* error and the remaining computers are still processed:

```powershell
$output  = Get-Content .\servers.txt | Get-SystemInventory -TimeoutSeconds 5 2>&1
$results = $output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
$offline = ($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).TargetObject   # unreachable computers
```

The AD commands take `-Server` (a domain controller) and `-Credential` instead of `-ComputerName`.

## Commands

> The outputs below are examples. Computer, user and domain names are illustrative.

### Get-DiskSpaceReport

Reports size, free space and usage of fixed disks. Disks whose free space is below `-ThresholdPercent` (default 15) are flagged with `BelowThreshold`.

```powershell
Get-DiskSpaceReport -ComputerName SRV01, SRV02 | Format-Table
```

```text
ComputerName Drive VolumeName FileSystem SizeGB FreeGB UsedPercent FreePercent ThresholdPercent BelowThreshold
------------ ----- ---------- ---------- ------ ------ ----------- ----------- ---------------- --------------
SRV01        C:    System     NTFS       126.45  48.12       61.94       38.06               15          False
SRV01        D:    Data       NTFS       511.87  37.40       92.69        7.31               15           True
SRV02        C:    System     NTFS       126.45  71.03       43.83       56.17               15          False
```

```powershell
# Every server in AD, only disks with less than 10 percent free space
Get-ADComputer -Filter 'OperatingSystem -like "*Server*"' |
    Get-DiskSpaceReport -ThresholdPercent 10 |
    Where-Object BelowThreshold
```

### Get-UpdateStatus

Shows the date and KB number of the most recently installed update, how many days ago that was, and whether the computer is waiting for a restart. The pending restart state is read from four sources: Component Based Servicing, Windows Update, PendingFileRenameOperations and a pending computer rename. The registry is read over CIM (`StdRegProv`), so the Remote Registry service is not needed.

```powershell
Get-UpdateStatus -ComputerName SRV01
```

```text
ComputerName        : SRV01
LastUpdateInstalled : 9/15/2026 12:00:00 AM
LastHotFixId        : KB5065432
DaysSinceLastUpdate : 23
HotFixCount         : 6
PendingReboot       : True
PendingRebootReason : {WindowsUpdate, PendingFileRenameOperations}
```

```powershell
# Servers waiting for a restart
Get-Content .\servers.txt | Get-UpdateStatus | Where-Object PendingReboot

# Computers without an update for more than 45 days
Get-Content .\servers.txt | Get-UpdateStatus | Where-Object DaysSinceLastUpdate -GT 45
```

> `Win32_QuickFixEngineering` lists cumulative and security updates. Defender definition updates and Store app updates are not included.

### Get-LocalAdminAudit

Lists the members of the local Administrators group. The group is found by its well-known SID (`S-1-5-32-544`) rather than by name, so it also works on localized Windows where the group has a translated name (for example "Yöneticiler" on Turkish Windows).

- **SIDs of deleted accounts that can no longer be resolved do not cause an error.** They are reported with `IsOrphaned = True` so they can be cleaned up.
- With `-ExpectedMember` (wildcards and SIDs allowed), `IsExpected` shows which administrators are not on the approved list.

```powershell
Get-LocalAdminAudit -ComputerName SRV01 -ExpectedMember '*\Administrator', 'CONTOSO\Domain Admins' |
    Format-Table Member, MemberType, IsLocal, IsOrphaned, IsExpected
```

```text
Member                                                 MemberType IsLocal IsOrphaned IsExpected
------                                                 ---------- ------- ---------- ----------
SRV01\Administrator                                    User          True      False       True
CONTOSO\Domain Admins                                  Group        False      False       True
CONTOSO\helpdesk-t1                                    Group        False      False      False
CONTOSO\S-1-5-21-1004336348-1177238915-682003330-4242  Unknown                  True      False
```

```powershell
# Find orphaned SIDs on every server in an OU and export them to CSV
Get-ADComputer -Filter * -SearchBase 'OU=Servers,DC=contoso,DC=com' |
    Get-LocalAdminAudit |
    Where-Object IsOrphaned |
    Export-ITReport -Path .\orphaned-admins.csv
```

### Get-SystemInventory

Combines operating system, CPU, memory, serial number, model and uptime into one object. Uptime is calculated from the remote computer's own clock.

```powershell
Get-SystemInventory -ComputerName SRV01
```

```text
ComputerName          : SRV01
Manufacturer          : Dell Inc.
Model                 : PowerEdge R650
SerialNumber          : 7XK2Q93
BiosVersion           : 1.14.1
Domain                : contoso.com
OperatingSystem       : Microsoft Windows Server 2022 Standard
OSVersion             : 10.0.20348
OSBuild               : 20348
OSArchitecture        : 64-bit
Processor             : Intel(R) Xeon(R) Gold 6338 CPU @ 2.00GHz
ProcessorCount        : 2
CoreCount             : 64
LogicalProcessorCount : 128
TotalMemoryGB         : 255.62
InstallDate           : 1/10/2024 8:00:00 AM
LastBootTime          : 9/22/2026 7:58:32 AM
Uptime                : 16.01:23:26.6161540
UptimeDays            : 16.1
```

```powershell
Get-Content .\servers.txt | Get-SystemInventory |
    Select-Object ComputerName, Model, SerialNumber, TotalMemoryGB, UptimeDays |
    Export-ITReport -Path .\inventory.csv
```

### Get-ExpiringCertificate

Finds certificates in the LocalMachine certificate stores that expire within `-Days` days (default 30). The default store is `My` (Personal). Certificates that have already expired are only returned with `-IncludeExpired`.

> Certificate stores cannot be read through CIM. The local computer is read directly; remote computers are read with `Invoke-Command` (PowerShell remoting).

```powershell
Get-ExpiringCertificate -ComputerName WEB01 -Days 60 -StoreName My, WebHosting |
    Format-Table ComputerName, Store, Subject, NotAfter, DaysRemaining, HasPrivateKey
```

```text
ComputerName Store                     Subject                   NotAfter               DaysRemaining HasPrivateKey
------------ -----                     -------                   --------               ------------- -------------
WEB01        LocalMachine\My           CN=intranet.contoso.com   10/21/2026 2:00:00 PM             13          True
WEB01        LocalMachine\WebHosting   CN=api.contoso.com        11/30/2026 9:30:00 AM             52          True
```

### Get-StaleADAccount

Finds AD user and computer accounts that have not logged on for `-Days` days (default 90). Accounts that never logged on are reported only if they were created before that date, so new accounts are not flagged. Disabled accounts are only returned with `-IncludeDisabled`.

```powershell
Get-StaleADAccount -Days 120 |
    Format-Table SamAccountName, ObjectClass, LastLogonDate, DaysSinceLastLogon, NeverLoggedOn
```

```text
SamAccountName ObjectClass LastLogonDate          DaysSinceLastLogon NeverLoggedOn
-------------- ----------- -------------          ------------------ -------------
ayilmaz        user        5/2/2026 8:14:51 AM                   159         False
temp.intern    user                                                           True
WS-0142$       computer    3/11/2026 5:40:02 PM                  210         False
```

```powershell
# Specific OUs; every OU from the pipeline is searched
Get-ADOrganizationalUnit -Filter 'Name -like "Branch*"' | Get-StaleADAccount -AccountType Computer -Days 180
```

> The last logon comes from `lastLogonTimestamp`. It replicates to every DC but can lag by 9-14 days, so thresholds below 14 days are not meaningful.

### Get-PasswordExpiryReport

Lists AD users whose password expires within `-Days` days (default 14). The expiry time comes from `msDS-UserPasswordExpiryTimeComputed`, so fine-grained password policies (PSOs) are honoured. Special values are handled separately:

| Value | Meaning | In the report |
|---|---|---|
| `0` | The user must change the password at next logon | Always listed, `Status = MustChangePassword` |
| `9223372036854775807` (max Int64) | The password never expires | Not listed |
| A date in the past | The password has expired | Listed only with `-IncludeExpired`, `Status = Expired` |
| A date within `-Days` | Expires soon | `Status = Expiring` |

```powershell
Get-PasswordExpiryReport -Days 14 |
    Format-Table SamAccountName, EmailAddress, PasswordExpires, DaysUntilExpiry, Status
```

```text
SamAccountName EmailAddress          PasswordExpires         DaysUntilExpiry Status
-------------- ------------          ---------------         --------------- ------
mkaya          mkaya@contoso.com     10/12/2026 9:12:44 AM                 4 Expiring
edemir         edemir@contoso.com    10/19/2026 4:03:10 PM                11 Expiring
new.hire       new.hire@contoso.com                                          MustChangePassword
```

### Disable-DepartingUser

Offboards a departing user by performing these steps **in this order**:

1. Writes the user's group memberships (`memberOf`) to a CSV file in `-BackupDirectory`. **If the backup cannot be written, the user is not changed at all.**
2. Removes the user from those groups. The primary group (usually Domain Users) is not part of `memberOf` and is kept.
3. Disables the account.
4. Prefixes the description with the date: `Disabled 2026-10-08 - <previous description>`. The prefix can be changed with `-DescriptionPrefix`.
5. Moves the account to `-TargetOU`, if given. The OU is validated before any user is changed.

Every executed action and every failure is logged together with the time, the operator and the target account. The default log file is `-BackupDirectory\Disable-DepartingUser.log`; use `-LogPath` to change it. The steps can safely be run again: an already disabled account is not disabled again, the date is not written twice on the same day, and an account already in the target OU is not moved.

```powershell
Disable-DepartingUser -Identity jdoe -BackupDirectory D:\Offboarding -TargetOU 'OU=Disabled Users,DC=contoso,DC=com'
```

Example result object:

```text
SamAccountName     : jdoe
DistinguishedName  : CN=John Doe,OU=Sales,DC=contoso,DC=com
Status             : Completed
Disabled           : True
DescriptionUpdated : True
GroupsRemoved      : {CN=Sales,OU=Groups,DC=contoso,DC=com, CN=VPN Users,OU=Groups,DC=contoso,DC=com}
GroupsFailed       : {}
MovedTo            : OU=Disabled Users,DC=contoso,DC=com
BackupFile         : D:\Offboarding\jdoe_groups_20261008-093748.csv
LogFile            : D:\Offboarding\Disable-DepartingUser.log
Errors             : {}
```

Example log:

```text
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Processing started. DN: CN=John Doe,OU=Sales,DC=contoso,DC=com; enabled: True; groups: 2.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Backed up 2 group membership(s) to 'D:\Offboarding\jdoe_groups_20261008-093748.csv'.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Removed from group 'CN=Sales,OU=Groups,DC=contoso,DC=com'.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Removed from group 'CN=VPN Users,OU=Groups,DC=contoso,DC=com'.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Account disabled.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Description changed from 'Sales representative' to 'Disabled 2026-10-08 - Sales representative'.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Moved from 'OU=Sales,DC=contoso,DC=com' to 'OU=Disabled Users,DC=contoso,DC=com'.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Processing finished: Completed.
```

If a step fails (for example, missing rights to remove a member from one group), the failure is logged and written to the error stream. The remaining steps still run, and `Status` becomes `CompletedWithErrors`. Because the backup is a CSV file, memberships can be restored if needed:

```powershell
Import-Csv D:\Offboarding\jdoe_groups_20261008-093748.csv |
    ForEach-Object { Add-ADGroupMember -Identity $_.GroupDistinguishedName -Members $_.SamAccountName }
```

### Export-ITReport

Exports the output of any command to CSV or to a single-file HTML report. The format is taken from the file extension, or set with `-Format`.

- CSV files are written as UTF-8 with a BOM, so non-ASCII characters display correctly in Excel. Use `-Delimiter ';'` where Excel's list separator is a semicolon.
- In HTML reports, rows where the `-HighlightProperty` value is `True` are highlighted.
- Collections are joined with `; ` and dates are written as `yyyy-MM-dd HH:mm:ss`.

```powershell
Get-DiskSpaceReport -ComputerName SRV01, SRV02 |
    Export-ITReport -Path .\disks.html -Title 'Disk usage' -HighlightProperty BelowThreshold

Get-PasswordExpiryReport -Days 7 |
    Export-ITReport -Path .\password-expiry.csv -Property SamAccountName, EmailAddress, PasswordExpires, Status
```

## -WhatIf and -Confirm

`Disable-DepartingUser` is the only command that makes changes, and it supports `SupportsShouldProcess` (ConfirmImpact = High):

- **`-WhatIf`**: changes nothing and writes no file (neither the backup nor the log). It only shows every step that would run.
- **Default behaviour**: asks for confirmation before each change. Answer "Yes to All" (`A`) to confirm the remaining steps.
- **`-Confirm:$false`**: runs without prompting, for scripts.

```powershell
Disable-DepartingUser -Identity jdoe -BackupDirectory D:\Offboarding -TargetOU 'OU=Disabled Users,DC=contoso,DC=com' -WhatIf
```

```text
What if: Performing the operation "Back up 2 group membership(s) of 'jdoe'" on target "D:\Offboarding\jdoe_groups_20261008-093748.csv".
What if: Performing the operation "Remove 'jdoe' from group" on target "CN=Sales,OU=Groups,DC=contoso,DC=com".
What if: Performing the operation "Remove 'jdoe' from group" on target "CN=VPN Users,OU=Groups,DC=contoso,DC=com".
What if: Performing the operation "Disable account" on target "jdoe".
What if: Performing the operation "Set description to 'Disabled 2026-10-08 - Sales representative'" on target "jdoe".
What if: Performing the operation "Move to 'OU=Disabled Users,DC=contoso,DC=com'" on target "jdoe".
```

To offboard everyone in a CSV list, check with `-WhatIf` first, then run without prompts:

```powershell
$leavers = Import-Csv .\leavers.csv   # SamAccountName column
$leavers | Disable-DepartingUser -BackupDirectory D:\Offboarding -TargetOU 'OU=Disabled Users,DC=contoso,DC=com' -WhatIf
$leavers | Disable-DepartingUser -BackupDirectory D:\Offboarding -TargetOU 'OU=Disabled Users,DC=contoso,DC=com' -Confirm:$false
```

`Export-ITReport` also supports `-WhatIf`.

## Tests and code quality

- **Pester 5** tests mock every CIM, Active Directory and remoting call. No real server, Active Directory or RSAT is required.
- **PSScriptAnalyzer** scans every script in the repository with `PSScriptAnalyzerSettings.psd1`. A single finding fails the build.
- **GitHub Actions** runs the analysis and the tests on Windows PowerShell 5.1 and PowerShell 7 for every push and pull request.

To run them locally:

```powershell
./build.ps1                    # Bootstrap + Analyze + Test
./build.ps1 -Task Analyze      # PSScriptAnalyzer only
./build.ps1 -Task Test         # Pester only (results are written to TestResults\)
```

Repository layout:

```text
ITToolkit/
  ITToolkit.psd1, ITToolkit.psm1
  Public/      exported commands (one file per command)
  Private/     helpers (CIM connection, logging, AD module check...)
Tests/         Pester tests and AD cmdlet stubs
build.ps1      bootstrap / analyze / test
```

## License

[MIT](LICENSE) © 2026 Muhammet Can Topaloğlu
