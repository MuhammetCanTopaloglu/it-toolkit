@{
    Severity            = @('Error', 'Warning', 'Information')
    IncludeDefaultRules = $true

    Rules               = @{
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentIndentation = @{
            Enable              = $true
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind                = 'space'
        }
        PSUseConsistentWhitespace  = @{
            Enable                          = $true
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $false
            CheckPipe                       = $true
            CheckSeparator                  = $true
            CheckParameter                  = $false
        }
        # PSUseCorrectCasing (opt-in) is intentionally not enabled: with PSScriptAnalyzer 1.25 on
        # Windows PowerShell 5.1 it intermittently fails with "The term 'Get-Command' is not recognized".
    }
}
