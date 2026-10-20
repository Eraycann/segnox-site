# Segnox VM testi - HOST tarafi
#
# Ne yapar:
#   1) Veritabanini + sunucuyu acar (0.0.0.0:8080)
#   2) Katilim kodu uretir
#   3) Konukta calisacak betigi paylasim klasorune yazar
#   4) Konukta SYSTEM zamanlanmis gorev (1 dk) betigi alip calistirir
#   5) Sonucu bekler ve ekrana basar
#
# Kullanim:
#   .\vm-test.ps1                -> servis testi (varsayilan)
#   .\vm-test.ps1 -Senaryo ortam -> sadece ortami hazirlar
#
# ONCE: konukta bir kez bootstrap calistirilmis olmali (bkz. vm-paylasim\bootstrap.ps1)

param(
  [ValidateSet('servis','ortam','devam')] [string]$Senaryo = 'servis',
  [int]$BekleDakika = 4
)

$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\Erayc\Desktop\segnox-uzaktan-erisim'
$pay  = 'C:\Users\Erayc\Desktop\segnox-site\.tools\vm-paylasim'
$pkg  = 'C:\Users\Erayc\Desktop\segnox-site\.tools\vm-paket'
Set-Location $repo

function Say ($s) { Write-Host $s }
function Adim ($s) { Write-Host "`n=== $s ===" -ForegroundColor Cyan }

# ---------------------------------------------------------------- 0) hazirlik
Adim 'Paylasim klasoru kontrolu'
New-Item -ItemType Directory $pay -Force | Out-Null
New-Item -ItemType Directory (Join-Path $pay 'sonuc') -Force | Out-Null
Copy-Item (Join-Path $pay 'poller.ps1') $pay -Force -ErrorAction SilentlyContinue

if (-not (Test-Path (Join-Path $pay 'bootstrap.ps1'))) {
  Say '  HATA: bootstrap.ps1 yok. Once konukta bootstrap calistir.'
  exit 1
}

# onceki sonuclari temizle
Remove-Item (Join-Path $pay 'sonuc\Bitti.txt')  -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $pay 'sonuc\calis.log')  -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $pay 'sonuc\bootstrap.txt') -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 1) veritabani
Adim 'Veritabani baslatiliyor'
$dbOut = Join-Path $env:TEMP 'segnox-vmdb.out'
$dbErr = Join-Path $env:TEMP 'segnox-vmdb.err'
Remove-Item $dbOut,$dbErr -ErrorAction SilentlyContinue

$devdbExe = Join-Path $repo 'segnox-devdb.exe'
$needBuild = $true
if (Test-Path $devdbExe) {
  $exeTime = (Get-Item $devdbExe).LastWriteTime
  $newestMig = Get-ChildItem (Join-Path $repo 'internal\store\migrations') -Filter *.sql |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($newestMig -and $exeTime -gt $newestMig.LastWriteTime) { $needBuild = $false }
}
if ($needBuild) {
  Say '  devdb yeniden derleniyor (migration semasi gomulu)...'
  & go build -o $devdbExe ./cmd/segnox-devdb
  if ($LASTEXITCODE -ne 0) { Say 'HATA: devdb derlenemedi'; exit 1 }
}
$dbProc = Start-Process -FilePath $devdbExe -ArgumentList @('-seed') -WorkingDirectory $repo `
  -PassThru -NoNewWindow -RedirectStandardOutput $dbOut -RedirectStandardError $dbErr

$cfg = $null
for ($i = 0; $i -lt 240; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Path $dbOut) {
    $line = Get-Content $dbOut -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '"appDsn"' } | Select-Object -First 1
    if ($line) { $cfg = $line | ConvertFrom-Json; break }
  }
  if ($dbProc.HasExited) { break }
}
if (-not $cfg) { Say 'HATA: veritabani baslamadi'; Get-Content $dbErr -Tail 10; exit 1 }
$owner = $cfg.tenants[0]
Say "  hazir. e-posta: $($owner.users[0].email)"

# ---------------------------------------------------------------- 2) sunucu
Adim 'Sunucu baslatiliyor (0.0.0.0:8080)'
$env:SEGNOX_ADDR             = '0.0.0.0:8080'
$env:SEGNOX_DB_URL            = $cfg.appDsn
$env:SEGNOX_DATA_KEY          = 'zwYp1v+wCLJfEcgAFNNLco+qEGNUwUjvGMGMzSUn1xU='
$env:SEGNOX_PUBLIC_URL        = 'http://127.0.0.1:8080'
$env:SEGNOX_COOKIE_SECURE     = 'false'
$env:SEGNOX_MAIL              = 'file:./data/mail'
$env:SEGNOX_TRUSTED_PROXIES   = '127.0.0.1'
$env:SEGNOX_LOG_LEVEL         = 'debug'

$logOut = Join-Path $env:TEMP 'segnox-vmserver.out'
Remove-Item $logOut -ErrorAction SilentlyContinue
$server = Start-Process -FilePath 'go' -ArgumentList @('run','./cmd/segnox-server') `
  -WorkingDirectory $repo -PassThru -NoNewWindow -RedirectStandardOutput $logOut `
  -RedirectStandardError (Join-Path $env:TEMP 'segnox-vmserver.err')

$up = $false
for ($i = 0; $i -lt 90; $i++) {
  Start-Sleep -Seconds 1
  try { if ((Invoke-WebRequest 'http://127.0.0.1:8080/healthz' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { $up = $true; break } } catch {}
}
if (-not $up) { Say 'HATA: sunucu ayakta degil'; Get-Content (Join-Path $env:TEMP 'segnox-vmserver.err') -Tail 12; exit 1 }
Say '  sunucu ayakta'

# ---------------------------------------------------------------- 3) katilim kodu
Adim 'Katilim kodu uretiliyor'
$api = 'http://127.0.0.1:8080/api/v1'
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$login = Invoke-RestMethod -Uri "$api/auth/login" -Method Post `
  -Body (@{ email = $owner.users[0].email; password = $owner.users[0].password } | ConvertTo-Json) `
  -ContentType 'application/json' -WebSession $session
$me = Invoke-RestMethod -Uri "$api/auth/me" -WebSession $session
$tok = Invoke-RestMethod -Uri "$api/enrollment-tokens" -Method Post `
  -Body (@{ name = 'VM testi'; uses = 5; ttlHours = 48 } | ConvertTo-Json) `
  -ContentType 'application/json' -WebSession $session -Headers @{ 'X-Segnox-CSRF' = $me.csrf }
Say "  kod: $($tok.token)"

# ---------------------------------------------------------------- 4) konuk betigi
Adim 'Konuk betigi hazirlaniyor'
$natIp = (Get-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet8' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Select-Object -First 1).IPAddress
$lanIp = (Get-NetIPAddress -InterfaceAlias 'Wi-Fi' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Select-Object -First 1).IPAddress
$serverUrl = "http://${natIp}:8080"

# ajan ikilisi konuga paylasim klasorunden okunacak
New-Item -ItemType Directory $pkg -Force | Out-Null
if (-not (Test-Path (Join-Path $repo 'segnox-agent.exe'))) {
  Say '  ajan derleniyor...'
  & go build -o (Join-Path $repo 'segnox-agent.exe') ./cmd/segnox-agent
  if ($LASTEXITCODE -ne 0) { Say 'HATA: ajan derlenemedi'; exit 1 }
}
Copy-Item (Join-Path $repo 'segnox-agent.exe') $pkg -Force
Copy-Item (Join-Path $repo 'segnox-agent.exe') $pay -Force
Say "  ajan hazir (paket + calisma klasoru)"

$guest = @"
`$ErrorActionPreference = 'Continue'
function Y (`$m) { Write-Output ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), `$m) }

Y '=== KONUK: basliyor (SYSTEM) ==='
Y ("kullanici: " + [Security.Principal.WindowsIdentity]::GetCurrent().Name)

# --- 0) Windows Update kapali: test sirasinda kendini yeniden baslatmasin ---
foreach (`$s in 'wuauserv','UsoSvc','WaaSMedicSvc') {
  try { Stop-Service `$s -Force -ErrorAction SilentlyContinue
        Set-Service  `$s -StartupType Disabled -ErrorAction SilentlyContinue
        Y ("servis durduruldu/disable: " + `$s) } catch { Y ("servis dokunulamadi: " + `$s) }
}

# --- 1) ajani paylasimdan al ---
`$src = '\\vmware-host\Shared Folders\segnox-paket\segnox-agent.exe'
`$dst = 'C:\segnox-test\segnox-agent.exe'
New-Item -ItemType Directory 'C:\segnox-test' -Force | Out-Null
if (Test-Path `$src) { Copy-Item `$src `$dst -Force; Y 'ajan kopyalandi' }
else { Y 'HATA: ajan paylasimda bulunamadi'; exit 1 }

# --- 2) servisi kur ---
Y 'servis kuruluyor (sessiz)...'
`$p = Start-Process -FilePath `$dst -ArgumentList @('/S','/TOKEN=$($tok.token)','/SERVER=$serverUrl','/NAME=VM-Test') -Wait -PassThru
Y ("servis kurulum cikis kodu: " + `$p.ExitCode)

# --- 3) dogrula ---
Y '--- dogrulama ---'
`$svc = Get-Service -Name 'SegnoxAgent' -ErrorAction SilentlyContinue
if (`$svc) { Y ("servis durumu: " + `$svc.Status) } else { Y 'HATA: servis yok' }

`$proc = Get-Process -Name 'segnox-agent' -ErrorAction SilentlyContinue -IncludeUserName
foreach (`$pr in `$proc) { Y ("surec: pid=" + `$pr.Id + " sahibi=" + `$pr.UserName) }
if (-not `$proc) { Y 'HATA: ajan sureci yok' }

Y '--- ProgramData izinleri (yalnizca SY/BA/Administrators olmali) ---'
`$acl = icacls 'C:\ProgramData\Segnox' 2>&1
`$acl | ForEach-Object { Y (`$_) }

Y '--- ajan logu (son 20 satir) ---'
`$logDir = 'C:\ProgramData\Segnox\logs'
if (Test-Path `$logDir) {
  Get-ChildItem `$logDir -Filter *.log -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object {
      Y ("log dosyasi: " + `$_.FullName)
      Get-Content `$_.FullName -Tail 20 | ForEach-Object { Y (`$_) } }
} else { Y ("log klasoru yok: " + `$logDir) }

Y '--- servis yapilandirmasi ---'
(sc qc SegnoxAgent 2>&1) | ForEach-Object { Y (`$_) }
Y '=== KONUK: bitti ==='
"@

Set-Content -Path (Join-Path $pay 'calis.ps1') -Value $guest -Encoding UTF8
Say "  betik yazildi: $pay\calis.ps1"

# ---------------------------------------------------------------- 5) bekle
Adim "Konuk bekleniyor (en fazla $BekleDakika dk)"
$bitis = Join-Path $pay 'sonuc\Bitti.txt'
$logF  = Join-Path $pay 'sonuc\calis.log'
$found = $false
for ($i = 0; $i -lt ($BekleDakika * 60); $i++) {
  Start-Sleep -Seconds 2
  if (Test-Path $bitis) { $found = $true; break }
  if ($i % 15 -eq 0) { Say ("  ... bekleniyor (" + [int]($i/60) + " dk)") }
}

if (-not $found) {
  Say '  SURE DOLDU - konuk sonucu gondermedi.'
  Say '  Kontrol: konukta paylasim klasoru gorunuyor mu? bootstrap calisti mi?'
  Say '  Konukta: \\vmware-host\Shared Folders\segnox-calisma\sonuc'
} else {
  Say ''
  Say '================ KONUK SONUCU ================' -ForegroundColor Green
  if (Test-Path $logF) { Get-Content $logF | ForEach-Object { Write-Host $_ } }
  Say '===============================================' -ForegroundColor Green
}

Say ''
Say "Parola (bilgisayardan giris):  $($owner.users[0].password)"
Say "Sunucu:  http://$natIp`:8080  (NAT)  |  http://$lanIp`:8080  (Wi-Fi)"
Say "Konuktan:  http://$natIp`:8080"
Say 'Sunucu bu pencerede acik kalacak. Bitince Ctrl+C.'

try { $server.WaitForExit() } finally {
  try { $dbProc.Kill() } catch {}
}
