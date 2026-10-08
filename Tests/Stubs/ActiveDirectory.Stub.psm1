# Minimal stand-ins for the ActiveDirectory cmdlets used by ITToolkit, so that Pester can mock them
# without RSAT and without the real parameter types. Calling one without a mock fails.

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

function Get-ADObject {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [object]$Identity,
        [string[]]$Properties,
        [string]$Server,
        [pscredential]$Credential
    )
    throw "Stub for Get-ADObject called with: $($PSBoundParameters.Keys -join ', ')"
}

function Remove-ADGroupMember {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [object]$Identity,
        [Parameter(Position = 1)]
        [object[]]$Members,
        [string]$Server,
        [pscredential]$Credential
    )
    if ($PSCmdlet.ShouldProcess("$Identity", 'Stub')) {
        throw "Stub for Remove-ADGroupMember called with: $($PSBoundParameters.Keys -join ', ')"
    }
}

function Disable-ADAccount {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [object]$Identity,
        [string]$Server,
        [pscredential]$Credential
    )
    if ($PSCmdlet.ShouldProcess("$Identity", 'Stub')) {
        throw "Stub for Disable-ADAccount called with: $($PSBoundParameters.Keys -join ', ')"
    }
}

function Set-ADUser {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [object]$Identity,
        [string]$Description,
        [string]$Server,
        [pscredential]$Credential
    )
    if ($PSCmdlet.ShouldProcess("$Identity", 'Stub')) {
        throw "Stub for Set-ADUser called with: $($PSBoundParameters.Keys -join ', ')"
    }
}

function Move-ADObject {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [object]$Identity,
        [Parameter(Position = 1)]
        [string]$TargetPath,
        [string]$Server,
        [pscredential]$Credential
    )
    if ($PSCmdlet.ShouldProcess("$Identity", 'Stub')) {
        throw "Stub for Move-ADObject called with: $($PSBoundParameters.Keys -join ', ')"
    }
}

Export-ModuleMember -Function *
