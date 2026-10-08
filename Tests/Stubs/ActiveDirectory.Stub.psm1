# Minimal stand-ins for the ActiveDirectory cmdlets used by ITToolkit. They are only imported when
# the real module is not installed, so that Pester can mock them. Calling one without a mock fails.

function Get-ADUser {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [object]$Identity,
        [string]$Filter,
        [string]$LDAPFilter,
        [string[]]$Properties,
        [string]$SearchBase,
        [string]$Server,
        [pscredential]$Credential
    )
    throw "Stub for Get-ADUser called with: $($PSBoundParameters.Keys -join ', ')"
}

function Get-ADComputer {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [object]$Identity,
        [string]$Filter,
        [string]$LDAPFilter,
        [string[]]$Properties,
        [string]$SearchBase,
        [string]$Server,
        [pscredential]$Credential
    )
    throw "Stub for Get-ADComputer called with: $($PSBoundParameters.Keys -join ', ')"
}

Export-ModuleMember -Function *
