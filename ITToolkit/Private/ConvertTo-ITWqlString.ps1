function ConvertTo-ITWqlString {
    <#
    .SYNOPSIS
        Escapes a value for use inside a single-quoted WQL string literal.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    return ($Value -replace '\\', '\\' -replace "'", "\'")
}
