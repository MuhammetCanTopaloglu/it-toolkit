# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-08

### Added

- `Get-DiskSpaceReport`: fixed disk usage with a free space threshold flag.
- `Get-UpdateStatus`: last installed update and pending restart state with reasons.
- `Get-LocalAdminAudit`: local Administrators members, orphaned SID detection and an approved member list.
- `Get-SystemInventory`: model, serial number, OS, CPU, memory and uptime.
- `Get-ExpiringCertificate`: LocalMachine certificates that expire within N days.
- `Get-StaleADAccount`: AD users and computers without a logon for N days.
- `Get-PasswordExpiryReport`: AD users whose password expires within N days or must be changed at next logon.
- `Disable-DepartingUser`: offboarding with group backup, `-WhatIf`/`-Confirm` support and an action log.
- `Export-ITReport`: CSV and HTML export for every command.
- Pester 5 tests, PSScriptAnalyzer settings and a GitHub Actions workflow for Windows PowerShell 5.1 and PowerShell 7.
