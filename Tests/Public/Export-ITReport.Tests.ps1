BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\Shared.ps1')

    $script:sample = @(
        [pscustomobject]@{
            ComputerName   = 'SRV01'
            Drive          = 'C:'
            FreePercent    = 8.5
            BelowThreshold = $true
            Reasons        = @('WindowsUpdate', 'ComponentBasedServicing')
            CheckedAt      = [datetime]'2026-10-08T09:30:00'
            Owner          = 'Çağrı Öztürk'
        }
        [pscustomobject]@{
            ComputerName   = 'SRV02'
            Drive          = 'D:'
            FreePercent    = 54.2
            BelowThreshold = $false
            Reasons        = @()
            CheckedAt      = [datetime]'2026-10-08T09:31:00'
            Owner          = '<script>alert(1)</script>'
        }
    )
}

Describe 'Export-ITReport' {
    Context 'CSV' {
        It 'writes a header and one line per object' {
            $path = Join-Path -Path $TestDrive -ChildPath 'report.csv'

            $script:sample | Export-ITReport -Path $path

            $rows = @(Import-Csv -Path $path)
            $rows.Count | Should -Be 2
            $rows[0].ComputerName | Should -Be 'SRV01'
            $rows[1].Drive | Should -Be 'D:'
        }

        It 'writes UTF-8 with a byte order mark and keeps non-ASCII characters' {
            $path = Join-Path -Path $TestDrive -ChildPath 'utf8.csv'

            $script:sample | Export-ITReport -Path $path

            $bytes = [System.IO.File]::ReadAllBytes($path)
            $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
            (Import-Csv -Path $path -Encoding UTF8)[0].Owner | Should -Be 'Çağrı Öztürk'
        }

        It 'joins collections and formats dates in a culture independent way' {
            $path = Join-Path -Path $TestDrive -ChildPath 'flat.csv'

            $script:sample | Export-ITReport -Path $path

            $row = (Import-Csv -Path $path)[0]
            $row.Reasons | Should -Be 'WindowsUpdate; ComponentBasedServicing'
            $row.CheckedAt | Should -Be '2026-10-08 09:30:00'
        }

        It 'exports only the requested properties in the given order' {
            $path = Join-Path -Path $TestDrive -ChildPath 'columns.csv'

            $script:sample | Export-ITReport -Path $path -Property Drive, ComputerName

            $header = (Get-Content -Path $path -TotalCount 1)
            $header | Should -Be '"Drive","ComputerName"'
        }

        It 'uses the requested delimiter' {
            $path = Join-Path -Path $TestDrive -ChildPath 'semicolon.csv'

            $script:sample | Export-ITReport -Path $path -Delimiter ';' -Property ComputerName, Drive

            (Get-Content -Path $path -TotalCount 1) | Should -Be '"ComputerName";"Drive"'
        }
    }

    Context 'HTML' {
        BeforeAll {
            $script:htmlPath = Join-Path -Path $TestDrive -ChildPath 'report.html'
            $script:sample | Export-ITReport -Path $script:htmlPath -Title 'Disk <Report>' -HighlightProperty BelowThreshold
            $script:html = [System.IO.File]::ReadAllText($script:htmlPath)
        }

        It 'creates a complete HTML document with the encoded title' {
            $script:html | Should -Match '<!DOCTYPE html>'
            $script:html | Should -Match '<title>Disk &lt;Report&gt;</title>'
        }

        It 'HTML-encodes values' {
            $script:html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
            $script:html | Should -Not -Match '<script>alert'
        }

        It 'highlights only rows whose highlight property is true' {
            ([regex]::Matches($script:html, '<tr class="flag">')).Count | Should -Be 1
            $script:html | Should -Match '<tr class="flag"><td>SRV01</td>'
        }

        It 'shows a message when there are no rows' {
            $path = Join-Path -Path $TestDrive -ChildPath 'empty.html'

            @() | Export-ITReport -Path $path -WarningAction SilentlyContinue

            [System.IO.File]::ReadAllText($path) | Should -Match 'No records\.'
        }
    }

    Context 'Format, safety and output' {
        It 'infers the format from <Extension>' -ForEach @(
            @{ Extension = '.csv'; Marker = '"ComputerName"' }
            @{ Extension = '.htm'; Marker = '<!DOCTYPE html>' }
            @{ Extension = '.html'; Marker = '<!DOCTYPE html>' }
        ) {
            $path = Join-Path -Path $TestDrive -ChildPath "infer$Extension"

            $script:sample | Export-ITReport -Path $path

            [System.IO.File]::ReadAllText($path) | Should -Match ([regex]::Escape($Marker))
        }

        It 'lets -Format override the extension' {
            $path = Join-Path -Path $TestDrive -ChildPath 'report.txt'

            $script:sample | Export-ITReport -Path $path -Format Html

            [System.IO.File]::ReadAllText($path) | Should -Match '<!DOCTYPE html>'
        }

        It 'fails for an unknown extension without -Format' {
            $path = Join-Path -Path $TestDrive -ChildPath 'report.txt'

            { $script:sample | Export-ITReport -Path $path } | Should -Throw -ExpectedMessage '*-Format*'
        }

        It 'fails when the target folder does not exist' {
            $path = Join-Path -Path $TestDrive -ChildPath 'missing\report.csv'

            { $script:sample | Export-ITReport -Path $path } | Should -Throw -ExpectedMessage '*does not exist*'
        }

        It 'does not write anything with -WhatIf' {
            $path = Join-Path -Path $TestDrive -ChildPath 'whatif.csv'

            $script:sample | Export-ITReport -Path $path -WhatIf

            Test-Path -Path $path | Should -BeFalse
        }

        It 'returns the file with -PassThru and nothing otherwise' {
            $path = Join-Path -Path $TestDrive -ChildPath 'passthru.csv'

            $file = $script:sample | Export-ITReport -Path $path -PassThru
            $none = $script:sample | Export-ITReport -Path $path

            $file | Should -BeOfType [System.IO.FileInfo]
            $file.FullName | Should -Be $path
            $none | Should -BeNullOrEmpty
        }

        It 'warns when no objects are received' {
            $path = Join-Path -Path $TestDrive -ChildPath 'empty.csv'

            @() | Export-ITReport -Path $path -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings | Should -Not -BeNullOrEmpty
            Test-Path -Path $path | Should -BeTrue
        }
    }
}
