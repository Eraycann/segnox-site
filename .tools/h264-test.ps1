# Segnox H.264 gercek ekran testi - tek komut.
# Kullanim:  .\h264-test.ps1
# Ne yapar: devdb + sunucuyu arka planda baslatir, ajani on planda calistirir,
# tarayicida acacagin adresi ve giris bilgisini yazdirir.

$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\Erayc\Desktop\segnox-uzaktan-erisim'
Set-Location $repo

function Say ($s) { Write-Host $s }
function Adim ($s) { Write-Host "`n=== $s ===" -ForegroundColor Cyan }

# ---------- onceki koslari temizle ----------
# YALNIZCA segnox sureclerini kapat. Claude Code veya baska bir islem
# calisiyorsa ona dokunma.
Adim 'Eski Segnox surecleri kapatiliyor'
Get-Process -Name 'segnox-agent','segnox-server','segnox-devdb' -ErrorAction SilentlyContinue |
  ForEach-Object { Say "  $($_.ProcessName) ($($_.Id))"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

# 8080 doluysa once onu bosalt (onceki bir testten kalmis olabilir)
$portBusy = (Test-NetConnection -ComputerName 127.0.0.1 -Port 8080 -WarningAction SilentlyContinue -InformationLevel Quiet)
if ($portBusy) {
  Say '  8080 dolu, eski sunucu araniyor...'
  Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 2
}

# ---------- 1) veritabani ----------
Adim 'Veritabani baslatiliyor (birkac saniye)'
$dbOut = Join-Path $env:TEMP 'segnox-devdb.out'
$dbErr = Join-Path $env:TEMP 'segnox-devdb.err'
Remove-Item $dbOut,$dbErr -ErrorAction SilentlyContinue

# go run her seferinde yeniden deriyordu (90 sn+). Onceden derle.
$devdbExe = Join-Path $repo 'segnox-devdb.exe'
if (-not (Test-Path $devdbExe) -or (Get-Item $devdbExe).LastWriteTime -lt (Get-Item (Join-Path $repo 'cmd\segnox-devdb\main.go')).LastWriteTime) {
  Say '  devdb derleniyor...'
  & go build -o $devdbExe ./cmd/segnox-devdb
}
$dbProc = Start-Process -FilePath $devdbExe `
  -ArgumentList @('-seed') `
  -WorkingDirectory $repo -PassThru -NoNewWindow `
  -RedirectStandardOutput $dbOut -RedirectStandardError $dbErr

$json = $null
for ($i = 0; $i -lt 240; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Path $dbOut) {
    $line = Get-Content $dbOut -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '"appDsn"' } | Select-Object -First 1
    if ($line) { $json = $line; break }
  }
  if ($dbProc.HasExited) { break }
}
$cfg = $null
if ($json) { $cfg = $json | ConvertFrom-Json }
if (-not $cfg) {
  Say 'HATA: veritabani baslamadi.'
  Get-Content $dbErr -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Say "  $_" }
  exit 1
}
Say '  veritabani hazir'

# devdb, stdin kapandiginda kapanir. Interaktif olmayan bir ortamda (uzaktan
# calistirilan / yonlendirilen kabuk) bu olur ve sunucu "baglanti reddedildi"
# ile cok daha belirsiz bir hataya duser. Erken yakala.
Start-Sleep -Seconds 3
if ($dbProc.HasExited) {
  Say 'HATA: veritabani sureci kapandi (stdin kapali gorunuyor).'
  Say 'Bu betigi etkilesim bir PowerShell penceresinde calistirmalisin.'
  exit 1
}
$owner = $cfg.tenants[0]
Say "  giris e-posta: $($owner.users[0].email)"

# ---------- 2) sunucu ----------
Adim 'Sunucu baslatiliyor'

# Yerel aga da ac: telefonun ayni Wi-Fi'dan baglanabilsin.
$lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.InterfaceAlias -notmatch 'VMware|Loopback|WSL|Radmin' -and
                 $_.IPAddress -notmatch '^(127|169\.254|172\.(1[6-9]|2[0-9]|3[01]))' } |
  Sort-Object InterfaceAlias | Select-Object -First 1).IPAddress
if (-not $lanIp) { Say 'HATA: Wi-Fi/IP bulunamadi'; exit 1 }

$env:SEGNOX_ADDR             = '0.0.0.0:8080'
$env:SEGNOX_DB_URL            = $cfg.appDsn
$env:SEGNOX_DATA_KEY          = 'zwYp1v+wCLJfEcgAFNNLco+qEGNUwUjvGMGMzSUn1xU='
# Sunucu disaridan http:// kabul etmez (K-21). Bu yuzden genel adres
# localhost kalir, telefonun Origin'i SEGNOX_ORIGINS ile ayrica izin alir.
$env:SEGNOX_PUBLIC_URL        = 'http://127.0.0.1:8080'
$env:SEGNOX_ORIGINS           = "$lanIp`:8080"
$env:SEGNOX_COOKIE_SECURE     = 'false'
$env:SEGNOX_MAIL              = 'file:./data/mail'
$env:SEGNOX_TRUSTED_PROXIES   = '127.0.0.1'

$logOut = Join-Path $env:TEMP 'segnox-server.out'
Remove-Item $logOut -ErrorAction SilentlyContinue
$server = Start-Process -FilePath 'go' `
  -ArgumentList @('run','./cmd/segnox-server') `
  -WorkingDirectory $repo -PassThru -NoNewWindow `
  -RedirectStandardOutput $logOut -RedirectStandardError (Join-Path $env:TEMP 'segnox-server.err')

$up = $false
for ($i = 0; $i -lt 60; $i++) {
  Start-Sleep -Seconds 1
  try {
    $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/healthz' -UseBasicParsing -TimeoutSec 2
    if ($r.StatusCode -eq 200) { $up = $true; break }
  } catch { }
}
if (-not $up) {
  Say 'HATA: sunucu ayakta degil.'
  Get-Content (Join-Path $env:TEMP 'segnox-server.err') -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Say "  $_" }
  exit 1
}
Say '  sunucu ayakta (healthz 200)'

Write-Host ''
Write-Host '############################################################' -ForegroundColor Green
Write-Host '#  ONEMLI: Telefondan baglan, bilgisayardan DEGIL.         #' -ForegroundColor Yellow
Write-Host '#  Aksi halde fare imleci ayni ekrana bakar, test olmaz.  #' -ForegroundColor Yellow
Write-Host '############################################################' -ForegroundColor Green
Write-Host ''
Write-Host '  TELEFONDA ac :' -ForegroundColor Green
Write-Host "     http://$lanIp`:8080" -ForegroundColor White
Write-Host ''
Write-Host '  Bilgisayarda ac :' -ForegroundColor DarkGray
Write-Host '     http://127.0.0.1:8080'
Write-Host ''
Write-Host "  e-posta : $($owner.users[0].email)" -ForegroundColor White
Write-Host "  parola  : $($owner.users[0].password)" -ForegroundColor White
Write-Host ''
Write-Host '  Baglanti kodu ekrana yazilacak.' -ForegroundColor White
Write-Host '############################################################' -ForegroundColor Green

# ---------- 3) ajan ----------
Adim 'Ajan derleniyor'
$env:CGO_ENABLED = '0'
go build -o segnox-agent.exe ./cmd/segnox-agent
if (-not (Test-Path .\segnox-agent.exe)) { Say 'HATA: ajan derlenmedi'; exit 1 }
Say "  derlendi ($([math]::Round((Get-Item .\segnox-agent.exe).Length/1MB,1)) MB)"

# ---------- 4) ajan kayit olsun: API ile katilim kodu uret ----------
Adim 'Katilim kodu uretiliyor'
$api = 'http://127.0.0.1:8080/api/v1'
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

$loginBody = @{ email = $owner.users[0].email; password = $owner.users[0].password } | ConvertTo-Json
try {
  $login = Invoke-RestMethod -Uri "$api/auth/login" -Method Post -Body $loginBody -ContentType 'application/json' `
    -WebSession $session -ErrorAction Stop
  if ($login.mfaRequired) { Say 'HATA: bu seed hesabi 2FA istiyor'; exit 1 }
  # CSRF belirteci login yanitinda degil, /auth/me icinde gelir.
  $me = Invoke-RestMethod -Uri "$api/auth/me" -WebSession $session -ErrorAction Stop
  $csrf = $me.csrf
  Say '  giris yapildi'
} catch {
  Say "HATA: giris basarisiz - $($_.Exception.Message)"
  exit 1
}

# uses ve ttlHours zorunlu: sunucu 1..1000 ve 1..720 bekliyor.
$tokBody = @{ name = 'H264 testi'; uses = 1; ttlHours = 24 } | ConvertTo-Json
try {
  $tok = Invoke-RestMethod -Uri "$api/enrollment-tokens" -Method Post -Body $tokBody `
    -ContentType 'application/json' -WebSession $session -Headers @{ 'X-Segnox-CSRF' = $csrf } -ErrorAction Stop
  Say "  kod: $($tok.token)"
} catch {
  Say "HATA: katilim kodu alinamadi - $($_.ErrorDetails.Message)"
  exit 1
}

# ---------- 5) ajan on planda ----------
# -VideoMod parametresi: auto (H.264 varsa) veya tiles (JPEG karsilastirma).
$videoMod = if ($args.Count -ge 1) { $args[0] } else { 'auto' }
if ($videoMod -notin @('auto','tiles')) { $videoMod = 'auto' }

Adim "Ajan calisiyor - video kipi: $videoMod"
Say '  Kip: auto (H.264 varsa kullanir, yoksa JPEG karoya duser)'
Say '  tiles = JPEG karsilastirma (imlec cizimi farki icin)'
Say '  Kapatmak icin Ctrl+C'
Say ''

$env:SEGNOX_VIDEO = $videoMod
$env:SEGNOX_ENROLL_TOKEN = $tok.token
& .\segnox-agent.exe run -server ws://127.0.0.1:8080/ws/agent

# ---------- temizlik ----------
Adim 'Bitti'
Get-Process -Name 'segnox-agent','segnox-server','segnox-devdb' -ErrorAction SilentlyContinue |
  ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Say '  butun surecler kapatildi'