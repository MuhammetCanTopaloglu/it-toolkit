# Dot-sourced from BeforeAll in every test file: imports a fresh copy of the module and stub
# ActiveDirectory cmdlets. The stubs are always loaded, even when RSAT is installed: functions take
# precedence over cmdlets, so the tests never depend on (or touch) a real Active Directory.

$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\ITToolkit\ITToolkit.psd1'
Get-Module -Name ITToolkit | Remove-Module -Force
Import-Module -Name $moduleManifest -Force -ErrorAction Stop

$adStub = Join-Path -Path $PSScriptRoot -ChildPath 'Stubs\ActiveDirectory.Stub.psm1'
Import-Module -Name $adStub -Force -ErrorAction Stop
