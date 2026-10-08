function Export-ITReport {
    <#
    .SYNOPSIS
        Exports the output of any ITToolkit command to a CSV file or a self-contained HTML report.

    .DESCRIPTION
        Export-ITReport collects objects from the pipeline and writes them to a single file.

        CSV files are written as UTF-8 with a byte order mark, so Excel shows non-ASCII characters
        (for example Turkish characters) correctly. Use -Delimiter ';' for Excel installations whose
        list separator is a semicolon.

        HTML reports are a single file with embedded styles; every value is HTML-encoded. Rows whose
        -HighlightProperty value is $true are highlighted, which makes threshold violations stand out
        (for example BelowThreshold from Get-DiskSpaceReport).

        In both formats collection values are joined with '; ' and dates are written as
        'yyyy-MM-dd HH:mm:ss'.

    .PARAMETER InputObject
        The objects to export. Usually received from the pipeline.

    .PARAMETER Path
        The file to create. An existing file is overwritten. The parent folder must exist.

    .PARAMETER Format
        Csv or Html. When omitted, the format is chosen from the file extension (.csv, .htm, .html).

    .PARAMETER Title
        The title of the HTML report. Ignored for CSV.

    .PARAMETER HighlightProperty
        The name of a boolean property. HTML rows where it is $true are highlighted. Ignored for CSV.

    .PARAMETER Property
        The properties (columns) to export, in order. By default all properties of the first object are used.

    .PARAMETER Delimiter
        The CSV field delimiter. Defaults to a comma.

    .PARAMETER PassThru
        Returns the created file as a System.IO.FileInfo object.

    .EXAMPLE
        Get-DiskSpaceReport -ComputerName SRV01, SRV02 | Export-ITReport -Path .\disks.html -HighlightProperty BelowThreshold

        Creates an HTML report in which disks below the free space threshold are highlighted.

    .EXAMPLE
        Get-SystemInventory -ComputerName (Get-Content .\servers.txt) | Export-ITReport -Path .\inventory.csv -Delimiter ';'

        Creates a semicolon separated CSV file that opens directly in Excel with a Turkish locale.

    .EXAMPLE
        Get-StaleADAccount -Days 120 | Export-ITReport -Path .\stale.html -Title 'Stale accounts' -Property SamAccountName, ObjectClass, LastLogonDate

        Creates an HTML report that contains only the selected columns.

    .INPUTS
        System.Management.Automation.PSObject

    .OUTPUTS
        None by default. System.IO.FileInfo when -PassThru is used.

    .LINK
        https://github.com/MuhammetCanTopaloglu/it-toolkit
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [psobject[]]$InputObject,

        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [ValidateSet('Csv', 'Html')]
        [string]$Format,

        [ValidateNotNullOrEmpty()]
        [string]$Title = 'IT Toolkit Report',

        [string]$HighlightProperty,

        [string[]]$Property,

        [char]$Delimiter = ',',

        [switch]$PassThru
    )

    begin {
        $fullPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

        if (-not $Format) {
            switch ([System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()) {
                '.csv' { $Format = 'Csv' }
                '.htm' { $Format = 'Html' }
                '.html' { $Format = 'Html' }
                default {
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                            [System.ArgumentException]::new("Cannot infer the report format from '$Path'. Use a .csv or .html extension, or specify -Format."),
                            'UnknownReportFormat',
                            [System.Management.Automation.ErrorCategory]::InvalidArgument,
                            $Path))
                }
            }
        }

        $parent = Split-Path -Path $fullPath -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.IO.DirectoryNotFoundException]::new("The folder '$parent' does not exist."),
                    'ReportFolderNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $parent))
        }

        $rows = New-Object -TypeName System.Collections.Generic.List[object]
    }

    process {
        foreach ($item in $InputObject) {
            if ($null -ne $item) {
                $rows.Add($item)
            }
        }
    }

    end {
        if (-not $PSCmdlet.ShouldProcess($fullPath, "Write $Format report with $($rows.Count) row(s)")) {
            return
        }

        if ($rows.Count -eq 0) {
            Write-Warning -Message 'No objects were received; the report will be empty.'
        }

        $columns = $Property
        if (-not $columns -and $rows.Count -gt 0) {
            $columns = @(($rows[0] | ConvertTo-ITFlatObject).PSObject.Properties | ForEach-Object { $_.Name })
        }
        $flatRows = @($rows | ConvertTo-ITFlatObject -Property $columns)
        $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true

        if ($Format -eq 'Csv') {
            $lines = @()
            if ($flatRows.Count -gt 0) {
                $lines = @($flatRows | ConvertTo-Csv -NoTypeInformation -Delimiter $Delimiter)
            }
            [System.IO.File]::WriteAllLines($fullPath, [string[]]$lines, $encoding)
        }
        else {
            $html = New-Object -TypeName System.Text.StringBuilder
            $encodedTitle = [System.Net.WebUtility]::HtmlEncode($Title)
            $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)

            $null = $html.AppendLine('<!DOCTYPE html>')
            $null = $html.AppendLine('<html lang="en">')
            $null = $html.AppendLine('<head>')
            $null = $html.AppendLine('<meta charset="utf-8">')
            $null = $html.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
            $null = $html.AppendLine("<title>$encodedTitle</title>")
            $null = $html.AppendLine('<style>')
            $null = $html.AppendLine('body { font-family: "Segoe UI", Arial, sans-serif; margin: 24px; color: #1f2328; background: #ffffff; }')
            $null = $html.AppendLine('h1 { font-size: 22px; margin: 0 0 4px 0; }')
            $null = $html.AppendLine('.meta { color: #59636e; font-size: 13px; margin-bottom: 16px; }')
            $null = $html.AppendLine('.wrap { overflow-x: auto; }')
            $null = $html.AppendLine('table { border-collapse: collapse; font-size: 13px; }')
            $null = $html.AppendLine('th, td { border: 1px solid #d1d9e0; padding: 6px 10px; text-align: left; vertical-align: top; }')
            $null = $html.AppendLine('th { background: #f6f8fa; position: sticky; top: 0; }')
            $null = $html.AppendLine('tr:nth-child(even) td { background: #fafbfc; }')
            $null = $html.AppendLine('tr.flag td { background: #ffebe9; }')
            $null = $html.AppendLine('</style>')
            $null = $html.AppendLine('</head>')
            $null = $html.AppendLine('<body>')
            $null = $html.AppendLine("<h1>$encodedTitle</h1>")
            $null = $html.AppendLine("<div class=`"meta`">Generated $generated &middot; $($flatRows.Count) row(s)</div>")

            if ($flatRows.Count -eq 0) {
                $null = $html.AppendLine('<p>No records.</p>')
            }
            else {
                $null = $html.AppendLine('<div class="wrap"><table>')
                $null = $html.Append('<thead><tr>')
                foreach ($column in $columns) {
                    $null = $html.Append('<th>').Append([System.Net.WebUtility]::HtmlEncode($column)).Append('</th>')
                }
                $null = $html.AppendLine('</tr></thead>')
                $null = $html.AppendLine('<tbody>')
                foreach ($row in $flatRows) {
                    $flagged = $HighlightProperty -and ("$($row.$HighlightProperty)" -eq 'True')
                    if ($flagged) {
                        $null = $html.Append('<tr class="flag">')
                    }
                    else {
                        $null = $html.Append('<tr>')
                    }
                    foreach ($column in $columns) {
                        $null = $html.Append('<td>').Append([System.Net.WebUtility]::HtmlEncode("$($row.$column)")).Append('</td>')
                    }
                    $null = $html.AppendLine('</tr>')
                }
                $null = $html.AppendLine('</tbody>')
                $null = $html.AppendLine('</table></div>')
            }

            $null = $html.AppendLine('</body>')
            $null = $html.AppendLine('</html>')
            [System.IO.File]::WriteAllText($fullPath, $html.ToString(), $encoding)
        }

        Write-Verbose -Message "Wrote $($flatRows.Count) row(s) to '$fullPath'."
        if ($PassThru) {
            Get-Item -LiteralPath $fullPath
        }
    }
}
