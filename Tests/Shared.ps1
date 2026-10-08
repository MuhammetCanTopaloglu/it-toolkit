# Dot-sourced from BeforeAll in every test file: imports a fresh copy of the module and,
# when the real ActiveDirectory module is not installed, stub AD cmdlets so they can be mocked.

$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\ITToolkit\ITToolkit.psd1'
Get-Module -Name ITToolkit | Remove-Module -Force
Import-Module -Name $moduleManifest -Force -ErrorAction Stop

$adStub = Join-Path -Path $PSScriptRoot -ChildPath 'Stubs\ActiveDirectory.Stub.psm1'
if ((Test-Path -Path $adStub) -and -not (Get-Command -Name Get-ADUser -ErrorAction SilentlyContinue)) {
    Import-Module -Name $adStub -Force -ErrorAction Stop
}
