function Get-ITCertificateStoreItem {
    <#
    .SYNOPSIS
        Reads certificates from LocalMachine certificate stores.

    .DESCRIPTION
        Self-contained on purpose: Get-ExpiringCertificate sends this function's script block to remote
        computers with Invoke-Command, where the module is not installed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]$StoreName
    )

    foreach ($name in $StoreName) {
        $store = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $name, 'LocalMachine'
        try {
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]'ReadOnly, OpenExistingOnly')
            foreach ($certificate in $store.Certificates) {
                [pscustomobject]@{
                    Store         = "LocalMachine\$name"
                    Subject       = $certificate.Subject
                    FriendlyName  = $certificate.FriendlyName
                    Issuer        = $certificate.Issuer
                    Thumbprint    = $certificate.Thumbprint
                    NotBefore     = $certificate.NotBefore
                    NotAfter      = $certificate.NotAfter
                    HasPrivateKey = $certificate.HasPrivateKey
                }
            }
        }
        catch {
            Write-Warning -Message "Certificate store 'LocalMachine\$name' could not be opened: $($_.Exception.Message)"
        }
        finally {
            $store.Close()
        }
    }
}
