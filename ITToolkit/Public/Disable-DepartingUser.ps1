function Disable-DepartingUser {
    <#
    .SYNOPSIS
        Offboards a departing Active Directory user: backs up and removes group memberships, disables the account, stamps the description and moves it to an OU.

    .DESCRIPTION
        Disable-DepartingUser performs these steps for every user, in this order:

          1. Writes the user's group memberships (memberOf) to a CSV file in -BackupDirectory.
             If the backup cannot be written, the user is not changed at all.
          2. Removes the user from each of those groups. The primary group (usually Domain Users)
             is not part of memberOf and is kept.
          3. Disables the account (skipped if it is already disabled).
          4. Sets the description to "<DescriptionPrefix> yyyy-MM-dd - <previous description>"
             (skipped if it already carries today's stamp).
          5. Moves the account to -TargetOU, if specified.

        Every step supports -WhatIf and -Confirm. The command has a high confirm impact, so it asks for
        confirmation by default; use -Confirm:$false in scripts. With -WhatIf nothing is changed and no
        file is written: neither the backup nor the log.

        Every executed action, and every failure, is written to the log file together with the time,
        the operator and the target account. A failure in one step is logged and reported, and the
        remaining steps still run (except for a failed backup, which stops the user).

        Requires the ActiveDirectory module (RSAT). If it is missing, a terminating error explains how
        to install it.

    .PARAMETER Identity
        The users to offboard: sAMAccountName, distinguished name, GUID or SID. Accepts pipeline input,
        including objects with a SamAccountName property (for example from Get-ADUser or Get-StaleADAccount).

    .PARAMETER BackupDirectory
        Folder for the group membership backups (<sAMAccountName>_groups_<yyyyMMdd-HHmmss>.csv).
        It is created when needed.

    .PARAMETER TargetOU
        Distinguished name of the OU or container the account is moved to. Its existence is checked
        before any user is changed. When omitted, the account is not moved.

    .PARAMETER LogPath
        The log file. Defaults to Disable-DepartingUser.log in -BackupDirectory.

    .PARAMETER DescriptionPrefix
        Text written in front of the date in the description. Defaults to 'Disabled'.

    .PARAMETER Server
        The domain controller or domain to use. Defaults to the domain of the current session.

    .PARAMETER Credential
        Credentials for the Active Directory changes.

    .EXAMPLE
        Disable-DepartingUser -Identity jdoe -BackupDirectory D:\Offboarding -TargetOU 'OU=Disabled Users,DC=contoso,DC=com' -WhatIf

        Shows every change that would be made for jdoe, without changing anything or writing any file.

    .EXAMPLE
        Disable-DepartingUser -Identity jdoe -BackupDirectory D:\Offboarding -TargetOU 'OU=Disabled Users,DC=contoso,DC=com'

        Offboards jdoe and asks for confirmation before each change.

    .EXAMPLE
        Import-Csv .\leavers.csv | Disable-DepartingUser -BackupDirectory D:\Offboarding -TargetOU 'OU=Disabled Users,DC=contoso,DC=com' -DescriptionPrefix 'Left the company' -Confirm:$false

        Offboards every user listed in the SamAccountName column of a CSV file without prompting.

    .INPUTS
        System.String

    .OUTPUTS
        ITToolkit.DepartingUserResult

    .LINK
        Get-StaleADAccount
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('ITToolkit.DepartingUserResult')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('SamAccountName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupDirectory,

        [ValidateNotNullOrEmpty()]
        [string]$TargetOU,

        [ValidateNotNullOrEmpty()]
        [string]$LogPath,

        [ValidateNotNullOrEmpty()]
        [string]$DescriptionPrefix = 'Disabled',

        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        try {
            Assert-ITADModule
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        $backupRoot = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BackupDirectory)
        if ($LogPath) {
            $logFile = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
        }
        else {
            $logFile = Join-Path -Path $backupRoot -ChildPath 'Disable-DepartingUser.log'
        }

        $ad = @{ ErrorAction = 'Stop' }
        if ($Server) {
            $ad.Server = $Server
        }
        $operator = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
            $ad.Credential = $Credential
            $operator = "$operator (as $($Credential.UserName))"
        }

        if ($TargetOU) {
            try {
                $null = Get-ADObject -Identity $TargetOU @ad
            }
            catch {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.ArgumentException]::new("Target OU '$TargetOU' was not found: $($_.Exception.Message)", $_.Exception),
                        'TargetOUNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $TargetOU))
            }
        }

        $isWhatIf = [bool]$WhatIfPreference
        $today = (Get-Date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    process {
        foreach ($id in $Identity) {
            try {
                $user = Get-ADUser -Identity $id -Properties MemberOf, Description @ad
            }
            catch {
                Write-Error -Message "[$id] User could not be read: $($_.Exception.Message)" -Exception $_.Exception -Category ObjectNotFound -ErrorId 'DepartingUserNotFound' -TargetObject $id
                continue
            }

            $sam = $user.SamAccountName
            $userDn = $user.DistinguishedName
            $groups = @($user.MemberOf | Where-Object { $_ })
            $removed = New-Object -TypeName System.Collections.Generic.List[string]
            $failed = New-Object -TypeName System.Collections.Generic.List[string]
            $problems = New-Object -TypeName System.Collections.Generic.List[string]
            $log = @{ Path = $logFile; Target = $sam; Operator = $operator }

            # Records a failed step in the log, the result and the error stream.
            $reportFailure = {
                param([string]$Message, [System.Management.Automation.ErrorRecord]$Cause)
                $text = "$Message $($Cause.Exception.Message)"
                $problems.Add($text)
                Write-ITLog @log -Level ERROR -Message $text
                Write-Error -Message "[$sam] $text" -Exception $Cause.Exception -Category WriteError -ErrorId 'DepartingUserStepFailed' -TargetObject $sam
            }

            if (-not $isWhatIf) {
                Write-ITLog @log -Message "Processing started. DN: $userDn; enabled: $($user.Enabled); groups: $($groups.Count)."
            }

            # 1. Back up group memberships. Nothing is changed if this fails.
            $backupFile = $null
            $backupDone = $false
            if ($groups.Count -eq 0) {
                $backupDone = $true
                if (-not $isWhatIf) {
                    Write-ITLog @log -Message 'No group memberships to back up or remove.'
                }
            }
            else {
                $candidate = Join-Path -Path $backupRoot -ChildPath ('{0}_groups_{1}.csv' -f $sam, (Get-Date -Format 'yyyyMMdd-HHmmss'))
                if ($PSCmdlet.ShouldProcess($candidate, "Back up $($groups.Count) group membership(s) of '$sam'")) {
                    try {
                        $null = [System.IO.Directory]::CreateDirectory($backupRoot)
                        $backedUpAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
                        $groups |
                            ForEach-Object -Process {
                                [pscustomobject]@{
                                    SamAccountName         = $sam
                                    UserDistinguishedName  = $userDn
                                    GroupDistinguishedName = $_
                                    BackedUpAt             = $backedUpAt
                                }
                            } |
                            Export-Csv -LiteralPath $candidate -NoTypeInformation -Encoding UTF8 -WhatIf:$false -Confirm:$false
                        $backupFile = $candidate
                        $backupDone = $true
                        Write-ITLog @log -Message "Backed up $($groups.Count) group membership(s) to '$candidate'."
                    }
                    catch {
                        Write-ITLog @log -Level ERROR -Message "Group membership backup failed, the user was not changed: $($_.Exception.Message)"
                        Write-Error -Message "[$sam] Group membership backup failed, the user was not changed: $($_.Exception.Message)" -Exception $_.Exception -Category WriteError -ErrorId 'DepartingUserBackupFailed' -TargetObject $sam
                        continue
                    }
                }
                elseif (-not $isWhatIf) {
                    Write-ITLog @log -Level WARN -Message 'Group membership backup was declined; group memberships will not be removed.'
                    Write-Warning -Message "[$sam] Group membership backup was declined; group memberships will not be removed."
                }
            }

            # 2. Remove group memberships (only after a successful backup; -WhatIf shows them all).
            if ($backupDone -or $isWhatIf) {
                foreach ($groupDn in $groups) {
                    if ($PSCmdlet.ShouldProcess($groupDn, "Remove '$sam' from group")) {
                        try {
                            Remove-ADGroupMember -Identity $groupDn -Members $user -Confirm:$false @ad
                            $removed.Add($groupDn)
                            Write-ITLog @log -Message "Removed from group '$groupDn'."
                        }
                        catch {
                            $failed.Add($groupDn)
                            & $reportFailure "Could not remove from group '$groupDn':" $_
                        }
                    }
                }
            }

            # 3. Disable the account.
            $disabled = $false
            if ($user.Enabled -eq $false) {
                $disabled = $true
                if (-not $isWhatIf) {
                    Write-ITLog @log -Message 'Account was already disabled.'
                }
            }
            elseif ($PSCmdlet.ShouldProcess($sam, 'Disable account')) {
                try {
                    Disable-ADAccount -Identity $user.ObjectGUID -Confirm:$false @ad
                    $disabled = $true
                    Write-ITLog @log -Message 'Account disabled.'
                }
                catch {
                    & $reportFailure 'Could not disable the account:' $_
                }
            }

            # 4. Stamp the description.
            $descriptionUpdated = $false
            $stamp = "$DescriptionPrefix $today"
            if ($user.Description -and $user.Description.StartsWith($stamp, [System.StringComparison]::OrdinalIgnoreCase)) {
                $descriptionUpdated = $true
                if (-not $isWhatIf) {
                    Write-ITLog @log -Message 'Description already carries today''s stamp.'
                }
            }
            else {
                $newDescription = $stamp
                if ($user.Description) {
                    $newDescription = "$stamp - $($user.Description)"
                }
                if ($PSCmdlet.ShouldProcess($sam, "Set description to '$newDescription'")) {
                    try {
                        Set-ADUser -Identity $user.ObjectGUID -Description $newDescription -Confirm:$false @ad
                        $descriptionUpdated = $true
                        Write-ITLog @log -Message "Description changed from '$($user.Description)' to '$newDescription'."
                    }
                    catch {
                        & $reportFailure 'Could not update the description:' $_
                    }
                }
            }

            # 5. Move to the target OU (last, because it changes the distinguished name).
            $movedTo = $null
            if ($TargetOU) {
                $currentParent = $userDn -replace '^.+?(?<!\\),', ''
                if ($currentParent -eq $TargetOU) {
                    $movedTo = $TargetOU
                    if (-not $isWhatIf) {
                        Write-ITLog @log -Message "Account is already in '$TargetOU'."
                    }
                }
                elseif ($PSCmdlet.ShouldProcess($sam, "Move to '$TargetOU'")) {
                    try {
                        Move-ADObject -Identity $user.ObjectGUID -TargetPath $TargetOU -Confirm:$false @ad
                        $movedTo = $TargetOU
                        Write-ITLog @log -Message "Moved from '$currentParent' to '$TargetOU'."
                    }
                    catch {
                        & $reportFailure "Could not move the account to '$TargetOU':" $_
                    }
                }
            }

            if ($isWhatIf) {
                continue
            }

            $status = 'Completed'
            if ($problems.Count -gt 0) {
                $status = 'CompletedWithErrors'
            }
            Write-ITLog @log -Message "Processing finished: $status."

            [pscustomobject]@{
                PSTypeName         = 'ITToolkit.DepartingUserResult'
                SamAccountName     = $sam
                DistinguishedName  = $userDn
                Status             = $status
                Disabled           = $disabled
                DescriptionUpdated = $descriptionUpdated
                GroupsRemoved      = [string[]]$removed.ToArray()
                GroupsFailed       = [string[]]$failed.ToArray()
                MovedTo            = $movedTo
                BackupFile         = $backupFile
                LogFile            = $logFile
                Errors             = [string[]]$problems.ToArray()
            }
        }
    }
}
