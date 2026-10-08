function ConvertTo-ITFlatObject {
    <#
    .SYNOPSIS
        Converts an object into a flat object whose property values are scalars suitable for CSV/HTML.

    .DESCRIPTION
        Collections are joined with a separator, dates are written as sortable ISO 8601 text and
        remoting-only properties (PSComputerName, RunspaceId, PSShowComputerName) are dropped.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [psobject]$InputObject,

        [string[]]$Property,

        [string]$Separator = '; '
    )

    begin {
        $excluded = @('PSComputerName', 'PSShowComputerName', 'RunspaceId')
    }

    process {
        if ($null -eq $InputObject) {
            return
        }

        $names = $Property
        if (-not $names) {
            $names = @($InputObject.PSObject.Properties | Where-Object { $excluded -notcontains $_.Name } | ForEach-Object { $_.Name })
        }

        $flat = [ordered]@{}
        foreach ($name in $names) {
            $value = $InputObject.$name
            if ($null -eq $value) {
                $flat[$name] = $null
            }
            elseif ($value -is [string]) {
                $flat[$name] = $value
            }
            elseif ($value -is [datetime]) {
                $flat[$name] = $value.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            elseif ($value -is [System.Collections.IEnumerable]) {
                $flat[$name] = (@($value) | ForEach-Object { "$_" }) -join $Separator
            }
            else {
                $flat[$name] = $value
            }
        }

        [pscustomobject]$flat
    }
}
