# Segnox VM testi - HOST tarafi
#
# Ne yapar:
#   1) (hazirlik disindaki senaryolarda) veritabani + sunucuyu acar (0.0.0.0:8080)
#   2) Katilim kodu uretir
#   3) Konukta calisacak betigi paylasim klasorune yazar (calis.ps1)
#   4) Konukta SYSTEM zamanlanmis gorev (1 dk) betigi alip calistirir (poller.ps1)
#   5) Asama dosyalariyla (sonuc\faz-*.txt) konukla eslesir, sonucu bekler ve basar
#   6) Sonunda sunucuyu/DB'yi kapatir, calis.ps1 ve gecici anahtarlari siler
#
# Kullanim (host, normal PowerShell):
#   .\vm-test.ps1 -Senaryo hazirlik    Windows Update + otomatik yeniden baslatma kapatilir
#   .\vm-test.ps1 -Senaryo servis      K-26 servis kurulumu: surec sahipleri, sc qc, icacls
#   .\vm-test.ps1 -Senaryo siyah       K-32 siyah ekran: ortam + izleyici URL'si + kontrol listesi
#   .\vm-test.ps1 -Senaryo izleyici    K-34 coklu izleyici: ortam + iki URL (Baglan + Izle)
#   .\vm-test.ps1 -Senaryo guncelleme  K-33 imzali guncelleme: 1.0.0 -> 1.0.1 -> bozuk 1.0.2 geri alma
#   .\vm-test.ps1 -Senaryo devam       K-27 cihaz parolasi + yeniden baslat + devam kaniti
#   .\vm-test.ps1 -Senaryo ortam       yalniz sunucu+kod hazirlar (konuk betigi yok)
#
# Parametreler:
#   -BekleDakika N     konuk sonucu icin bekleme (0 = senaryo varsayilani)
#   -VmParola <p>      vmrun sifreleme parolasi (varsayilan: $env:SEGNOX_VMRUN_PAROLA; betige gomulmez)
#   -SadeceBetikUret D konuk betiklerini D klasorune uretir (sahte degerlerle), baska hicbir sey baslatmaz
#
# ONCE: konukta bir kez bootstrap calistirilmis olmali (bkz. vm-paylasim\bootstrap.ps1)

param(
  [ValidateSet('hazirlik','servis','siyah','izleyici','guncelleme','devam','ortam')] [string]$Senaryo = 'servis',
  [int]$BekleDakika = 0,
  [string]$VmParola = $env:SEGNOX_VMRUN_PAROLA,
  [string]$SadeceBetikUret = ''
)

$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\Erayc\Desktop\segnox-uzaktan-erisim'
$pay  = 'C:\Users\Erayc\Desktop\segnox-site\.tools\vm-paylasim'
$pkg  = 'C:\Users\Erayc\Desktop\segnox-site\.tools\vm-paket'
$vmrun = 'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
$sonucD = Join-Path $pay 'sonuc'

function Say ($s) { Write-Host $s }
function Adim ($s) { Write-Host "`n=== $s ===" -ForegroundColor Cyan }
function Kisa ($s) { if ($s -and $s.Length -gt 12) { $s.Substring(0,8) + '...' } else { '***' } }

# varsayilan bekleme (dk): guncelleme uzun surer (10 dk deneme penceresi + geri alma)
if ($BekleDakika -le 0) {
  $BekleDakika = switch ($Senaryo) { 'guncelleme' { 60 } 'siyah' { 40 } 'izleyici' { 40 } 'hazirlik' { 4 } default { 12 } }
}

# =========================================================== KONUK BETIKLERI
# Tek tirnakli here-string: icinde $ ve ` oldugu gibi kalir. Yer tutucular @@AD@@ ile degistirilir.
# Konuk PowerShell 5.1 (SYSTEM). Yalniz ASCII.
$konukOnsoz = @'
$ErrorActionPreference = 'Continue'
$Sonuc  = '\\vmware-host\Shared Folders\segnox-calisma\sonuc'
$Paket  = '\\vmware-host\Shared Folders\segnox-paket'
$Prog   = 'C:\Program Files\Segnox'
$Veri   = 'C:\ProgramData\Segnox'
$Yerel  = 'C:\segnox-test'
$Canli  = Join-Path $Sonuc 'canli.log'
function Y ($m) {
  $s = "{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  Write-Host $s
  try { Add-Content -Path $Canli -Value $s -Encoding ASCII } catch {}
}
function Faz ($ad) {
  try { ('tamam ' + (Get-Date -Format 'HH:mm:ss')) | Out-File (Join-Path $Sonuc ("faz-$ad.txt")) -Encoding ASCII }
  catch { Y ("faz yazilamadi: " + $ad) }
}
function BitirIstendi { Test-Path (Join-Path $Sonuc 'bitir.txt') }
function KisaKod ($k) { if ($k -and $k.Length -gt 12) { $k.Substring(0,8) + '...' } else { '***' } }
function AjanLog {
  Get-ChildItem (Join-Path $Veri 'logs') -Filter *.log -ErrorAction SilentlyContinue | ForEach-Object {
    Get-Content $_.FullName -Tail 800 -ErrorAction SilentlyContinue }
}
function LogAra ($desen) { @(AjanLog | Where-Object { $_ -match $desen }) }
function LogBekle ($desen, $dk) {
  $son = (Get-Date).AddMinutes($dk)
  while ((Get-Date) -lt $son) {
    $m = LogAra $desen
    if ($m.Count -gt 0) { return $m }
    Start-Sleep -Seconds 5
  }
  return @()
}
function LogBas ($baslik, $desen, $en) {
  Y ("--- " + $baslik + " ---")
  $m = LogAra $desen
  if ($m.Count -eq 0) { Y '  (eslesen satir yok)' }
  else { $m | Select-Object -Last $en | ForEach-Object { Y ("  " + $_) } }
}
function Surecler {
  Get-CimInstance Win32_Process -Filter "Name='segnox-agent.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
    $o = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction SilentlyContinue
    $sahip = if ($o -and $o.User) { "$($o.Domain)\$($o.User)" } else { '?' }
    $cl = [string]$_.CommandLine
    $rol = if ($cl -match '\bhelper\b') { 'helper' } elseif ($cl -match 'ui-host') { 'ui-host' } elseif ($cl -match '\bservice\b') { 'service' } else { 'diger' }
    [pscustomobject]@{ Pid = $_.ProcessId; Rol = $rol; Sahip = $sahip }
  }
}
# Test icin: kok sertifikayi host'tan indir ve guvenilir koka ekle.
# (Ajan, loopback disindaki sunucu icin https zorunlu tutuyor - K-21)
try {
  $caTmp = Join-Path $Yerel 'ca.der'
  Invoke-WebRequest 'http://192.168.79.1:8081/ca.der' -OutFile $caTmp -TimeoutSec 60
  $rr = certutil.exe -addstore -f Root $caTmp 2>&1
  if ($LASTEXITCODE -eq 0) { Y 'kok sertifika indirildi ve guvenilir koka eklendi' }
  else { Y ('kok sertifika kurulamadi: ' + (($rr | Select-Object -Last 2) -join ' ')) }
} catch { Y ('kok sertifika alinamadi: ' + $_.Exception.Message) }

# Eski senaryoyu calistirma: host'taki run id ile bu betigin run id'si karsilastirilir
try {
  $yani = (Invoke-WebRequest 'http://192.168.79.1:8081/run-id.txt' -UseBasicParsing -TimeoutSec 20).Content.Trim()
  if ($yani -ne '@@RUNID@@') {
    Y ("ESKI SENARYO - atlandi (konuk: " + $yani + ", bu: @@RUNID@@)")
    exit 0
  }
  Y ("run id dogrulandi: " + $yani)
  Get-ChildItem $Sonuc -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'faz-*.txt' -or $_.Name -eq 'Bitti.txt' } |
    Remove-Item -Force -ErrorAction SilentlyContinue
} catch { Y ('run id alinamadi, devam ediliyor: ' + $_.Exception.Message) }

function Kur ($kaynak, $tok, $sunucu, $ad) {
  # Test icin: guvenilen kok sertifika (TLS proxy) varsa kur
  $ca = Join-Path $Paket 'ca.der'
  if (-not (Test-Path $ca)) { $ca = 'C:\segnox-test\incoming\ca.der' }
  if (Test-Path $ca) {
    $r = certutil.exe -addstore -f Root $ca 2>&1
    if ($LASTEXITCODE -eq 0) { Y ('kok sertifika kuruldu: ' + $ca) }
    else { Y ("kok sertifika kurulamadi: " + (($r | Select-Object -Last 2) -join ' ')) }
  } else { Y 'kok sertifika bulunamadi (paket/incoming) - https baglantisi reddedilir' }
  $svc = Get-Service -Name 'SegnoxAgent' -ErrorAction SilentlyContinue
  if ($svc) {
    Y 'onceki kurulum kaldiriliyor (/UNINSTALL /S)'
    $u = Join-Path $Prog 'segnox-agent.exe'
    if (Test-Path $u) { Start-Process -FilePath $u -ArgumentList @('/UNINSTALL','/S') -Wait | Out-Null }
    Start-Sleep -Seconds 3
  }
  Remove-Item $Veri -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory $Yerel -Force | Out-Null
  $dst = Join-Path $Yerel 'segnox-agent.exe'
  if (-not (Test-Path $kaynak)) { Y ("HATA: paylasimda yok: " + $kaynak); return $false }
  Copy-Item $kaynak $dst -Force
  Y ("ajan kopyalandi: " + (Split-Path $kaynak -Leaf))
  Y ("servis kuruluyor (sessiz); katilim kodu " + (KisaKod $tok))
  $env:SEGNOX_ENROLL_TOKEN = $tok
  $cOut = Join-Path $Yerel 'kurulum.out'
  $cErr = Join-Path $Yerel 'kurulum.err'
  $p = Start-Process -FilePath $dst -ArgumentList @('/S', "/SERVER=$sunucu", "/NAME=$ad") -Wait -PassThru -RedirectStandardOutput $cOut -RedirectStandardError $cErr
  Remove-Item Env:\SEGNOX_ENROLL_TOKEN -ErrorAction SilentlyContinue
  Y ("kurulum cikis kodu: " + $p.ExitCode)
  $kurulu = Join-Path $Prog 'segnox-agent.exe'
  if (Test-Path $kurulu) {
    $sv = [string](& $kurulu version 2>&1 | Select-Object -First 1)
    Y ("kurulu surum: " + $sv)
    $bekSurum = '@@SURUM@@'
    if ($bekSurum -and (Split-Path $kaynak -Leaf) -eq 'segnox-agent.exe' -and $sv -ne $bekSurum) {
      Y ("HATA: kurulu surum host'takiyle ayni degil (beklenen: " + $bekSurum + ")")
      return $false
    }
  }
  foreach ($f in @($cOut, $cErr)) {
    if (Test-Path $f) {
      Get-Content $f -ErrorAction SilentlyContinue | Select-Object -Last 15 | ForEach-Object { Y ("  kurulum: " + $_) }
    }
  }
  return ($p.ExitCode -eq 0)
}
function AclDenetle ($yol, $ad) {
  Y ("--- icacls " + $ad + " ---")
  $acl = (icacls.exe $yol 2>&1) | ForEach-Object { [string]$_ }
  $acl | ForEach-Object { Y ("  " + $_) }
  $kotu = @()
  foreach ($l in $acl) {
    $t = $l.Replace($yol, '').Trim()
    if ($t -match '^(.+?):\([A-Z]') {
      $pr = $Matches[1].Trim()
      if ($pr -notmatch '^(NT AUTHORITY\\SYSTEM|BUILTIN\\Administrators|CREATOR OWNER)$') { $kotu += $pr }
    }
  }
  if ($kotu.Count -eq 0) { Y ("OK: " + $ad + " yalniz SYSTEM + Administrators") }
  else { Y ("UYARI: beklenmeyen ACL girdisi: " + (($kotu | Select-Object -Unique) -join ', ')) }
}
function Dogrula {
  Y '--- servis ---'
  $svc = Get-Service -Name 'SegnoxAgent' -ErrorAction SilentlyContinue
  if ($svc) { Y ("servis durumu: " + $svc.Status) } else { Y 'HATA: SegnoxAgent servisi yok' }
  $qc = (sc.exe qc SegnoxAgent 2>&1) | ForEach-Object { [string]$_ }
  $qc | ForEach-Object { Y ("  " + $_) }
  if (($qc -join ' ') -match 'LocalSystem' -and ($qc -join ' ') -match 'AUTO_START') { Y 'OK: LocalSystem + otomatik baslangic' } else { Y 'UYARI: LocalSystem/otomatik degil' }
  Start-Sleep -Seconds 5
  Y '--- surecler (rol / sahip) ---'
  $sl = @(Surecler)
  if ($sl.Count -eq 0) { Y 'HATA: segnox-agent sureci yok' }
  $sl | ForEach-Object { Y ("  pid=" + $_.Pid + " rol=" + $_.Rol + " sahip=" + $_.Sahip) }
  $h = @($sl | Where-Object { $_.Rol -eq 'helper' })
  $u = @($sl | Where-Object { $_.Rol -eq 'ui-host' })
  if ($h.Count -gt 0 -and @($h | Where-Object { $_.Sahip -notmatch 'SYSTEM' }).Count -eq 0) { Y 'OK: helper SYSTEM olarak' } else { Y 'UYARI: helper yok ya da SYSTEM degil (kullanici oturumu acik mi?)' }
  if ($u.Count -gt 0 -and @($u | Where-Object { $_.Sahip -match 'SYSTEM' }).Count -eq 0) { Y 'OK: ui-host kullanici olarak' } else { Y 'UYARI: ui-host yok ya da SYSTEM (kullanici oturumu acik mi?)' }
  AclDenetle $Veri 'ProgramData\Segnox'
}
function Temizle {
  # parola/kod iceren betigin yerel kopyasini silecek gizli surec (bu betik bittikten sonra)
  Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-Command',
    "Start-Sleep 25; Remove-Item 'C:\segnox-test\calis.ps1' -Force -ErrorAction SilentlyContinue") | Out-Null
}
# Ayni kosu bir kez: konuktaki poller betigi yeniden calistirsa da (eski poller surumu,
# kendini silen calis.ps1) kurulum tekrarlanmaz; her tekrar yeni cihaz kaydi + katilim kodu harciyordu.
$KosuIsaret = 'C:\segnox-test\kosu-@@RUNID@@.txt'
if (Test-Path $KosuIsaret) { exit 0 }
New-Item -ItemType Directory 'C:\segnox-test' -Force | Out-Null
'basladi' | Out-File $KosuIsaret -Encoding ASCII
Y ("=== KONUK basliyor (@@SENARYO@@) kullanici: " + [Security.Principal.WindowsIdentity]::GetCurrent().Name + " ===")
# Paket esitleme: host'taki paket.sha256 ile yerel paket karsilastirilir, farkli ya da eksik dosya
# yeniden indirilir (eski poller dosya varsa hic indirmiyordu: konuk eski ajani kuruyordu).
New-Item -ItemType Directory 'C:\segnox-test\paket' -Force | Out-Null
try {
  $ozet = (Invoke-WebRequest 'http://192.168.79.1:8081/paket.sha256' -UseBasicParsing -TimeoutSec 20).Content
  if ($ozet -is [byte[]]) { $ozet = [Text.Encoding]::ASCII.GetString($ozet) }
  foreach ($satir in ($ozet -split "`r?`n")) {
    if ($satir -notmatch '^([0-9a-f]{64})\s+(\S+)$') { continue }
    $bek = $Matches[1]; $ad = $Matches[2]
    $hedef = Join-Path 'C:\segnox-test\paket' $ad
    $var = if (Test-Path $hedef) { (Get-FileHash $hedef -Algorithm SHA256).Hash.ToLower() } else { '' }
    if ($var -eq $bek) { Y ("paket guncel: " + $ad); continue }
    $tmp = $hedef + '.indir'
    Invoke-WebRequest ('http://192.168.79.1:8081/' + $ad) -OutFile $tmp -UseBasicParsing -TimeoutSec 300
    if ((Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower() -ne $bek) {
      Remove-Item $tmp -Force -ErrorAction SilentlyContinue
      Y ("HATA: indirilen " + $ad + " ozeti tutmuyor")
      continue
    }
    Move-Item $tmp $hedef -Force
    Y ("paket yenilendi: " + $ad)
  }
} catch { Y ('HATA: paket esitlenemedi: ' + $_.Exception.Message) }
'@

$konukGovde = @{}

$konukGovde['hazirlik'] = @'
Y '--- Windows Update + otomatik yeniden baslatma kapatiliyor ---'
foreach ($s in 'wuauserv','UsoSvc','WaaSMedicSvc') {
  try { Stop-Service $s -Force -ErrorAction SilentlyContinue } catch {}
  & sc.exe config $s start= disabled 2>&1 | ForEach-Object { Y ("  sc config " + $s + ": " + $_) }
  try { Set-Service $s -StartupType Disabled -ErrorAction Stop } catch { Y ("  Set-Service " + $s + ": " + $_.Exception.Message) }
}
# WaaSMedicSvc kendini geri acabilir: kayit defterinde Start=4
try { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name Start -Value 4 -ErrorAction Stop; Y '  WaaSMedicSvc Start=4 yazildi' }
catch { Y ("  WaaSMedicSvc kayit defteri yazilamadi (TrustedInstaller sahibi olabilir): " + $_.Exception.Message) }
# politikalar
$au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
New-Item -Path $au -Force | Out-Null
New-ItemProperty -Path $au -Name NoAutoRebootWithLoggedOnUsers -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $au -Name NoAutoUpdate -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $au -Name AUOptions -Value 1 -PropertyType DWord -Force | Out-Null
# yeniden baslatma gorevleri (en iyi caba)
Get-ScheduledTask -TaskPath '\Microsoft\Windows\UpdateOrchestrator\*' -ErrorAction SilentlyContinue |
  ForEach-Object { try { Disable-ScheduledTask -InputObject $_ -ErrorAction Stop | Out-Null; Y ("  gorev kapatildi: " + $_.TaskName) } catch {} }
# Guncellemeleri 10 yil duraklat (Ayarlar > Windows Update > Duraklat ile ayni anahtarlar);
# servis kendini geri acsa bile kurulum/yeniden baslatma yapmaz.
$ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
New-Item -Path $ux -Force | Out-Null
$bas = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$son = (Get-Date).AddYears(10).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
foreach ($n in 'PauseUpdatesStartTime','PauseFeatureUpdatesStartTime','PauseQualityUpdatesStartTime') { New-ItemProperty -Path $ux -Name $n -Value $bas -PropertyType String -Force | Out-Null }
foreach ($n in 'PauseUpdatesExpiryTime','PauseFeatureUpdatesEndTime','PauseQualityUpdatesEndTime') { New-ItemProperty -Path $ux -Name $n -Value $son -PropertyType String -Force | Out-Null }
New-ItemProperty -Path $ux -Name FlightSettingsMaxPauseDays -Value 3650 -PropertyType DWord -Force | Out-Null
Y ("  guncellemeler duraklatildi: " + $son)
Get-ScheduledTask -TaskPath '\Microsoft\Windows\WindowsUpdate\*' -ErrorAction SilentlyContinue |
  ForEach-Object { try { Disable-ScheduledTask -InputObject $_ -ErrorAction Stop | Out-Null; Y ("  gorev kapatildi: " + $_.TaskName) } catch {} }
Y '--- son yeniden baslatmalar (1074 kim/neden, 6008 beklenmeyen kapanis, 41 guc kaybi) ---'
try {
  Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1074, 6008, 41 } -MaxEvents 10 -ErrorAction Stop | ForEach-Object {
    $m = (($_.Message -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 2) -join ' '
    if ($m.Length -gt 300) { $m = $m.Substring(0, 300) }
    Y ("  " + $_.TimeCreated.ToString('dd.MM HH:mm') + " [" + $_.Id + "] " + $m)
  }
} catch { Y ("  olay gunlugu okunamadi: " + $_.Exception.Message) }
Y '--- KANIT ---'
foreach ($s in 'wuauserv','UsoSvc','WaaSMedicSvc') {
  $v = Get-Service $s -ErrorAction SilentlyContinue
  $st = (Get-ItemProperty ("HKLM:\SYSTEM\CurrentControlSet\Services\" + $s) -ErrorAction SilentlyContinue).Start
  if ($v) { Y ("  " + $s + ": durum=" + $v.Status + " baslangic(kayit)=" + $st) } else { Y ("  " + $s + ": yok") }
}
$p = Get-ItemProperty $au
Y ("  NoAutoRebootWithLoggedOnUsers=" + $p.NoAutoRebootWithLoggedOnUsers + " NoAutoUpdate=" + $p.NoAutoUpdate)
Faz 'hazirlik'
'@

$konukGovde['servis'] = @'
$ok = Kur (Join-Path $Paket 'segnox-agent.exe') '@@TOKEN@@' '@@SUNUCU@@' 'VM-Test'
if ($ok) {
  Dogrula
  Y '--- ui-host teshisi icin 40 sn bekleniyor ---'
  Start-Sleep -Seconds 40
  LogBas 'helper: ui-host satirlari' 'helper started|ui-host' 60
  Y '--- ui-host cikti dosyalari (ProgramData, en yeni 3) ---'
  Get-ChildItem (Join-Path $Veri 'logs') -Filter 'ui-host-*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object {
      Y ("  == " + $_.Name)
      Get-Content $_.FullName -Tail 40 -ErrorAction SilentlyContinue | ForEach-Object { Y ("    " + $_) }
    }
  Y '--- ui-host kullanici loglari ---'
  $ul = @(Get-ChildItem 'C:\Users\*\AppData\Local\Segnox\logs\ui-host.log' -ErrorAction SilentlyContinue)
  if ($ul.Count -eq 0) { Y '  (yok)' }
  $ul | ForEach-Object {
    Y ("  == " + $_.FullName)
    Get-Content $_.FullName -Tail 30 -ErrorAction SilentlyContinue | ForEach-Object { Y ("    " + $_) }
  }
  Dogrula
}
Y '--- ajan logu (son 20 satir) ---'
AjanLog | Select-Object -Last 20 | ForEach-Object { Y ("  " + $_) }
Faz 'kurulum'
'@

$konukGovde['siyah'] = @'
$ok = Kur (Join-Path $Paket 'segnox-agent.exe') '@@TOKEN@@' '@@SUNUCU@@' 'VM-Siyah'
if ($ok) { Dogrula }
Faz 'kurulum'
Y 'host tarafinda siyah ekran denemesi bekleniyor (host Enter verince biter, en cok 35 dk)...'
$son = (Get-Date).AddMinutes(35)
while ((Get-Date) -lt $son -and -not (BitirIstendi)) { Start-Sleep -Seconds 5 }
LogBas 'siyah ekran kayitlari (K-32)' 'privacy mode' 40
$on  = (LogAra 'privacy mode on').Count
$off = (LogAra 'privacy mode off').Count
Y ("OTOMATIK KANIT: siyah ekran acildi=" + $on + " kapandi=" + $off)
if ($on -gt 0 -and $off -ge $on) { Y 'OK: acildi ve kapandi' } elseif ($on -gt 0) { Y 'UYARI: acildi ama kapanma satiri yok (hala acik ya da kalkmadi!)' } else { Y 'EKSIK: siyah ekran hic acilmadi' }
Y '--- GOZLE KONTROL LISTESI (K-32, ACIK #16) ---'
Y ' 1) Onayli oturumda teknisyen "Ekrani karart" -> musteriye ikinci onay -> yerelde siyah ekran + uyari'
Y ' 2) Cubuk ustte ve "Baglantiyi kes" tiklanabilir; teknisyen masaustunu normal gorur ve kontrol eder'
Y ' 3) Win+L / UAC -> goruntuleyicide "musteri su an gorebilir", cikinca yeniden gizli'
Y ' 4) VM ag baglantisini kes (adaptor ayir) -> yerel siyah ekran hemen kalkar'
Y ' 5) Gorev Yoneticisinden ajan/ui-host oldur -> siyah ekran kalkar'
Y ' 6) Iki monitor varsa ikisi de kararir (VM tek monitor ise atla)'
Y '=== KONUK bitti ==='
'@

$konukGovde['izleyici'] = @'
$ok = Kur (Join-Path $Paket 'segnox-agent.exe') '@@TOKEN@@' '@@SUNUCU@@' 'VM-Izleyici'
if ($ok) { Dogrula }
Faz 'kurulum'
Y 'host tarafinda iki goruntuleyici (Baglan + Izle) bekleniyor (host Enter verince biter, en cok 35 dk)...'
$son = (Get-Date).AddMinutes(35)
while ((Get-Date) -lt $son -and -not (BitirIstendi)) { Start-Sleep -Seconds 5 }
LogBas 'oturum/izleyici kayitlari (K-34)' 'viewer|observer|peer|session' 40
Y '--- GOZLE KONTROL LISTESI (K-34, ACIK #18) ---'
Y ' 1) Musteri cubugunda "2 kisi bagli: 1 kontrol, 1 izliyor" satiri tasmadan gorunur (panel acikken de)'
Y ' 2) Goruntuleyicilerde "2 kisi bagli (1 izliyor)"'
Y ' 3) Izleme sekmesi kapaninca iki taraf da guncellenir (1 kisi)'
Y ' 4) Izleyen sekmeden fare/klavye uzaga GITMEZ'
Y '=== KONUK bitti ==='
'@

$konukGovde['guncelleme'] = @'
# --- 1.0.0 kurulumu (genel anahtar gomulu); sunucuda 1.0.1 imzali surum hazir ---
$ok = Kur (Join-Path $Paket 'segnox-agent-1.0.0.exe') '@@TOKEN@@' '@@SUNUCU@@' 'VM-Guncelleme'
if ($ok) { Dogrula }
Faz 'kurulum'
# --- 1.0.1: host konsolu "Guncelle" gibi POST /devices/{id}/update yollar ---
Y 'host guncelleme sinyalini gonderince 1.0.1 beklenecek (en cok 20 dk)...'
$m = LogBekle 'update installed' 20
LogBas 'guncelleme zinciri (available -> downloaded -> applied -> installed)' 'update (available|downloaded|applied|installed)' 12
if ($m.Count -gt 0) { Y 'OK: update installed goruldu' } else { Y 'EKSIK: 20 dk icinde update installed yok' }
Y '--- Program Files\Segnox (.old beklenir: installed sonrasi silinir) ---'
Get-ChildItem $Prog -Force -ErrorAction SilentlyContinue | ForEach-Object { Y ("  " + $_.Name + "  " + $_.Length) }
Y '--- icacls yeni exe (Users RX, yazma yok) ---'
$e = Join-Path $Prog 'segnox-agent.exe'
(icacls.exe $e 2>&1) | ForEach-Object { Y ("  " + $_) }
Y '--- surecler ---'
@(Surecler) | ForEach-Object { Y ("  pid=" + $_.Pid + " rol=" + $_.Rol + " sahip=" + $_.Sahip) }
Faz 'guncel'
# --- bozuk 1.0.2: host sunucuya koyar ve sinyal yollar; geri alma beklenir ---
Y 'bozuk 1.0.2 bekleniyor; geri alma (update rolled back) en cok 25 dk...'
$r = LogBekle 'update rolled back' 25
LogBas 'tum guncelleme satirlari' 'update ' 30
if ($r.Count -gt 0) { Y 'OK: update rolled back goruldu' } else { Y 'EKSIK: 25 dk icinde update rolled back yok' }
Y '--- Program Files\Segnox (1.0.1 geri gelmis olmali) ---'
Get-ChildItem $Prog -Force -ErrorAction SilentlyContinue | ForEach-Object { Y ("  " + $_.Name + "  " + $_.Length) }
$sv = Get-Service SegnoxAgent -ErrorAction SilentlyContinue
if ($sv) { Y ("servis durumu: " + $sv.Status) }
@(Surecler) | ForEach-Object { Y ("  pid=" + $_.Pid + " rol=" + $_.Rol + " sahip=" + $_.Sahip) }
Faz 'geri'
Y '=== KONUK bitti ==='
'@

$konukGovde['devam'] = @'
$ok = Kur (Join-Path $Paket 'segnox-agent.exe') '@@TOKEN@@' '@@SUNUCU@@' 'VM-Devam'
if ($ok) { Dogrula }
$exe = Join-Path $Prog 'segnox-agent.exe'
$pw = '@@PAROLA@@'
$pw | & $exe set-password -service 2>&1 | ForEach-Object { Y ("set-password: " + $_) }
Y ("set-password cikis kodu: " + $LASTEXITCODE)
$pw = $null
# yeniden baslatmadan sonra kanit toplayacak tek seferlik gorev (SYSTEM, acilista)
Copy-Item '\\vmware-host\Shared Folders\segnox-calisma\devam-sonrasi.ps1' (Join-Path $Yerel 'devam-sonrasi.ps1') -Force
schtasks.exe /delete /tn SegnoxVMDevam /f 2>&1 | Out-Null
$r = schtasks.exe /create /tn SegnoxVMDevam /sc onstart /ru SYSTEM /rl highest /tr 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\segnox-test\devam-sonrasi.ps1' /f 2>&1
Y ("devam-sonrasi gorevi: " + $r)
Faz 'kurulum'
Y '=== KONUK bitti (yeniden baslatma sonrasi kanit: sonuc\devam-sonrasi.log) ==='
'@

$konukSon = @'
Temizle
'@

$devamSonrasi = @'
# Yeniden baslatma sonrasi tek seferlik kanit (SYSTEM, acilista). Kendini siler.
$Sonuc = '\\vmware-host\Shared Folders\segnox-calisma\sonuc'
$log = Join-Path $Sonuc 'devam-sonrasi.log'
function Y ($m) { try { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding ASCII } catch {} }
# paylasim ve servisin ayaga kalkmasini bekle (en cok 5 dk)
for ($i = 0; $i -lt 60; $i++) {
  if ((Test-Path $Sonuc) -and ((Get-Service SegnoxAgent -ErrorAction SilentlyContinue).Status -eq 'Running')) { break }
  Start-Sleep -Seconds 5
}
Start-Sleep -Seconds 60
Y '=== yeniden baslatma sonrasi ==='
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
Y ("son acilis: " + $boot + "  (calisma suresi dk: " + [int]((Get-Date) - $boot).TotalMinutes + ")")
Y ("servis: " + (Get-Service SegnoxAgent -ErrorAction SilentlyContinue).Status)
Get-CimInstance Win32_Process -Filter "Name='segnox-agent.exe'" | ForEach-Object {
  $o = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction SilentlyContinue
  Y ("surec pid=" + $_.ProcessId + " sahip=" + $o.User + " komut=" + ([string]$_.CommandLine -replace '\s+', ' ')) }
Y '--- ajan logu: yeniden baslatma / devam satirlari ---'
Get-ChildItem 'C:\ProgramData\Segnox\logs' -Filter *.log -ErrorAction SilentlyContinue | ForEach-Object {
  Get-Content $_.FullName -Tail 800 -ErrorAction SilentlyContinue } |
  Where-Object { $_ -match 'reboot|restart|resum|session|connected|enrolled|power|tray|window|ui-host|uiswitch' } | Select-Object -Last 60 |
  ForEach-Object { Y ("  " + $_) }
Y '=== bitti ==='
schtasks.exe /delete /tn SegnoxVMDevam /f 2>&1 | Out-Null
Remove-Item 'C:\segnox-test\devam-sonrasi.ps1' -Force -ErrorAction SilentlyContinue
'@

function Konuk-Betik ([string]$ad, [string]$tok, [string]$sunucu, [string]$parola) {
  $b = $konukOnsoz.Replace('@@SENARYO@@', $ad) + "`r`n" + $konukGovde[$ad] + "`r`n" + $konukSon
  $b = $b.Replace('@@TOKEN@@', $tok).Replace('@@SUNUCU@@', $sunucu).Replace('@@PAROLA@@', $parola)
  $b = $b.Replace('@@RUNID@@', $script:runId)
  $b = $b.Replace('@@SURUM@@', [string]$script:ajanSurum)
  # HGFS/paylasim klasoru konukta calismiyorsa yerel yol kullan
  # (konuktaki poller-http.ps1 dosyalari HTTP ile doldurur)
  $b = $b.Replace('\\vmware-host\Shared Folders\segnox-calisma\sonuc',      'C:\segnox-test\out')
  $b = $b.Replace('\\vmware-host\Shared Folders\segnox-paket',             'C:\segnox-test\paket')
  $b = $b.Replace('\\vmware-host\Shared Folders\segnox-calisma\devam-sonrasi.ps1', 'C:\segnox-test\incoming\devam-sonrasi.ps1')
  return $b
}

# yalniz betik uretimi (sozdizimi denetimi icin): hicbir sey baslatmaz
if ($SadeceBetikUret) {
  New-Item -ItemType Directory $SadeceBetikUret -Force | Out-Null
  foreach ($a in $konukGovde.Keys) {
    Set-Content -Path (Join-Path $SadeceBetikUret ("konuk-$a.ps1")) -Value (Konuk-Betik $a 'sge_ORNEKORNEKORNEKORNEK' 'http://192.168.79.1:8080' 'ornek-parola-1234') -Encoding UTF8
  }
  Set-Content -Path (Join-Path $SadeceBetikUret 'devam-sonrasi.ps1') -Value $devamSonrasi -Encoding UTF8
  Say "konuk betikleri uretildi: $SadeceBetikUret"
  return
}

# ================================================================ HOST AKISI
$script:dbProc = $null; $script:server = $null; $script:gecici = @(); $script:httpProc = $null

function Surec-Kapat ($p) {
  try { if ($p -and -not $p.HasExited) { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null } } catch {}
}

# Etkilesimsiz kosu: SEGNOX_VMTEST_BEKLE bir dosya yoluysa Enter yerine o dosyanin
# olusmasi beklenir (orkestrator arka planda kosturur, kullanici yalniz tarayiciya bakar).
function Kullanici-Bekle ([string]$mesaj) {
  $f = $env:SEGNOX_VMTEST_BEKLE
  if (-not $f) { [void](Read-Host $mesaj); return }
  Say ("  (bekleniyor: " + $f + " olusunca devam)  " + $mesaj)
  while (-not (Test-Path $f)) { Start-Sleep -Seconds 2 }
  Remove-Item $f -Force -ErrorAction SilentlyContinue
}

function Temizlik {
  Surec-Kapat $script:server
  try { if ($script:turnProc) { Surec-Kapat $script:turnProc } } catch {}
  try { if ($script:httpProc) { Surec-Kapat $script:httpProc } } catch {}
  try { if ($script:dbProc) { $script:dbProc.StandardInput.Close() } } catch {}   # devdb stdin EOF -> kendi postgres'ini kapatir
  Start-Sleep -Seconds 3
  Surec-Kapat $script:dbProc
  Start-Sleep -Seconds 1
  Remove-Item (Join-Path $pay 'calis.ps1') -Force -ErrorAction SilentlyContinue   # kod/parola iceriyor
  Remove-Item (Join-Path $pay 'devam-sonrasi.ps1') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $sonucD 'bitir.txt') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $pkg 'segnox-agent-1.0.0.exe') -Force -ErrorAction SilentlyContinue
  foreach ($d in $script:gecici) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }  # imza anahtari dahil
  Remove-Item Env:\SEGNOX_UPDATE_DIR, Env:\SEGNOX_UPDATE_KEYS, Env:\SEGNOX_TURN_SECRET, Env:\SEGNOX_TURN_URLS, Env:\SEGNOX_RECORD_DIR -ErrorAction SilentlyContinue
  Say 'Temizlik tamam: sunucu + DB kapatildi, calis.ps1 ve gecici anahtarlar silindi.'
}

function Konuk-Bekle ([string]$faz, [int]$dk) {
  $f = Join-Path $sonucD ("faz-$faz.txt")
  for ($i = 0; $i -lt ($dk * 30); $i++) {
    Sonuc-Guncelle
    if (Test-Path $f) { return $true }
    Start-Sleep -Seconds 2
    if ($i % 45 -eq 44) { Say ("  ... konuk asamasi bekleniyor: $faz (" + [int](($i+1)/30) + " dk)") }
  }
  return $false
}

function Konuk-Sonuc ([int]$dk) {
  $bitis = Join-Path $sonucD 'Bitti.txt'
  $logF  = Join-Path $sonucD 'calis.log'
  for ($i = 0; $i -lt ($dk * 30); $i++) {
    Sonuc-Guncelle
    if (Test-Path $bitis) {
      Say '================ KONUK SONUCU ================'
      if (Test-Path $logF) { Get-Content $logF | ForEach-Object { Write-Host $_ } }
      Say '=============================================='
      return $true
    }
    Start-Sleep -Seconds 2
  }
  Say '  SURE DOLDU - konuk sonucu gondermedi.'
  Say '  Kontrol: konukta bootstrap calisti mi? VM acik mi? HTTP sunucu ayakta mi?'
  Say "  Canli kayit: $sonucD\canli.log"
  return $false
}

# Konuk, sonuclarini HTTP ile POST eder (sonuc.zip). Burada acilir.
function Sonuc-Guncelle {
  $zip = Join-Path $pay 'sonuc.zip'
  if (-not (Test-Path $zip)) { return }
  try {
    $t = (Get-Item $zip).LastWriteTime
    $isaret = Join-Path $sonucD '.sonuc-zip'
    if ((Test-Path $isaret) -and ((Get-Item $isaret).LastWriteTime -ge $t)) { return }
    New-Item -ItemType Directory $sonucD -Force | Out-Null
    $gecici = Join-Path $env:TEMP ('segnox-sonuc-' + [guid]::NewGuid().ToString('N').Substring(0,6))
    New-Item -ItemType Directory $gecici -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $gecici -Force
    # Konuk out klasorunu her dakika yeniden gonderir: eski kosunun Bitti/faz dosyalari bu
    # kosunun sonucu sanilmasin. Yalniz canli.log bu run id'yi dogrulamissa kabul edilir.
    if ($script:runId) {
      $c = Join-Path $gecici 'canli.log'
      if (-not ((Test-Path $c) -and (Select-String -Path $c -SimpleMatch ('run id dogrulandi: ' + $script:runId) -Quiet))) {
        Remove-Item $gecici -Recurse -Force -ErrorAction SilentlyContinue
        Set-Content -Path $isaret -Value (Get-Date).ToString('s')
        return
      }
    }
    Get-ChildItem $gecici -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $sonucD $_.Name) -Force }
    # konuk "=== bitti:" yazdiysa Bitti.txt isaretini host'ta uret
    $log = Join-Path $sonucD 'calis.log'
    if ((Test-Path $log) -and ((Get-Content $log -Tail 3 -ErrorAction SilentlyContinue) -join "`n") -match '=== bitti:') {
      if (-not (Test-Path (Join-Path $sonucD 'Bitti.txt'))) {
        'tamam' | Out-File (Join-Path $sonucD 'Bitti.txt') -Encoding ASCII
      }
    }
    Remove-Item $gecici -Recurse -Force -ErrorAction SilentlyContinue
    Set-Content -Path $isaret -Value (Get-Date).ToString('s')
  } catch { }
}

try {
  # ------------------------------------------------------------ on kontrol
  Adim 'On kontrol'
  New-Item -ItemType Directory $pay -Force | Out-Null
  New-Item -ItemType Directory $sonucD -Force | Out-Null
  if (-not (Test-Path (Join-Path $pay 'bootstrap-http.ps1'))) {
    Say '  HATA: bootstrap-http.ps1 yok. Once konukta bootstrap calistir.'
    Say '        Konuk PowerShell''de: iwr http://192.168.79.1:8081/bootstrap-http.ps1 -OutFile $env:TEMP\bs.ps1; & $env:TEMP\bs.ps1'
    exit 1
  }
  $vmCalisiyor = $null
  if (Test-Path $vmrun) {
    try {
      $liste = if ($VmParola) { & $vmrun -T ws -vp $VmParola list 2>&1 } else { & $vmrun -T ws list 2>&1 }
      $vmCalisiyor = [bool]($liste | Where-Object { [string]$_ -match '\.vmx' })
    } catch { $vmCalisiyor = $null }
  }
  if ($null -eq $vmCalisiyor) { $vmCalisiyor = [bool](Get-Process vmware-vmx -ErrorAction SilentlyContinue) }
  if (-not $vmCalisiyor) {
    Say '  HATA: calisan VM yok (vmrun list bos / vmware-vmx yok). VMware Workstation''de Windows 11 VM''ini ac,'
    Say '        konukta bootstrap''in calistigindan emin ol, sonra tekrar dene.'
    exit 1
  }
  $natIp = (Get-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet8' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Select-Object -First 1).IPAddress
  $lanIp = (Get-NetIPAddress -InterfaceAlias 'Wi-Fi' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Select-Object -First 1).IPAddress
  if ($Senaryo -ne 'hazirlik' -and -not $natIp) {
    Say '  HATA: "VMware Network Adapter VMnet8" bulunamadi - konuk NAT agina ulasilamaz.'; exit 1
  }
  if ($Senaryo -ne 'hazirlik') {
    $dolu = $false
    try { $dolu = ((Invoke-WebRequest 'http://127.0.0.1:8090/healthz' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) } catch {}
    if ($dolu) { Say '  HATA: 127.0.0.1:8080 zaten dolu (baska bir sunucu calisiyor). Ona dokunulmaz; once onu kapat ya da bekle.'; exit 1 }
  }
  Say '  tamam'

  # onceki sonuclari temizle
  foreach ($n in 'Bitti.txt','HATA.txt','calis.log','canli.log','bitir.txt','devam-sonrasi.log') {
    Remove-Item (Join-Path $sonucD $n) -Force -ErrorAction SilentlyContinue }
  Get-ChildItem $sonucD -Filter 'faz-*.txt' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $pay 'calis.ps1') -Force -ErrorAction SilentlyContinue

  # ------------------------------------------------------------ konuk HTTP sunucusu
  # Konuk (HGFS calismiyor) dosyalari ve sonuclarini HTTP ile alir/gonderir.
  Adim 'Konuk dosya sunucusu (HTTP)'
  $script:httpProc = $null
  $pyScript = Join-Path $PSScriptRoot 'host-dosya-sunucu.py'
  $zatenVar = $false
  try { $zatenVar = (Invoke-WebRequest 'http://127.0.0.1:8081/bootstrap-http.ps1' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200 } catch {}
  if ($zatenVar) {
    Say '  8081 zaten acik - mevcut sunucu kullanilacak'
  } else {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { Say '  HATA: python bulunamadi (konuk HTTP sunucusu icin gerekli)'; exit 1 }
    if (-not (Test-Path $pyScript)) { Say "  HATA: $pyScript yok"; exit 1 }
    $script:httpProc = Start-Process -FilePath $py.Source `
      -ArgumentList @("`"$pyScript`"", "`"$pay`"", '8081') -PassThru -NoNewWindow `
      -RedirectStandardOutput (Join-Path $env:TEMP 'segnox-http.out') `
      -RedirectStandardError  (Join-Path $env:TEMP 'segnox-http.err')
    Start-Sleep -Seconds 2
    if ($script:httpProc.HasExited) {
      Say '  HATA: HTTP sunucusu baslamadi'
      Get-Content (Join-Path $env:TEMP 'segnox-http.err') -Tail 5 -ErrorAction SilentlyContinue
      exit 1
    }
    Say ("  http://${natIp}:8081  (PID $($script:httpProc.Id))")
  }

  # ------------------------------------------------------------ hazirlik: sunucu gerekmez
  if ($Senaryo -eq 'hazirlik') {
    $script:runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,4))
    Set-Content -Path (Join-Path $pay 'run-id.txt') -Value $script:runId -Encoding ASCII -NoNewline
    Set-Content -Path (Join-Path $pay 'calis.ps1') -Value (Konuk-Betik 'hazirlik' '' '' '') -Encoding UTF8
    Adim "Konuk bekleniyor (en fazla $BekleDakika dk)"
    [void](Konuk-Sonuc $BekleDakika)
    return
  }

  # ------------------------------------------------------------ gecici arac klasoru
  $arac = Join-Path $env:TEMP 'segnox-vm-arac'
  New-Item -ItemType Directory $arac -Force | Out-Null
  $script:gecici += $arac

  # ------------------------------------------------------------ guncelleme: anahtar + surumler
  if ($Senaryo -eq 'guncelleme') {
    Adim 'Imza anahtari + 1.0.0 / 1.0.1 / bozuk 1.0.2 derleniyor'
    $kdir = Join-Path $env:TEMP ('segnox-vm-anahtar-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory $kdir | Out-Null
    $script:gecici += $kdir          # ozel anahtar repoya/paylasima girmez, sonda silinir
    $relExe = Join-Path $arac 'segnox-release.exe'
    Push-Location $repo
    try {
      & go build -o $relExe ./cmd/segnox-release; if ($LASTEXITCODE -ne 0) { throw 'segnox-release derlenemedi' }
      $keyFile = Join-Path $kdir 'release.key'
      $pub = (@(& $relExe keygen -out $keyFile) | Select-Object -First 1).ToString().Trim()
      if (-not $pub) { throw 'keygen genel anahtar vermedi' }
      Say ("  genel anahtar: " + (Kisa $pub) + " (ozel anahtar gecici klasorde, sonda silinir)")
      $env:CGO_ENABLED = '0'; $env:GOOS = 'windows'; $env:GOARCH = 'amd64'
      New-Item -ItemType Directory $pkg -Force | Out-Null
      & go build -ldflags "-X segnox.com/uzakdestek/internal/agent/update.releaseKeys=$pub -X main.version=1.0.0" -o (Join-Path $pkg 'segnox-agent-1.0.0.exe') ./cmd/segnox-agent
      if ($LASTEXITCODE -ne 0) { throw '1.0.0 derlenemedi' }
      Copy-Item (Join-Path $pkg 'segnox-agent-1.0.0.exe') (Join-Path $pay 'segnox-agent-1.0.0.exe') -Force
      $updDir = Join-Path $arac 'guncelleme'
      New-Item -ItemType Directory $updDir -Force | Out-Null
      $relBin = Join-Path $updDir 'segnox-agent-windows-amd64.exe'
      & go build -ldflags "-X segnox.com/uzakdestek/internal/agent/update.releaseKeys=$pub -X main.version=1.0.1" -o $relBin ./cmd/segnox-agent
      if ($LASTEXITCODE -ne 0) { throw '1.0.1 derlenemedi' }
      # bozuk 1.0.2: acilista cikis kodu 3 ile biten bos program (ayri gecici modul)
      $kirikD = Join-Path $arac 'kirik'
      New-Item -ItemType Directory $kirikD -Force | Out-Null
      Set-Content (Join-Path $kirikD 'go.mod') "module kirik`r`n`r`ngo 1.21`r`n" -Encoding ASCII
      Set-Content (Join-Path $kirikD 'main.go') "package main`r`n`r`nimport `"os`"`r`n`r`nfunc main() { os.Exit(3) }`r`n" -Encoding ASCII
      Push-Location $kirikD
      try { & go build -o (Join-Path $arac 'kirik-1.0.2.exe') . ; if ($LASTEXITCODE -ne 0) { throw 'bozuk 1.0.2 derlenemedi' } } finally { Pop-Location }
    } finally {
      Remove-Item Env:\GOOS, Env:\GOARCH, Env:\CGO_ENABLED -ErrorAction SilentlyContinue
      Pop-Location
    }
    function Surum-Yayinla ([string]$ver) {
      & $relExe manifest -version $ver -dir $updDir | Out-Null; if ($LASTEXITCODE -ne 0) { throw "manifest $ver" }
      & $relExe sign -key $keyFile -in (Join-Path $updDir 'manifest.json') | Out-Null; if ($LASTEXITCODE -ne 0) { throw "imza $ver" }
      & $relExe verify -keys $pub -dir $updDir | Out-Null; if ($LASTEXITCODE -ne 0) { throw "dogrulama $ver" }
    }
    Surum-Yayinla '1.0.1'
    $env:SEGNOX_UPDATE_DIR  = $updDir
    $env:SEGNOX_UPDATE_KEYS = $pub
    Say '  1.0.1 imzali yayinlandi (sunucu SEGNOX_UPDATE_DIR / SEGNOX_UPDATE_KEYS)'
  }

  # ------------------------------------------------------------ veritabani
  Adim 'Veritabani baslatiliyor'
  Set-Location $repo
  $dbOut = Join-Path $env:TEMP 'segnox-vmdb.out'
  $dbErr = Join-Path $env:TEMP 'segnox-vmdb.err'
  Remove-Item $dbOut,$dbErr -ErrorAction SilentlyContinue
  $devdbExe = Join-Path $arac 'segnox-devdb.exe'
  Say '  devdb derleniyor (migration semasi gomulu)...'
  & go build -o $devdbExe ./cmd/segnox-devdb
  if ($LASTEXITCODE -ne 0) { Say 'HATA: devdb derlenemedi'; exit 1 }
  # devdb stdin kapaninca durur: stdin acik tutulur (konsolsuz/zamanlanmis calistirmada da dayanir)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $devdbExe; $psi.Arguments = '-seed'; $psi.WorkingDirectory = $arac
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $script:dbProc = [System.Diagnostics.Process]::Start($psi)
  $errFs = [System.IO.File]::Create($dbErr)
  [void]$script:dbProc.StandardError.BaseStream.CopyToAsync($errFs)
  $cfg = $null
  $okuma = $script:dbProc.StandardOutput.ReadLineAsync()
  for ($i = 0; $i -lt 240 -and -not $cfg; $i++) {
    if ($okuma.Wait(1000)) {
      $line = $okuma.Result
      if ($null -eq $line) { break }
      if ($line -match '"appDsn"') { $cfg = $line | ConvertFrom-Json } else { $okuma = $script:dbProc.StandardOutput.ReadLineAsync() }
    } elseif ($script:dbProc.HasExited) { break }
  }
  if ($cfg) { [void]$script:dbProc.StandardOutput.BaseStream.CopyToAsync([System.IO.Stream]::Null) }
  if (-not $cfg) { Say 'HATA: veritabani baslamadi'; $errFs.Flush(); Get-Content $dbErr -Tail 10; exit 1 }
  $owner = $cfg.tenants[0]
  $ownerMail = $owner.users[0].email
  $ownerPw   = $owner.users[0].password
  Say "  hazir. e-posta: $ownerMail"

  # ------------------------------------------------------------ sunucu
  Adim 'Sunucu baslatiliyor (127.0.0.1:8090; yalniz bu test suresince)'
  $srvExe = Join-Path $arac 'segnox-server.exe'
  & go build -o $srvExe ./cmd/segnox-server
  if ($LASTEXITCODE -ne 0) { Say 'HATA: sunucu derlenemedi'; exit 1 }
  $mailD = Join-Path $arac 'mail'
  New-Item -ItemType Directory $mailD -Force | Out-Null
  $env:SEGNOX_ADDR             = '127.0.0.1:8090'
  $env:SEGNOX_DB_URL           = $cfg.appDsn
  $env:SEGNOX_DATA_KEY         = [Convert]::ToBase64String([byte[]](1..32 | ForEach-Object { Get-Random -Maximum 256 }))
  # Cihaz imzasi sunucu host'unu icerir (K-21): ajan bu URL'i kullaniyor,
  # sunucu da ayni host'u bekliyor. Ikisi ayni olmali.
  $env:SEGNOX_PUBLIC_URL       = "https://${natIp}:8080"
  $env:SEGNOX_COOKIE_SECURE    = 'true'
  $env:SEGNOX_MAIL             = "file:$mailD"
  $env:SEGNOX_TRUSTED_PROXIES  = '127.0.0.1'
  $env:SEGNOX_LOG_LEVEL        = 'debug'
  $env:SEGNOX_RECORD_DIR       = (Join-Path $arac 'kayit')   # oturum kaydi (K-35) denenebilsin
  New-Item -ItemType Directory $env:SEGNOX_RECORD_DIR -Force | Out-Null
  # TURN (K-10): Chrome yerel adresleri mDNS (.local) ile gizler, ajan mDNS cozmez ve
  # konuk guvenlik duvari gelen UDP'yi keser -> STUN/TURN olmadan yol kurulamaz
  # ("Karsi tarafla baglanti kurulamadi"). Gelistirme TURN'u (TCP) iki tarafa relay verir.
  $turnExe = Join-Path $arac 'segnox-devturn.exe'
  & go build -o $turnExe ./cmd/segnox-devturn
  if ($LASTEXITCODE -ne 0) { Say 'HATA: devturn derlenemedi'; exit 1 }
  $env:SEGNOX_TURN_SECRET = -join (1..40 | ForEach-Object { [char](Get-Random -Minimum 97 -Maximum 123) })
  # devturn stdin kapaninca durur: stdin acik tutulur (Temizlik sureci kapatir).
  $tpsi = New-Object System.Diagnostics.ProcessStartInfo
  $tpsi.FileName = $turnExe
  $tpsi.Arguments = "-allow-loopback-peers -tcp ${natIp}:3478 -tcp-any"
  $tpsi.UseShellExecute = $false
  $tpsi.RedirectStandardInput = $true
  $tpsi.RedirectStandardOutput = $true
  $tpsi.RedirectStandardError = $true
  $script:turnProc = [System.Diagnostics.Process]::Start($tpsi)
  [void]$script:turnProc.StandardOutput.BaseStream.CopyToAsync([System.IO.Stream]::Null)
  [void]$script:turnProc.StandardError.BaseStream.CopyToAsync([System.IO.Stream]::Null)
  $turnUp = $false
  for ($i = 0; $i -lt 20 -and -not $turnUp; $i++) {
    Start-Sleep -Milliseconds 500
    $turnUp = [bool](Get-NetTCPConnection -LocalAddress $natIp -LocalPort 3478 -State Listen -ErrorAction SilentlyContinue)
  }
  if (-not $turnUp) { Say 'HATA: devturn ayakta degil'; exit 1 }
  $env:SEGNOX_TURN_URLS = "turn:${natIp}:3478?transport=tcp"
  Say "  TURN (gelistirme, TCP): ${natIp}:3478"
  $logOut = Join-Path $env:TEMP 'segnox-vmserver.out'
  $logErr = Join-Path $env:TEMP 'segnox-vmserver.err'
  Remove-Item $logOut,$logErr -ErrorAction SilentlyContinue
  $script:server = Start-Process -FilePath $srvExe -WorkingDirectory $arac -PassThru -NoNewWindow `
    -RedirectStandardOutput $logOut -RedirectStandardError $logErr
  $up = $false
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 1
    try { if ((Invoke-WebRequest 'http://127.0.0.1:8090/healthz' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { $up = $true; break } } catch {}
  }
  if (-not $up) { Say 'HATA: sunucu ayakta degil'; Get-Content $logErr -Tail 12; exit 1 }
  Say '  sunucu ayakta'

  # Ajan, loopback disindaki sunucu icin duz HTTP'i reddeder (K-21).
  # Bu yuzden TLS sonlandirici proxy kuruyoruz: ajan https:// ile baglanir,
  # konuk kok sertifikayi guvenilir olarak yukler.
  # NOT: host'un API cagrilari da PUBLIC_URL ile ayni https adrese gittigi icin
  # proxy, giris yapmadan ONCE ayaga kalkmali.
  Adim 'TLS proxy (ajan https ile baglansin)'
  $certDir = Join-Path $env:TEMP 'segnox-vm-cert'
  New-Item -ItemType Directory $certDir -Force | Out-Null
  $proxyGo = Join-Path $PSScriptRoot 'vm-tls-proxy.go'
  $script:proxyProc = $null
  $proxyArgs = @("run", "`"$proxyGo`"", '-listen', '8080', '-target', '127.0.0.1:8090', '-ip', $natIp, '-dir', "`"$certDir`"")
  $script:proxyProc = Start-Process -FilePath 'go' -ArgumentList $proxyArgs -PassThru -NoNewWindow `
    -RedirectStandardOutput (Join-Path $env:TEMP 'segnox-proxy.out') `
    -RedirectStandardError  (Join-Path $env:TEMP 'segnox-proxy.err')
  $proxyHazir = $false
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    # curl -k: host kendi CA'sina guvenmiyor (konuk edecek) -> dogrulama kapali
    try {
      $c = & curl.exe -k -s -o NUL -w '%{http_code}' "https://${natIp}:8080/healthz" 2>$null
      if ("$c" -eq '200') { $proxyHazir = $true; break }
    } catch {}
    if ($script:proxyProc.HasExited) { break }
  }
  if (-not $proxyHazir) {
    Say '  HATA: TLS proxy ayaga kalkmadi'
    Get-Content (Join-Path $env:TEMP 'segnox-proxy.err') -Tail 8 -ErrorAction SilentlyContinue
    exit 1
  }
  Say "  https://${natIp}:8080 -> 127.0.0.1:8090 (guvenilen kok: $certDir\ca.pem)"

  # Kok sertifikayi konuga ver (konuk kendi guvenilir koku olarak yukler)
  Copy-Item (Join-Path $certDir 'ca.der') (Join-Path $pay 'ca.der') -Force
  # Host tarayicisi da ayni CA'ya guvenmeli (kullanici deposu - yonetici gerekmez)
  try {
    certutil.exe -user -addstore -f Root (Join-Path $certDir 'ca.der') 2>&1 | Out-Null
    Say '  kok sertifika host tarayicisina da eklendi (kullanici deposu)'
  } catch { }

  # 8080 icin zaten "Segnox test 8080" kurulu (konuk oradan baglaniyor).
  # Yeni kural eklemek yonetici gerektirir; eklenemezse sunucu 127.0.0.1:8090'da kalir.

  $serverUrl = "https://${natIp}:8080"

  # ------------------------------------------------------------ API oturumu + katilim kodu
  Adim 'Katilim kodu uretiliyor'
  $api = "https://${natIp}:8080/api/v1"
  # Test ortami: kendi urettigimiz CA'ya guven (dogrulama kapali - sadece test)
  try {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
  } catch { }
  $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  [void](Invoke-RestMethod -Uri "$api/auth/login" -Method Post `
    -Body (@{ email = $ownerMail; password = $ownerPw } | ConvertTo-Json) -ContentType 'application/json' -WebSession $session)
  $me = Invoke-RestMethod -Uri "$api/auth/me" -WebSession $session
  $tok = Invoke-RestMethod -Uri "$api/enrollment-tokens" -Method Post `
    -Body (@{ name = "VM testi ($Senaryo)"; uses = 3; ttlHours = 2 } | ConvertTo-Json) `
    -ContentType 'application/json' -WebSession $session -Headers @{ 'X-Segnox-CSRF' = $me.csrf }
  Say ("  kod: " + (Kisa $tok.token) + " (kisaltildi; 2 saat / 3 kullanim)")
  Say "  Konsol: https://${natIp}:8080   e-posta: $ownerMail   parola: $ownerPw"

  function Cihaz-Bekle ([int]$dk) {
    for ($i = 0; $i -lt ($dk * 12); $i++) {
      try {
        $r = Invoke-RestMethod -Uri "$api/devices" -WebSession $session
        $liste = if ($r.devices) { @($r.devices) } elseif ($r.items) { @($r.items) } else { @($r) }
        $d = $liste | Where-Object { $_.online } | Select-Object -First 1
        if ($d) { return $d }
        $sonHata = 'cihaz listesi: ' + (@($liste | ForEach-Object { [string]$_.name + ' online=' + [string]$_.online }) -join ', ')
      } catch {
        $sonHata = [string]$_
        try { [void](Invoke-RestMethod -Uri "$api/auth/login" -Method Post -Body (@{ email = $ownerMail; password = $ownerPw } | ConvertTo-Json) -ContentType 'application/json' -WebSession $session) } catch {}
      }
      Start-Sleep -Seconds 5
    }
    Say ("  cihaz bekleme son durum: " + $sonHata)
    return $null
  }
  function Guncelle-Yolla ([string]$id) {
    $me2 = Invoke-RestMethod -Uri "$api/auth/me" -WebSession $session
    Invoke-RestMethod -Uri "$api/devices/$id/update" -Method Post -WebSession $session -Headers @{ 'X-Segnox-CSRF' = $me2.csrf } | Out-Null
  }

  if ($Senaryo -eq 'ortam') {
    Adim 'Ortam hazir (konuk betigi yazilmadi)'
    Say "  Sunucu (NAT): $serverUrl   Wi-Fi: http://${lanIp}:8080"
    Say "  Konsol: $serverUrl   e-posta: $ownerMail   parola: $ownerPw"
    Say "  Konukta: `$env:SEGNOX_ENROLL_TOKEN='<kod>'; segnox-agent.exe /S /SERVER=$serverUrl /NAME=VM   (kod konsoldan yeni uretilir)"
    Kullanici-Bekle ('Kapatmak icin Enter')
    return
  }

  # ------------------------------------------------------------ konuk betigi
  Adim 'Konuk betigi hazirlaniyor'
  New-Item -ItemType Directory $pkg -Force | Out-Null
  if ($Senaryo -ne 'guncelleme') {
    Say '  ajan derleniyor...'
    $env:CGO_ENABLED = '0'; $env:GOOS = 'windows'; $env:GOARCH = 'amd64'
    try { & go build -o (Join-Path $pkg 'segnox-agent.exe') ./cmd/segnox-agent } finally { Remove-Item Env:\GOOS, Env:\GOARCH, Env:\CGO_ENABLED -ErrorAction SilentlyContinue }
Copy-Item (Join-Path $pkg 'segnox-agent.exe') (Join-Path $pay 'segnox-agent.exe') -Force   # konuk HTTP ile indirir
    if ($LASTEXITCODE -ne 0) { Say 'HATA: ajan derlenemedi'; exit 1 }
  }
  $parola = ''
  if ($Senaryo -eq 'devam') {
    $parola = 'Vm-' + [Convert]::ToBase64String([byte[]](1..12 | ForEach-Object { Get-Random -Maximum 256 })).Replace('+','x').Replace('/','y').Replace('=','')
    Set-Content -Path (Join-Path $pay 'devam-sonrasi.ps1') -Value ($devamSonrasi.Replace('\\vmware-host\Shared Folders\segnox-calisma\sonuc', 'C:\segnox-test\out')) -Encoding UTF8
  }
  # ------------------------------------------------------------ konuk betigi hazirlaniyor
  $script:runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,4))
  # Konuk paketi bu ozetle esitler; kurulu ajanin surumu bununla karsilastirilir.
  $ozet = foreach ($f in 'segnox-agent.exe', 'segnox-agent-1.0.0.exe', 'ca.der') {
    $fp = Join-Path $pay $f
    if (Test-Path $fp) { (Get-FileHash $fp -Algorithm SHA256).Hash.ToLower() + '  ' + $f }
  }
  Set-Content -Path (Join-Path $pay 'paket.sha256') -Value $ozet -Encoding ASCII
  $script:ajanSurum = ''
  if ($Senaryo -ne 'guncelleme') {
    $script:ajanSurum = [string](& (Join-Path $pay 'segnox-agent.exe') version 2>&1 | Select-Object -First 1)
    Say "  konuga gidecek ajan: $($script:ajanSurum)"
  }
  Set-Content -Path (Join-Path $pay 'run-id.txt') -Value $script:runId -Encoding ASCII -NoNewline
  Set-Content -Path (Join-Path $pay 'calis.ps1') -Value (Konuk-Betik $Senaryo $tok.token $serverUrl $parola) -Encoding UTF8
  Say "  betik yazildi: $pay\calis.ps1 (sonda silinir; kod/parola yalniz orada)"

  Adim "Konuk kurulumu bekleniyor (en fazla $BekleDakika dk; konuk gorevi 1 dk'da bir bakar)"
  if (-not (Konuk-Bekle 'kurulum' ([Math]::Min($BekleDakika, 10)))) {
    Say '  SURE DOLDU - konuk kurulum asamasina gelmedi (VM acik mi, bootstrap calisti mi?).'
    return
  }
  Say '  konuk kurulumu bitti, cihaz cevrimici bekleniyor...'
  $dev = Cihaz-Bekle 3
  if (-not $dev) { Say '  UYARI: 3 dk icinde cevrimici cihaz yok (ajan sunucuya baglanamadi mi? Guvenlik duvari 8080?)' }
  else { Say ("  cihaz cevrimici: " + $dev.name + " (" + $dev.id + ")") }

  switch ($Senaryo) {
    'servis' { }
    { $_ -in 'siyah','izleyici' } {
      if ($dev) {
        $b = "https://${natIp}:8080/v/?device=$($dev.id)"
        Say ''
        Say "Konsole once giris yap:  https://${natIp}:8080  ($ownerMail / $ownerPw)"
        Say "  BAGLAN (kontrol):  $b"
        Say "  IZLE   (salt gorme): $b&role=view"
        Say 'Konukta cihaz parolasi tanimli degil: baglantiyi konuk kullanicisi cubuktan onaylar.'
        Say 'Gozle kontrol listesi konuk logunda (sonda) da basilacak.'
      }
      Say ''
      Kullanici-Bekle ('Deneme bitince Enter (konuk loglari toplanir, sunucu kapanir)')
      'bitir' | Out-File (Join-Path $sonucD 'bitir.txt') -Encoding ASCII
    }
    'guncelleme' {
      if (-not $dev) { Say '  HATA: cihaz yok, guncelleme sinyali gonderilemez'; break }
      Say '  1) "Guncelle" sinyali (1.0.1) gonderiliyor...'
      Guncelle-Yolla $dev.id
      if (-not (Konuk-Bekle 'guncel' 25)) { Say '  UYARI: 1.0.1 asamasi 25 dk icinde bitmedi (sonuc yine de beklenecek)' }
      else {
        Say '  1.0.1 kuruldu (konuk raporu sonda). Simdi bozuk 1.0.2 yayinlaniyor...'
        Copy-Item (Join-Path $arac 'kirik-1.0.2.exe') $relBin -Force
        Surum-Yayinla '1.0.2'
        $dev2 = Cihaz-Bekle 5
        if ($dev2) { Guncelle-Yolla $dev2.id; Say '  2) bozuk 1.0.2 icin sinyal gonderildi; geri alma bekleniyor (3 yeniden baslatma ya da 10 dk)...' }
        else { Say '  UYARI: 1.0.1 sonrasi cihaz cevrimici degil; 1.0.2 sinyali gonderilemedi' }
      }
    }
    'devam' {
      Say ''
      Say 'K-27 DEVAM DENEMESI (cihaz parolasi tanimli; parola yalniz burada gosterilir):'
      Say "  parola: $parola"
      if ($dev) { Say "  Baglan: https://${natIp}:8080/v/?device=$($dev.id)   (once konsola giris: $ownerMail / $ownerPw)" }
      Say '  1) Parolayla baglan, "Yeniden baslat" -> onay -> VM 10 sn Turkce uyariyla yeniden baslar'
      Say '  2) Tarayici "Cihaz yeniden baslatiliyor" gosterir; acilinca onaysiz devam eder'
      Say '  3) Yeniden baslatma sonrasi konuk kaniti: sonuc\devam-sonrasi.log (otomatik toplanir)'
      Kullanici-Bekle ('VM yeniden basladiktan sonra (ya da vazgectiysen) Enter')
      $dl = Join-Path $sonucD 'devam-sonrasi.log'
      Say '  yeniden baslatma sonrasi kanit bekleniyor (en cok 10 dk)...'
      for ($i = 0; $i -lt 300; $i++) {
        if ((Test-Path $dl) -and (Select-String -Path $dl -Pattern '=== bitti ===' -Quiet)) { break }
        Start-Sleep -Seconds 2
      }
      if (Test-Path $dl) { Get-Content $dl | ForEach-Object { Write-Host "  $_" } }
      else { Say '  devam-sonrasi.log gelmedi (VM yeniden baslamadi mi?).' }
    }
  }

  Adim 'Konuk sonucu'
  [void](Konuk-Sonuc $BekleDakika)
  Say ''
  Say "Konsol: $serverUrl   e-posta: $ownerMail   parola: $ownerPw"
  Say "Sunucu (NAT): $serverUrl   Wi-Fi: http://${lanIp}:8080"
}
finally {
  Temizlik
}



