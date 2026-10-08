# it-toolkit

[![CI](https://github.com/MuhammetCanTopaloglu/it-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/MuhammetCanTopaloglu/it-toolkit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**[English](README.en.md)** | Türkçe

Windows ve Active Directory ortamları için sistem yöneticisi araç seti. `ITToolkit`, Windows PowerShell 5.1 ve PowerShell 7 ile çalışan bir PowerShell modülüdür.

- Her komut nesne döndürür. Sonuçlar `Where-Object`, `Sort-Object` ve `Export-ITReport` ile süzülüp CSV veya HTML rapora dönüştürülebilir.
- Uzak bilgisayarlar **CIM** ile sorgulanır (önce WSMan, gerekirse DCOM). WMI cmdlet'leri kullanılmaz.
- Ulaşılamayan bir bilgisayar raporu bekletmez. `-TimeoutSeconds` (varsayılan 15) sonunda hata verilir ve sıradaki bilgisayara geçilir.
- Kuruma özgü hiçbir sabit değer yoktur. OU'lar, eşikler, yollar ve sunucular parametreyle verilir.
- Her komutun `Get-Help` ile açıklaması ve örnekleri vardır.

## İçindekiler

- [Gereksinimler](#gereksinimler)
- [Kurulum](#kurulum)
- [Ortak parametreler](#ortak-parametreler)
- [Komutlar](#komutlar)
  - [Get-DiskSpaceReport](#get-diskspacereport)
  - [Get-UpdateStatus](#get-updatestatus)
  - [Get-LocalAdminAudit](#get-localadminaudit)
  - [Get-SystemInventory](#get-systeminventory)
  - [Get-ExpiringCertificate](#get-expiringcertificate)
  - [Get-StaleADAccount](#get-staleadaccount)
  - [Get-PasswordExpiryReport](#get-passwordexpiryreport)
  - [Disable-DepartingUser](#disable-departinguser)
  - [Export-ITReport](#export-itreport)
- [-WhatIf ve -Confirm](#-whatif-ve--confirm)
- [Testler ve kod kalitesi](#testler-ve-kod-kalitesi)
- [Lisans](#lisans)

## Gereksinimler

| Gereksinim | Ne için |
|---|---|
| Windows PowerShell 5.1 veya PowerShell 7.x (Windows) | Tüm komutlar |
| Uzak bilgisayarda WinRM (TCP 5985) **veya** DCOM/RPC (TCP 135) ve WMI güvenlik duvarı kuralları | `-ComputerName` ile uzak sorgular |
| Uzak bilgisayarda PowerShell Remoting (WinRM) | Yalnızca `Get-ExpiringCertificate` uzak sorguları |
| Uzak bilgisayarda yerel yönetici yetkisi | Uzak CIM sorguları |
| ActiveDirectory modülü (RSAT) | `Get-StaleADAccount`, `Get-PasswordExpiryReport`, `Disable-DepartingUser` |
| AD'de kullanıcı/grup değiştirme ve taşıma yetkisi | `Disable-DepartingUser` |

ActiveDirectory modülü yüklü değilse AD komutları, kurulumun nasıl yapılacağını gösteren bir hata verir:

```powershell
# Windows 10/11
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
# Windows Server
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

## Kurulum

```powershell
git clone https://github.com/MuhammetCanTopaloglu/it-toolkit.git
Import-Module .\it-toolkit\ITToolkit\ITToolkit.psd1
Get-Command -Module ITToolkit
```

Modülün her oturumda adıyla yüklenmesi için `ITToolkit` klasörünü modül yollarından birine kopyalayın:

```powershell
# Windows PowerShell 5.1: Documents\WindowsPowerShell\Modules
# PowerShell 7:           Documents\PowerShell\Modules
Copy-Item -Recurse .\it-toolkit\ITToolkit "$HOME\Documents\WindowsPowerShell\Modules\ITToolkit"
Import-Module ITToolkit
```

Dosyaları ZIP olarak indirdiyseniz, yürütme ilkesi engellemesin diye önce engellerini kaldırın:

```powershell
Get-ChildItem -Recurse .\it-toolkit | Unblock-File
```

## Ortak parametreler

Bilgisayar sorgulayan komutların hepsinde (`Get-DiskSpaceReport`, `Get-UpdateStatus`, `Get-LocalAdminAudit`, `Get-SystemInventory`, `Get-ExpiringCertificate`) şu parametreler bulunur:

| Parametre | Açıklama |
|---|---|
| `-ComputerName` | Varsayılan değer yerel bilgisayardır. Pipeline'dan metin alabilir. `ComputerName`, `DNSHostName` veya `Name` özelliği olan nesneleri de kabul eder (örneğin `Get-ADComputer` çıktısı). |
| `-Credential` | Uzak bilgisayarlar için kimlik bilgisi. Yerel bilgisayarda yok sayılır. |
| `-TimeoutSeconds` | Bir bilgisayarın yanıt vermesi için beklenecek süre (varsayılan 15). Bağlantıdan önce portlar bu süreyle yoklanır, böylece kapalı bir makine raporu uzun süre bekletmez. |

Yerel bilgisayar WinRM gerektirmeden sorgulanır. Ulaşılamayan bir bilgisayar *non-terminating* bir hata üretir ve listedeki diğer bilgisayarlar işlenmeye devam eder:

```powershell
$output  = Get-Content .\servers.txt | Get-SystemInventory -TimeoutSeconds 5 2>&1
$results = $output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
$offline = ($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).TargetObject   # ulaşılamayan bilgisayarlar
```

AD komutları `-ComputerName` yerine `-Server` (etki alanı denetleyicisi) ve `-Credential` alır.

## Komutlar

> Aşağıdaki çıktılar örnektir. Bilgisayar, kullanıcı ve etki alanı adları temsilidir.

### Get-DiskSpaceReport

Sabit disklerin boyutunu, boş alanını ve doluluk oranını raporlar. Boş alanı `-ThresholdPercent` değerinin (varsayılan 15) altında kalan diskleri `BelowThreshold` ile işaretler.

```powershell
Get-DiskSpaceReport -ComputerName SRV01, SRV02 | Format-Table
```

```text
ComputerName Drive VolumeName FileSystem SizeGB FreeGB UsedPercent FreePercent ThresholdPercent BelowThreshold
------------ ----- ---------- ---------- ------ ------ ----------- ----------- ---------------- --------------
SRV01        C:    System     NTFS       126,45  48,12       61,94       38,06               15          False
SRV01        D:    Data       NTFS       511,87  37,40       92,69        7,31               15           True
SRV02        C:    System     NTFS       126,45  71,03       43,83       56,17               15          False
```

```powershell
# AD'deki tüm sunucular; boş alanı %10'un altında kalanlar
Get-ADComputer -Filter 'OperatingSystem -like "*Server*"' |
    Get-DiskSpaceReport -ThresholdPercent 10 |
    Where-Object BelowThreshold
```

### Get-UpdateStatus

Son yüklenen güncellemenin tarihini ve KB numarasını, üzerinden kaç gün geçtiğini ve bilgisayarın yeniden başlatma bekleyip beklemediğini gösterir. Bekleyen yeniden başlatma şu dört kaynaktan okunur: Component Based Servicing, Windows Update, PendingFileRenameOperations ve bilgisayar adı değişikliği. Kayıt defteri CIM (`StdRegProv`) üzerinden okunduğu için Remote Registry servisine gerek yoktur.

```powershell
Get-UpdateStatus -ComputerName SRV01
```

```text
ComputerName        : SRV01
LastUpdateInstalled : 15.09.2026 00:00:00
LastHotFixId        : KB5065432
DaysSinceLastUpdate : 23
HotFixCount         : 6
PendingReboot       : True
PendingRebootReason : {WindowsUpdate, PendingFileRenameOperations}
```

```powershell
# Yeniden başlatma bekleyen sunucular
Get-Content .\servers.txt | Get-UpdateStatus | Where-Object PendingReboot

# 45 günden uzun süredir güncelleme almamış olanlar
Get-Content .\servers.txt | Get-UpdateStatus | Where-Object DaysSinceLastUpdate -GT 45
```

> `Win32_QuickFixEngineering` toplu güncellemeleri ve güvenlik güncellemelerini listeler. Defender tanım güncellemeleri ve Store uygulama güncellemeleri bu listede yer almaz.

### Get-LocalAdminAudit

Yerel Administrators grubunun üyelerini listeler. Grup adıyla değil, iyi bilinen SID'iyle (`S-1-5-32-544`) bulunur. Bu sayede grubun "Yöneticiler" adını taşıdığı Türkçe Windows'ta da çalışır.

- **Silinmiş hesaplara ait, çözümlenemeyen SID'ler hata vermez.** Raporda `IsOrphaned = True` olarak işaretlenir ve temizlenebilir.
- `-ExpectedMember` ile onaylı üyeler verilirse `IsExpected`, beklenmeyen yöneticileri gösterir. Değerler joker karakter ve SID içerebilir.

```powershell
Get-LocalAdminAudit -ComputerName SRV01 -ExpectedMember '*\Administrator', 'CONTOSO\Domain Admins' |
    Format-Table Member, MemberType, IsLocal, IsOrphaned, IsExpected
```

```text
Member                                                 MemberType IsLocal IsOrphaned IsExpected
------                                                 ---------- ------- ---------- ----------
SRV01\Administrator                                    User          True      False       True
CONTOSO\Domain Admins                                  Group        False      False       True
CONTOSO\helpdesk-t1                                    Group        False      False      False
CONTOSO\S-1-5-21-1004336348-1177238915-682003330-4242  Unknown                  True      False
```

```powershell
# Bir OU'daki sunucularda yetim SID'leri bul ve CSV'ye aktar
Get-ADComputer -Filter * -SearchBase 'OU=Servers,DC=contoso,DC=com' |
    Get-LocalAdminAudit |
    Where-Object IsOrphaned |
    Export-ITReport -Path .\orphaned-admins.csv
```

### Get-SystemInventory

İşletim sistemi, CPU, RAM, seri numarası, model ve uptime bilgilerini tek bir nesnede toplar. Uptime, uzak bilgisayarın kendi saatine göre hesaplanır.

```powershell
Get-SystemInventory -ComputerName SRV01
```

```text
ComputerName          : SRV01
Manufacturer          : Dell Inc.
Model                 : PowerEdge R650
SerialNumber          : 7XK2Q93
BiosVersion           : 1.14.1
Domain                : contoso.com
OperatingSystem       : Microsoft Windows Server 2022 Standard
OSVersion             : 10.0.20348
OSBuild               : 20348
OSArchitecture        : 64-bit
Processor             : Intel(R) Xeon(R) Gold 6338 CPU @ 2.00GHz
ProcessorCount        : 2
CoreCount             : 64
LogicalProcessorCount : 128
TotalMemoryGB         : 255,62
InstallDate           : 10.01.2024 08:00:00
LastBootTime          : 22.09.2026 07:58:32
Uptime                : 16.01:23:26.6161540
UptimeDays            : 16,1
```

```powershell
Get-Content .\servers.txt | Get-SystemInventory |
    Select-Object ComputerName, Model, SerialNumber, TotalMemoryGB, UptimeDays |
    Export-ITReport -Path .\inventory.csv -Delimiter ';'
```

### Get-ExpiringCertificate

LocalMachine sertifika depolarında `-Days` gün (varsayılan 30) içinde süresi dolacak sertifikaları bulur. Varsayılan depo `My` (Kişisel) deposudur. Süresi zaten dolmuş sertifikalar yalnızca `-IncludeExpired` ile gelir.

> Sertifika depoları CIM üzerinden okunamaz. Yerel bilgisayarda depo doğrudan okunur, uzak bilgisayarlarda `Invoke-Command` (PowerShell Remoting) kullanılır.

```powershell
Get-ExpiringCertificate -ComputerName WEB01 -Days 60 -StoreName My, WebHosting |
    Format-Table ComputerName, Store, Subject, NotAfter, DaysRemaining, HasPrivateKey
```

```text
ComputerName Store                     Subject                   NotAfter            DaysRemaining HasPrivateKey
------------ -----                     -------                   --------            ------------- -------------
WEB01        LocalMachine\My           CN=intranet.contoso.com   21.10.2026 14:00:00            13          True
WEB01        LocalMachine\WebHosting   CN=api.contoso.com        30.11.2026 09:30:00            52          True
```

### Get-StaleADAccount

`-Days` gündür (varsayılan 90) oturum açmamış AD kullanıcı ve bilgisayar hesaplarını bulur. Hiç oturum açmamış hesaplar, eşik tarihinden önce oluşturulmuşlarsa rapora girer; yeni açılmış hesaplar raporlanmaz. Devre dışı hesaplar yalnızca `-IncludeDisabled` ile gelir.

```powershell
Get-StaleADAccount -Days 120 |
    Format-Table SamAccountName, ObjectClass, LastLogonDate, DaysSinceLastLogon, NeverLoggedOn
```

```text
SamAccountName ObjectClass LastLogonDate        DaysSinceLastLogon NeverLoggedOn
-------------- ----------- -------------        ------------------ -------------
ayilmaz        user        2.05.2026 08:14:51                  159         False
temp.intern    user                                                         True
WS-0142$       computer    11.03.2026 17:40:02                 210         False
```

```powershell
# Belirli OU'lar; pipeline'dan gelen her OU ayrı ayrı aranır
Get-ADOrganizationalUnit -Filter 'Name -like "Branch*"' | Get-StaleADAccount -AccountType Computer -Days 180
```

> Son oturum tarihi `lastLogonTimestamp` özniteliğinden okunur. Bu değer tüm DC'lere replike olur ama 9–14 gün gecikebilir; bu yüzden 14 günden kısa eşikler anlamlı değildir.

### Get-PasswordExpiryReport

Şifresi `-Days` gün (varsayılan 14) içinde dolacak AD kullanıcılarını listeler. Süre `msDS-UserPasswordExpiryTimeComputed` özniteliğinden okunduğu için ince ayarlı şifre ilkeleri (PSO) de hesaba katılır. Özel değerler ayrı ele alınır:

| Değer | Anlamı | Rapordaki karşılığı |
|---|---|---|
| `0` | Kullanıcı bir sonraki oturum açışta şifresini değiştirmeli | Her zaman listelenir, `Status = MustChangePassword` |
| `9223372036854775807` (maksimum Int64) | Şifre süresiz | Listelenmez |
| Geçmiş bir tarih | Şifrenin süresi dolmuş | Yalnızca `-IncludeExpired` ile listelenir, `Status = Expired` |
| `-Days` gün içinde bir tarih | Süresi yaklaşıyor | `Status = Expiring` |

```powershell
Get-PasswordExpiryReport -Days 14 |
    Format-Table SamAccountName, EmailAddress, PasswordExpires, DaysUntilExpiry, Status
```

```text
SamAccountName EmailAddress          PasswordExpires      DaysUntilExpiry Status
-------------- ------------          ---------------      --------------- ------
mkaya          mkaya@contoso.com     12.10.2026 09:12:44                4 Expiring
edemir         edemir@contoso.com    19.10.2026 16:03:10               11 Expiring
new.hire       new.hire@contoso.com                                       MustChangePassword
```

### Disable-DepartingUser

İşten ayrılan bir kullanıcı için şu adımları **bu sırayla** uygular:

1. Grup üyeliklerini (`memberOf`) `-BackupDirectory` içine CSV olarak kaydeder. **Yedek yazılamazsa kullanıcıya hiç dokunulmaz.**
2. Kullanıcıyı bu gruplardan çıkarır. Birincil grup (genellikle Domain Users) `memberOf` içinde olmadığı için korunur.
3. Hesabı devre dışı bırakır.
4. Açıklamanın başına tarih yazar: `Disabled 2026-10-08 - <eski açıklama>`. Ön ek `-DescriptionPrefix` ile değiştirilebilir.
5. `-TargetOU` verildiyse hesabı o OU'ya taşır. OU'nun varlığı, hiçbir kullanıcı değiştirilmeden önce kontrol edilir.

Yapılan her işlem ve her hata, zaman, işlemi yapan kişi ve hedef hesapla birlikte log dosyasına yazılır. Varsayılan log dosyası `-BackupDirectory\Disable-DepartingUser.log`, `-LogPath` ile değiştirilebilir. Adımlar tekrar çalıştırılabilir: zaten devre dışı olan hesap yeniden devre dışı bırakılmaz, aynı gün iki kez tarih yazılmaz, zaten hedef OU'da olan hesap taşınmaz.

```powershell
Disable-DepartingUser -Identity jdoe -BackupDirectory D:\Offboarding -TargetOU 'OU=Disabled Users,DC=contoso,DC=com'
```

Örnek sonuç nesnesi:

```text
SamAccountName     : jdoe
DistinguishedName  : CN=John Doe,OU=Sales,DC=contoso,DC=com
Status             : Completed
Disabled           : True
DescriptionUpdated : True
GroupsRemoved      : {CN=Sales,OU=Groups,DC=contoso,DC=com, CN=VPN Users,OU=Groups,DC=contoso,DC=com}
GroupsFailed       : {}
MovedTo            : OU=Disabled Users,DC=contoso,DC=com
BackupFile         : D:\Offboarding\jdoe_groups_20261008-093748.csv
LogFile            : D:\Offboarding\Disable-DepartingUser.log
Errors             : {}
```

Örnek log:

```text
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Processing started. DN: CN=John Doe,OU=Sales,DC=contoso,DC=com; enabled: True; groups: 2.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Backed up 2 group membership(s) to 'D:\Offboarding\jdoe_groups_20261008-093748.csv'.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Removed from group 'CN=Sales,OU=Groups,DC=contoso,DC=com'.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Removed from group 'CN=VPN Users,OU=Groups,DC=contoso,DC=com'.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Account disabled.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Description changed from 'Sales representative' to 'Disabled 2026-10-08 - Sales representative'.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Moved from 'OU=Sales,DC=contoso,DC=com' to 'OU=Disabled Users,DC=contoso,DC=com'.
2026-10-08 09:37:48 +03:00 | INFO  | CONTOSO\it.admin | jdoe | Processing finished: Completed.
```

Bir adım başarısız olursa (örneğin bir gruptan çıkarma yetkisi yoksa) hata loglanır ve hata akışına yazılır. Kalan adımlar yine de çalışır ve `Status` değeri `CompletedWithErrors` olur. Grup yedeği CSV olduğu için üyelikler gerektiğinde geri yüklenebilir:

```powershell
Import-Csv D:\Offboarding\jdoe_groups_20261008-093748.csv |
    ForEach-Object { Add-ADGroupMember -Identity $_.GroupDistinguishedName -Members $_.SamAccountName }
```

### Export-ITReport

Tüm komutların çıktısını CSV'ye veya tek dosyalık bir HTML rapora aktarır. Biçim dosya uzantısından anlaşılır, istenirse `-Format` ile belirtilir.

- CSV dosyaları BOM'lu UTF-8 olarak yazılır, böylece Türkçe karakterler Excel'de bozulmaz. Excel'in liste ayırıcısı noktalı virgül olan sistemler için `-Delimiter ';'` kullanılabilir.
- HTML raporda `-HighlightProperty` ile verilen özelliği `True` olan satırlar renklendirilir.
- Diziler `; ` ile birleştirilir, tarihler `yyyy-MM-dd HH:mm:ss` biçiminde yazılır.

```powershell
Get-DiskSpaceReport -ComputerName SRV01, SRV02 |
    Export-ITReport -Path .\disks.html -Title 'Disk doluluk raporu' -HighlightProperty BelowThreshold

Get-PasswordExpiryReport -Days 7 |
    Export-ITReport -Path .\password-expiry.csv -Delimiter ';' -Property SamAccountName, EmailAddress, PasswordExpires, Status
```

## -WhatIf ve -Confirm

`Disable-DepartingUser` değişiklik yapan tek komuttur ve `SupportsShouldProcess` (ConfirmImpact = High) destekler:

- **`-WhatIf`**: Hiçbir değişiklik yapmaz ve hiçbir dosya yazmaz (yedek ve log dahil). Yalnızca yapılacak her adımı gösterir.
- **Varsayılan davranış**: Her değişiklikten önce onay ister. "Tümüne Evet" (`A`) ile kalan adımlar onaylanabilir.
- **`-Confirm:$false`**: Betiklerde onay sormadan çalıştırır.

```powershell
Disable-DepartingUser -Identity jdoe -BackupDirectory D:\Offboarding -TargetOU 'OU=Disabled Users,DC=contoso,DC=com' -WhatIf
```

```text
What if: Performing the operation "Back up 2 group membership(s) of 'jdoe'" on target "D:\Offboarding\jdoe_groups_20261008-093748.csv".
What if: Performing the operation "Remove 'jdoe' from group" on target "CN=Sales,OU=Groups,DC=contoso,DC=com".
What if: Performing the operation "Remove 'jdoe' from group" on target "CN=VPN Users,OU=Groups,DC=contoso,DC=com".
What if: Performing the operation "Disable account" on target "jdoe".
What if: Performing the operation "Set description to 'Disabled 2026-10-08 - Sales representative'" on target "jdoe".
What if: Performing the operation "Move to 'OU=Disabled Users,DC=contoso,DC=com'" on target "jdoe".
```

Bir CSV listesindeki tüm ayrılan kullanıcılar için önce `-WhatIf` ile kontrol edip ardından onay sormadan çalıştırmak:

```powershell
$leavers = Import-Csv .\leavers.csv   # SamAccountName sütunu
$leavers | Disable-DepartingUser -BackupDirectory D:\Offboarding -TargetOU 'OU=Disabled Users,DC=contoso,DC=com' -WhatIf
$leavers | Disable-DepartingUser -BackupDirectory D:\Offboarding -TargetOU 'OU=Disabled Users,DC=contoso,DC=com' -Confirm:$false
```

`Export-ITReport` de `-WhatIf` destekler.

## Testler ve kod kalitesi

- **Pester 5** testleri tüm CIM, Active Directory ve uzak bağlantı çağrılarını mock'lar. Gerçek bir sunucu, AD veya RSAT gerekmez.
- **PSScriptAnalyzer** depodaki tüm betikleri `PSScriptAnalyzerSettings.psd1` ayarlarıyla tarar. Tek bir bulgu bile derlemeyi başarısız sayar.
- **GitHub Actions** her push ve pull request'te Windows PowerShell 5.1 ve PowerShell 7 üzerinde analiz ve testleri çalıştırır.

Yerelde çalıştırmak için:

```powershell
./build.ps1                    # Bootstrap + Analyze + Test
./build.ps1 -Task Analyze      # yalnızca PSScriptAnalyzer
./build.ps1 -Task Test         # yalnızca Pester (sonuçlar TestResults\ klasörüne yazılır)
```

Klasör yapısı:

```text
ITToolkit/
  ITToolkit.psd1, ITToolkit.psm1
  Public/      dışa açılan komutlar (her komut ayrı dosyada)
  Private/     yardımcı fonksiyonlar (CIM bağlantısı, log, AD modül kontrolü...)
Tests/         Pester testleri ve AD cmdlet stub'ları
build.ps1      bootstrap / analiz / test
```

## Lisans

[MIT](LICENSE) © 2026 Muhammet Can Topaloğlu
