BeforeDiscovery {
    $script:publicFunctions = @(
        Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\ITToolkit\Public') -Filter '*.ps1' -ErrorAction SilentlyContinue |
            ForEach-Object -Process { $_.BaseName }
    )
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Shared.ps1')
    $script:manifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\ITToolkit\ITToolkit.psd1'
    $script:publicNames = @(
        Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\ITToolkit\Public') -Filter '*.ps1' -ErrorAction SilentlyContinue |
            ForEach-Object -Process { $_.BaseName } |
            Sort-Object
    )
}

Describe 'ITToolkit module' {
    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $script:manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'supports Windows PowerShell 5.1 and PowerShell 7' {
        $manifest = Import-PowerShellDataFile -Path $script:manifestPath
        $manifest.PowerShellVersion | Should -Be '5.1'
        $manifest.CompatiblePSEditions | Should -Contain 'Desktop'
        $manifest.CompatiblePSEditions | Should -Contain 'Core'
    }

    It 'lists every public function in FunctionsToExport' {
        $manifest = Import-PowerShellDataFile -Path $script:manifestPath
        (@($manifest.FunctionsToExport | Sort-Object) -join ',') | Should -Be ($script:publicNames -join ',')
    }

    It 'exports only the public functions' {
        $exported = @((Get-Module -Name ITToolkit).ExportedFunctions.Keys | Sort-Object)
        ($exported -join ',') | Should -Be ($script:publicNames -join ',')
    }
}

Describe '<_> help and conventions' -ForEach $script:publicFunctions {
    BeforeAll {
        $script:command = Get-Command -Name $_ -Module ITToolkit
        $script:help = Get-Help -Name $_ -Full
        $script:commonParameters = @([System.Management.Automation.PSCmdlet]::CommonParameters)
        $script:commonParameters += [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
    }

    It 'is an advanced function' {
        $script:command.CmdletBinding | Should -BeTrue
    }

    It 'has a synopsis' {
        $script:help.Synopsis | Should -Not -BeNullOrEmpty
        $script:help.Synopsis | Should -Not -Match ([regex]::Escape($script:command.Name) + '\s')
    }

    It 'has a description' {
        ($script:help.Description.Text -join '') | Should -Not -BeNullOrEmpty
    }

    It 'has at least two examples' {
        @($script:help.Examples.Example).Count | Should -BeGreaterOrEqual 2
    }

    It 'documents every parameter' {
        $parameterNames = $script:command.Parameters.Keys | Where-Object { $script:commonParameters -notcontains $_ }
        foreach ($name in $parameterNames) {
            $parameterHelp = $script:help.Parameters.Parameter | Where-Object { $_.Name -eq $name }
            ($parameterHelp.Description.Text -join '') | Should -Not -BeNullOrEmpty -Because "parameter -$name needs a description"
        }
    }

    It 'declares an output type' {
        $script:command.OutputType | Should -Not -BeNullOrEmpty
    }
}
