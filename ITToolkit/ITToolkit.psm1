#Requires -Version 5.1

# Dot-source private helpers first so public functions can rely on them.
$privateFiles = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$publicFiles = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($privateFiles + $publicFiles)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import '$($file.FullName)': $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $publicFiles.BaseName
