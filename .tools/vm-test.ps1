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
function Kur ($kaynak, $tok, $sunucu, $ad) {
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
  $p = Start-Process -FilePath $dst -ArgumentList @('/S', "/SERVER=$sunucu", "/NAME=$ad") -Wait -PassThru
  Remove-Item Env:\SEGNOX_ENROLL_TOKEN -ErrorAction SilentlyContinue
  Y ("kurulum cikis kodu: " + $p.ExitCode)
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
Y ("=== KONUK basliyor (@@SENARYO@@) kullanici: " + [Security.Principal.WindowsIdentity]::GetCurrent().Name + " ===")
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
if ($ok) { Dogrula }
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
  Where-Object { $_ -match 'reboot|restart|resum|session|connected|enrolled' } | Select-Object -Last 25 |
  ForEach-Object { Y ("  " + $_) }
Y '=== bitti ==='
schtasks.exe /delete /tn SegnoxVMDevam /f 2>&1 | Out-Null
Remove-Item 'C:\segnox-test\devam-sonrasi.ps1' -Force -ErrorAction SilentlyContinue
'@

function Konuk-Betik ([string]$ad, [string]$tok, [string]$sunucu, [string]$parola) {
  $b = $konukOnsoz.Replace('@@SENARYO@@', $ad) + "`r`n" + $konukGovde[$ad] + "`r`n" + $konukSon
  return $b.Replace('@@TOKEN@@', $tok).Replace('@@SUNUCU@@', $sunucu).Replace('@@PAROLA@@', $parola)
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
$script:dbProc = $null; $script:server = $null; $script:gecici = @()

function Surec-Kapat ($p) {
  try { if ($p -and -not $p.HasExited) { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null } } catch {}
}

function Temizlik {
  Surec-Kapat $script:server
  try { if ($script:dbProc) { $script:dbProc.StandardInput.Close() } } catch {}   # devdb stdin EOF -> kendi postgres'ini kapatir
  Start-Sleep -Seconds 3
  Surec-Kapat $script:dbProc
  Start-Sleep -Seconds 1
  Remove-Item (Join-Path $pay 'calis.ps1') -Force -ErrorAction SilentlyContinue   # kod/parola iceriyor
  Remove-Item (Join-Path $pay 'devam-sonrasi.ps1') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $sonucD 'bitir.txt') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $pkg 'segnox-agent-1.0.0.exe') -Force -ErrorAction SilentlyContinue
  foreach ($d in $script:gecici) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }  # imza anahtari dahil
  Remove-Item Env:\SEGNOX_UPDATE_DIR, Env:\SEGNOX_UPDATE_KEYS -ErrorAction SilentlyContinue
  Say 'Temizlik tamam: sunucu + DB kapatildi, calis.ps1 ve gecici anahtarlar silindi.'
}

function Konuk-Bekle ([string]$faz, [int]$dk) {
  $f = Join-Path $sonucD ("faz-$faz.txt")
  for ($i = 0; $i -lt ($dk * 30); $i++) {
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
    if (Test-Path $bitis) {
      Say '================ KONUK SONUCU ================'
      if (Test-Path $logF) { Get-Content $logF | ForEach-Object { Write-Host $_ } }
      Say '=============================================='
      return $true
    }
    Start-Sleep -Seconds 2
  }
  Say '  SURE DOLDU - konuk sonucu gondermedi.'
  Say '  Kontrol: konukta paylasim klasoru gorunuyor mu? bootstrap calisti mi? VM acik mi?'
  Say "  Canli kayit: $sonucD\canli.log"
  return $false
}

try {
  # ------------------------------------------------------------ on kontrol
  Adim 'On kontrol'
  New-Item -ItemType Directory $pay -Force | Out-Null
  New-Item -ItemType Directory $sonucD -Force | Out-Null
  if (-not (Test-Path (Join-Path $pay 'bootstrap.ps1'))) {
    Say '  HATA: bootstrap.ps1 yok. Once konukta bootstrap calistir.'; exit 1
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
    try { $dolu = ((Invoke-WebRequest 'http://127.0.0.1:8080/healthz' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) } catch {}
    if ($dolu) { Say '  HATA: 127.0.0.1:8080 zaten dolu (baska bir sunucu calisiyor). Ona dokunulmaz; once onu kapat ya da bekle.'; exit 1 }
  }
  Say '  tamam'

  # onceki sonuclari temizle
  foreach ($n in 'Bitti.txt','HATA.txt','calis.log','canli.log','bitir.txt','devam-sonrasi.log') {
    Remove-Item (Join-Path $sonucD $n) -Force -ErrorAction SilentlyContinue }
  Get-ChildItem $sonucD -Filter 'faz-*.txt' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $pay 'calis.ps1') -Force -ErrorAction SilentlyContinue

  # ------------------------------------------------------------ hazirlik: sunucu gerekmez
  if ($Senaryo -eq 'hazirlik') {
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
  Adim 'Sunucu baslatiliyor (0.0.0.0:8080; yalniz bu test suresince)'
  $srvExe = Join-Path $arac 'segnox-server.exe'
  & go build -o $srvExe ./cmd/segnox-server
  if ($LASTEXITCODE -ne 0) { Say 'HATA: sunucu derlenemedi'; exit 1 }
  $mailD = Join-Path $arac 'mail'
  New-Item -ItemType Directory $mailD -Force | Out-Null
  $env:SEGNOX_ADDR             = '0.0.0.0:8080'
  $env:SEGNOX_DB_URL           = $cfg.appDsn
  $env:SEGNOX_DATA_KEY         = [Convert]::ToBase64String([byte[]](1..32 | ForEach-Object { Get-Random -Maximum 256 }))
  $env:SEGNOX_PUBLIC_URL       = 'http://127.0.0.1:8080'
  $env:SEGNOX_COOKIE_SECURE    = 'false'
  $env:SEGNOX_MAIL             = "file:$mailD"
  $env:SEGNOX_TRUSTED_PROXIES  = '127.0.0.1'
  $env:SEGNOX_LOG_LEVEL        = 'debug'
  $logOut = Join-Path $env:TEMP 'segnox-vmserver.out'
  $logErr = Join-Path $env:TEMP 'segnox-vmserver.err'
  Remove-Item $logOut,$logErr -ErrorAction SilentlyContinue
  $script:server = Start-Process -FilePath $srvExe -WorkingDirectory $arac -PassThru -NoNewWindow `
    -RedirectStandardOutput $logOut -RedirectStandardError $logErr
  $up = $false
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 1
    try { if ((Invoke-WebRequest 'http://127.0.0.1:8080/healthz' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { $up = $true; break } } catch {}
  }
  if (-not $up) { Say 'HATA: sunucu ayakta degil'; Get-Content $logErr -Tail 12; exit 1 }
  Say '  sunucu ayakta'

  # ------------------------------------------------------------ API oturumu + katilim kodu
  Adim 'Katilim kodu uretiliyor'
  $api = 'http://127.0.0.1:8080/api/v1'
  $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  [void](Invoke-RestMethod -Uri "$api/auth/login" -Method Post `
    -Body (@{ email = $ownerMail; password = $ownerPw } | ConvertTo-Json) -ContentType 'application/json' -WebSession $session)
  $me = Invoke-RestMethod -Uri "$api/auth/me" -WebSession $session
  $tok = Invoke-RestMethod -Uri "$api/enrollment-tokens" -Method Post `
    -Body (@{ name = "VM testi ($Senaryo)"; uses = 3; ttlHours = 2 } | ConvertTo-Json) `
    -ContentType 'application/json' -WebSession $session -Headers @{ 'X-Segnox-CSRF' = $me.csrf }
  Say ("  kod: " + (Kisa $tok.token) + " (kisaltildi; 2 saat / 3 kullanim)")
  $serverUrl = "http://${natIp}:8080"

  function Cihaz-Bekle ([int]$dk) {
    for ($i = 0; $i -lt ($dk * 12); $i++) {
      try {
        $r = Invoke-RestMethod -Uri "$api/devices" -WebSession $session
        $liste = if ($r.devices) { @($r.devices) } elseif ($r.items) { @($r.items) } else { @($r) }
        $d = $liste | Where-Object { $_.online } | Select-Object -First 1
        if ($d) { return $d }
      } catch {}
      Start-Sleep -Seconds 5
    }
    return $null
  }
  function Guncelle-Yolla ([string]$id) {
    $me2 = Invoke-RestMethod -Uri "$api/auth/me" -WebSession $session
    Invoke-RestMethod -Uri "$api/devices/$id/update" -Method Post -WebSession $session -Headers @{ 'X-Segnox-CSRF' = $me2.csrf } | Out-Null
  }

  if ($Senaryo -eq 'ortam') {
    Adim 'Ortam hazir (konuk betigi yazilmadi)'
    Say "  Sunucu (NAT): $serverUrl   Wi-Fi: http://${lanIp}:8080"
    Say "  Konsol: http://127.0.0.1:8080   e-posta: $ownerMail   parola: $ownerPw"
    Say "  Konukta: `$env:SEGNOX_ENROLL_TOKEN='<kod>'; segnox-agent.exe /S /SERVER=$serverUrl /NAME=VM   (kod konsoldan yeni uretilir)"
    [void](Read-Host 'Kapatmak icin Enter')
    return
  }

  # ------------------------------------------------------------ konuk betigi
  Adim 'Konuk betigi hazirlaniyor'
  New-Item -ItemType Directory $pkg -Force | Out-Null
  if ($Senaryo -ne 'guncelleme') {
    Say '  ajan derleniyor...'
    $env:CGO_ENABLED = '0'; $env:GOOS = 'windows'; $env:GOARCH = 'amd64'
    try { & go build -o (Join-Path $pkg 'segnox-agent.exe') ./cmd/segnox-agent } finally { Remove-Item Env:\GOOS, Env:\GOARCH, Env:\CGO_ENABLED -ErrorAction SilentlyContinue }
    if ($LASTEXITCODE -ne 0) { Say 'HATA: ajan derlenemedi'; exit 1 }
  }
  $parola = ''
  if ($Senaryo -eq 'devam') {
    $parola = 'Vm-' + [Convert]::ToBase64String([byte[]](1..12 | ForEach-Object { Get-Random -Maximum 256 })).Replace('+','x').Replace('/','y').Replace('=','')
    Set-Content -Path (Join-Path $pay 'devam-sonrasi.ps1') -Value $devamSonrasi -Encoding UTF8
  }
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
        $b = "http://127.0.0.1:8080/v/?device=$($dev.id)"
        Say ''
        Say "Konsole once giris yap:  http://127.0.0.1:8080  ($ownerMail / $ownerPw)"
        Say "  BAGLAN (kontrol):  $b"
        Say "  IZLE   (salt gorme): $b&role=view"
        Say 'Konukta cihaz parolasi tanimli degil: baglantiyi konuk kullanicisi cubuktan onaylar.'
        Say 'Gozle kontrol listesi konuk logunda (sonda) da basilacak.'
      }
      Say ''
      [void](Read-Host 'Deneme bitince Enter (konuk loglari toplanir, sunucu kapanir)')
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
      if ($dev) { Say "  Baglan: http://127.0.0.1:8080/v/?device=$($dev.id)   (once konsola giris: $ownerMail / $ownerPw)" }
      Say '  1) Parolayla baglan, "Yeniden baslat" -> onay -> VM 10 sn Turkce uyariyla yeniden baslar'
      Say '  2) Tarayici "Cihaz yeniden baslatiliyor" gosterir; acilinca onaysiz devam eder'
      Say '  3) Yeniden baslatma sonrasi konuk kaniti: sonuc\devam-sonrasi.log (otomatik toplanir)'
      [void](Read-Host 'VM yeniden basladiktan sonra (ya da vazgectiysen) Enter')
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
  Say "Konsol: http://127.0.0.1:8080   e-posta: $ownerMail   parola: $ownerPw"
  Say "Sunucu (NAT): $serverUrl   Wi-Fi: http://${lanIp}:8080"
}
finally {
  Temizlik
}
