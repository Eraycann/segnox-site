# Segnox VM testi - sunucu tarafi (HOST'ta calistir)
# Kullanim:  .\vm-test.ps1
# Ne yapar: veritabanini + sunucuyu acar, bir katilim kodu uretir,
#           VM'de calistiracagin komutu ekrana basar.

$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\Erayc\Desktop\segnox-uzaktan-erisim'
Set-Location $repo

function Say ($s) { Write-Host $s }
function Adim ($s) { Write-Host "`n=== $s ===" -ForegroundColor Cyan }

# ---------- onceki koslari temizle ----------
Adim 'Eski Segnox surecleri kapatiliyor'
Get-Process -Name 'segnox-agent','segnox-server','segnox-devdb','postgres' -ErrorAction SilentlyContinue |
  ForEach-Object { Say "  $($_.ProcessName) ($($_.Id))"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue |
  ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

# ---------- 1) veritabani ----------
Adim 'Veritabani baslatiliyor'
$dbOut = Join-Path $env:TEMP 'segnox-vmdb.out'
$dbErr = Join-Path $env:TEMP 'segnox-vmdb.err'
Remove-Item $dbOut,$dbErr -ErrorAction SilentlyContinue

$devdbExe = Join-Path $repo 'segnox-devdb.exe'
# Migration'lar go:embed ile ikiliye gomulur. Eski ikili = eski sema =
# "column does not exist" hatasi. HER ZAMAN yeniden derle.
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

# ---------- 2) sunucu ----------
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

# ---------- 3) katilim kodu ----------
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

# ---------- 4) VM icin paket + dosya sunucusu ----------
Adim 'VM paketi hazirlaniyor + dosya sunucusu aciliyor'
$pkg = 'C:\Users\Erayc\Desktop\segnox-site\.tools\vm-paket'
New-Item -ItemType Directory -Path $pkg -Force | Out-Null
Copy-Item (Join-Path $repo 'segnox-agent.exe') $pkg -Force
Copy-Item (Join-Path $repo 'segnox-devdb.exe') $pkg -Force -ErrorAction SilentlyContinue

# VM birbirine ulasabilsin diye iki adres deniyoruz
$natIp = (Get-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet8' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Select-Object -First 1).IPAddress
$lanIp = (Get-NetIPAddress -InterfaceAlias 'Wi-Fi' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Select-Object -First 1).IPAddress

# Kucuk dosya sunucusu: python -m http.server (tek komut, garantili calisir)
$httpJob = Start-Process -FilePath 'python' `
  -ArgumentList @('-m','http.server','8081','--bind','0.0.0.0','--directory',$pkg) `
  -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $env:TEMP 'segnox-files.out') `
  -RedirectStandardError (Join-Path $env:TEMP 'segnox-files.err')
Start-Sleep -Seconds 2
if ($httpJob.HasExited) {
  Say 'HATA: dosya sunucusu acilamadi'
  Get-Content (Join-Path $env:TEMP 'segnox-files.err') -Tail 6 -ErrorAction SilentlyContinue
  exit 1
}
Say "  dosya sunucusu: PID $($httpJob.Id), port 8081"
# Segnox VM testi - sunucu tarafi (HOST'ta calistir)
# Kullanim:  .\vm-test.ps1
# Ne yapar: veritabanini + sunucuyu acar, bir katilim kodu uretir,
#           VM'de calistiracagin komutu ekrana basar.

$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\Erayc\Desktop\segnox-uzaktan-erisim'
Set-Location $repo

function Say ($s) { Write-Host $s }
function Adim ($s) { Write-Host "`n=== $s ===" -ForegroundColor Cyan }

# ---------- onceki koslari temizle ----------
Adim 'Eski Segnox surecleri kapatiliyor'
Get-Process -Name 'segnox-agent','segnox-server','segnox-devdb','postgres' -ErrorAction SilentlyContinue |
  ForEach-Object { Say "  $($_.ProcessName) ($($_.Id))"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue |
  ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

# ---------- 1) veritabani ----------
Adim 'Veritabani baslatiliyor'
$dbOut = Join-Path $env:TEMP 'segnox-vmdb.out'
$dbErr = Join-Path $env:TEMP 'segnox-vmdb.err'
Remove-Item $dbOut,$dbErr -ErrorAction SilentlyContinue

$devdbExe = Join-Path $repo 'segnox-devdb.exe'
# Migration'lar go:embed ile ikiliye gomulur. Eski ikili = eski sema =
# "column does not exist" hatasi. HER ZAMAN yeniden derle.
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

# ---------- 2) sunucu ----------
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

# ---------- 3) katilim kodu ----------
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

# ---------- 4) VM icin paket + dosya sunucusu ----------
Adim 'VM paketi hazirlaniyor + dosya sunucusu aciliyor'
$pkg = 'C:\Users\Erayc\Desktop\segnox-site\.tools\vm-paket'
New-Item -ItemType Directory -Path $pkg -Force | Out-Null
Copy-Item (Join-Path $repo 'segnox-agent.exe') $pkg -Force
Copy-Item (Join-Path $repo 'segnox-devdb.exe') $pkg -Force -ErrorAction SilentlyContinue

# VM birbirine ulasabilsin diye iki adres deniyoruz
$natIp = (Get-NetIPAddress -InterfaceAlias 'VMware Network Adapter VMnet8' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Select-Object -First 1).IPAddress
$lanIp = (Get-NetIPAddress -InterfaceAlias 'Wi-Fi' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Select-Object -First 1).IPAddress

# Kucuk dosya sunucusu: python -m http.server (tek komut, garantili calisir)
$httpJob = Start-Process -FilePath 'python' `
  -ArgumentList @('-m','http.server','8081','--bind','0.0.0.0','--directory',$pkg) `
  -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $env:TEMP 'segnox-files.out') `
  -RedirectStandardError (Join-Path $env:TEMP 'segnox-files.err')
Start-Sleep -Seconds 2
if ($httpJob.HasExited) {
  Say 'HATA: dosya sunucusu acilamadi'
  Get-Content (Join-Path $env:TEMP 'segnox-files.err') -Tail 6 -ErrorAction SilentlyContinue
  exit 1
}
Say "  dosya sunucusu: PID $($httpJob.Id), port 8081"

$setup = @"
`$ErrorActionPreference = 'Stop'
Write-Host '=== Segnox ajan indiriliyor ===' -ForegroundColor Cyan
New-Item -ItemType Directory 'C:\Program Files\Segnox' -Force | Out-Null
Invoke-WebRequest 'http://HOSTIP:8081/segnox-agent.exe' -OutFile 'C:\Program Files\Segnox\segnox-agent.exe'
Write-Host '  indirildi'

Write-Host '=== Servis kuruluyor (sessiz) ===' -ForegroundColor Cyan
`$env:SEGNOX_ENROLL_TOKEN = '$($tok.token)'
& 'C:\Program Files\Segnox\segnox-agent.exe' /S /SERVER='http://HOSTIP:8080' /NAME='VM-Test'
Write-Host "  cikis kodu: `$LASTEXITCODE"

Write-Host '=== Servis durumu ===' -ForegroundColor Cyan
sc qc SegnoxAgent
sc query SegnoxAgent

Write-Host '=== ProgramData izinleri ===' -ForegroundColor Cyan
icacls 'C:\ProgramData\Segnox'
"@
$setup = $setup.Replace('HOSTIP', $natIp)
Set-Content (Join-Path $pkg 'kur.ps1') $setup -Encoding UTF8

Write-Host ''
Write-Host '############################################################' -ForegroundColor Green
Write-Host '#  SUNUCU HAZIR. Simdi VM icinde calistir:              #' -ForegroundColor Green
Write-Host '############################################################' -ForegroundColor Green
Write-Host ''
Write-Host '  VM icinde YONETICI PowerShell ac, sonra su komutu yapistir:'
Write-Host ''
Write-Host '     cd $env:TEMP' -ForegroundColor White
Write-Host '     Invoke-WebRequest "http://HOSTIP:8081/kur.ps1" -OutFile kur.ps1' -ForegroundColor White
Write-Host '     .\kur.ps1' -ForegroundColor White
Write-Host ''
Write-Host '  (HOSTIP yerine sunucu adresini yaz)' -ForegroundColor DarkGray
Write-Host ''
Write-Host '############################################################' -ForegroundColor Green
Write-Host ''
Say "  Parola (bilgisayardan giris):  $($owner.users[0].password)"
Say "  Sunucu adresi:  http://$natIp`:8080   (NAT)  |  http://$lanIp`:8080   (Wi-Fi)"
Say "  Dosya sunucusu: http://$natIp`:8081"
Say "  Sunucu bu pencerede acik kalacak. Bitince Ctrl+C."
Say ''

try { $server.WaitForExit() } finally {
  try { $httpJob.Kill() } catch {}
}
