<#
.SYNOPSIS
    Installs test dependencies, runs PSScriptAnalyzer and runs the Pester test suite.

.DESCRIPTION
    Used both locally and by the GitHub Actions workflow.
    Bootstrap installs Pester 5.x and PSScriptAnalyzer for the current user when they are missing.

.PARAMETER Task
    One or more of Bootstrap, Analyze, Test. All runs every task in that order.

.EXAMPLE
    ./build.ps1

.EXAMPLE
    ./build.ps1 -Task Analyze
#>
[CmdletBinding()]
param(
    [ValidateSet('Bootstrap', 'Analyze', 'Test', 'All')]
    [string[]]$Task = 'All'
)

$ErrorActionPreference = 'Stop'
$pesterMinimum = [version]'5.5.0'
$pesterMaximum = [version]'5.999.999'

if ($Task -contains 'All') {
    $Task = @('Bootstrap', 'Analyze', 'Test')
}

if ($Task -contains 'Bootstrap') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $pester = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -ge $pesterMinimum -and $_.Version -le $pesterMaximum }
    if (-not $pester) {
        Write-Output "Installing Pester $pesterMinimum - 5.x"
        Install-Module -Name Pester -MinimumVersion $pesterMinimum -MaximumVersion $pesterMaximum -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
    }

    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Write-Output 'Installing PSScriptAnalyzer'
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
    }
}

if ($Task -contains 'Analyze') {
    Import-Module -Name PSScriptAnalyzer
    $settings = Join-Path -Path $PSScriptRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
    $findings = @(Invoke-ScriptAnalyzer -Path $PSScriptRoot -Recurse -Settings $settings)
    if ($findings.Count -gt 0) {
        $findings | Format-Table -AutoSize -Property Severity, RuleName, ScriptName, Line, Message | Out-String -Width 300 | Write-Output
        throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
    }
    Write-Output 'PSScriptAnalyzer: no findings.'
}

if ($Task -contains 'Test') {
    Import-Module -Name Pester -MinimumVersion $pesterMinimum -MaximumVersion $pesterMaximum

    $resultsDir = Join-Path -Path $PSScriptRoot -ChildPath 'TestResults'
    $null = New-Item -Path $resultsDir -ItemType Directory -Force

    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path -Path $PSScriptRoot -ChildPath 'Tests'
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = Join-Path -Path $resultsDir -ChildPath "pester-ps$($PSVersionTable.PSVersion.Major).xml"
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = Join-Path -Path $PSScriptRoot -ChildPath 'ITToolkit'
    $config.CodeCoverage.OutputPath = Join-Path -Path $resultsDir -ChildPath "coverage-ps$($PSVersionTable.PSVersion.Major).xml"

    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
        throw "Pester: $($result.FailedCount) test(s) failed."
    }
}
