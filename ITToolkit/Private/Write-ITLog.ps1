function Write-ITLog {
    <#
    .SYNOPSIS
        Appends a timestamped line to a UTF-8 log file, creating the folder when needed.

    .DESCRIPTION
        Line format: 2026-10-08 14:03:12 +03:00 | INFO  | CONTOSO\operator | target | message
        Uses .NET file APIs on purpose, so the line is written even while the caller runs with
        -Confirm (no extra prompt). Callers must not log actions that were only simulated with -WhatIf.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [string]$Target = '-',

        [string]$Operator = '-'
    )

    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder -PathType Container)) {
        $null = [System.IO.Directory]::CreateDirectory($folder)
    }

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz', [System.Globalization.CultureInfo]::InvariantCulture)
    $line = '{0} | {1,-5} | {2} | {3} | {4}' -f $timestamp, $Level, $Operator, $Target, $Message
    [System.IO.File]::AppendAllText($Path, $line + [Environment]::NewLine, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true))
}
