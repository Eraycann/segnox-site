# Segnox VM hazirlik - HOST'ta calistir (VM KAPALIYKEN)
#
# Ne yapar:
#   1) VM aciksa duzgun kapatir (vmrun stop soft)
#   2) .vmx yedek alir
#   3) Copy-Paste / Drag-Drop / Shared Folder (HGFS) ayarlarini yazar
#   4) Paylasim klasorlerini baglar
#   5) VM'i acar ve IP'sini bekler
#   6) VMware Tools durumunu kontrol eder
#
# Kullanim:  .\vm-prep.ps1
# Not: .vmx yalnizca VM KAPALIYKEN duzenlenir. VMware her kapamada .vmx'i
#       yeniden yazdigindan, acikken yapilan degisiklikler kaybolur.

$ErrorActionPreference = 'Stop'

$vmDir      = 'C:\Users\Erayc\Documents\Virtual Machines\Windows 11 x64'
$vmx        = Join-Path $vmDir 'Windows 11 x64.vmx'
$vmrun      = 'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
$toolsIso   = 'C:\Program Files\VMware\VMware Workstation\windows.iso'
$paylasim   = 'C:\Users\Erayc\Desktop\segnox-site\.tools\vm-paylasim'
$paket      = 'C:\Users\Erayc\Desktop\segnox-site\.tools\vm-paket'
$vmIp       = '192.168.79.129'

function Say  ($s) { Write-Host $s }
function Adim ($s) { Write-Host "`n=== $s ===" -ForegroundColor Cyan }

# ---------------------------------------------------------------- 0) kontrol
if (-not (Test-Path $vmx)) { Say "HATA: .vmx bulunamadi: $vmx"; exit 1 }
if (-not (Test-Path $vmrun)) { Say "HATA: vmrun yok: $vmrun"; exit 1 }

Adim 'VM durumu'
$running = (& $vmrun -T ws list) -join "`n"
Say "  $running"
$isRunning = $running -notmatch 'Total running VMs: 0'

if ($isRunning) {
  Say '  VM acik - duzgun kapatiliyor (vmrun stop soft)...'
  & $vmrun -T ws stop soft $vmx 2>&1 | Out-Null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    $l = (& $vmrun -T ws list) -join "`n"
    if ($l -match 'Total running VMs: 0') { break }
  }
  $l = (& $vmrun -T ws list) -join "`n"
  if ($l -notmatch 'Total running VMs: 0') { Say '  HATA: VM kapanmadi. elle kapat.'; exit 1 }
  Say '  VM kapandi'
}

# ---------------------------------------------------------------- 1) yedek
Adim '.vmx yedekleniyor'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bak   = "$vmx.bak-$stamp"
Copy-Item $vmx $bak -Force
Say "  yedek: $(Split-Path $bak -Leaf)"

# ---------------------------------------------------------------- 2) .vmx
function Set-VmxKey {
  param([string]$Path, [string]$Key, [string]$Value)
  $esc  = [regex]::Escape($Key)
  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($l in [System.IO.File]::ReadAllLines($Path)) { $lines.Add($l) }
  $found = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^\s*$esc\s*=") {
      $lines[$i] = "$Key = `"$Value`""
      $found = $true
    }
  }
  if (-not $found) { $lines.Add("$Key = `"$Value`"") }
  # BOM'suz UTF-8 + CRLF (VMware .vmx formatı)
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($Path, $lines, $enc)
}

Adim '.vmx ayarlari yaziliyor'
New-Item -ItemType Directory -Path $paylasim -Force | Out-Null
New-Item -ItemType Directory -Path $paket -Force | Out-Null

# Paylasim + pano (eski "TRUE" anahtarlari da kalir, ikisi de "izinli" demek)
$ayarlar = @(
  @('isolation.tools.copyPaste',      'TRUE'),
  @('isolation.tools.paste',          'TRUE'),
  @('isolation.tools.dnd',            'TRUE'),
  @('isolation.tools.hgfs',           'TRUE'),
  @('isolation.tools.copyPaste.disable','FALSE'),
  @('isolation.tools.paste.disable',    'FALSE'),
  @('isolation.tools.dnd.disable',      'FALSE'),
  @('isolation.tools.hgfs.disable',     'FALSE'),
  @('tools.remindInstall',              'FALSE'),
  # 0: paket (salt okunur) - 1: calisma klasoru (yazilabilir)
  @('sharedFolder0',                 $paket),
  @('sharedFolder0.guestName',       'segnox-paket'),
  @('sharedFolder0.readAccess',      'TRUE'),
  @('sharedFolder0.writeAccess',     'FALSE'),
  @('sharedFolder0.disabled',        'FALSE'),
  @('sharedFolder1',                 $paylasim),
  @('sharedFolder1.guestName',       'segnox-calisma'),
  @('sharedFolder1.readAccess',      'TRUE'),
  @('sharedFolder1.writeAccess',     'TRUE'),
  @('sharedFolder1.disabled',        'FALSE')
)
foreach ($a in $ayarlar) {
  Set-VmxKey -Path $vmx -Key $a[0] -Value $a[1]
  Say "  $($a[0]) = $($a[1])"
}

# ---------------------------------------------------------------- 3) ac
Adim 'VM aciliyor'
Say "  vmrun start $vmx"
$p = Start-Process -FilePath $vmrun -ArgumentList @('-T','ws','start',"`"$vmx`"") -NoNewWindow -PassThru
$p.WaitForExit(180000) | Out-Null
if ($p.ExitCode -ne 0) {
  Say "  HATA: vmrun start kodu $($p.ExitCode)"
  Say '  VM sifreli ise parola sorulur - VMware penceresinden ac.'
  exit 1
}
Say '  acma komutu gonderildi'

# ---------------------------------------------------------------- 4) IP
Adim 'Konuk IP bekleniyor'
$ok = $false
for ($i = 0; $i -lt 90; $i++) {
  Start-Sleep -Seconds 2
  $ping = Test-Connection -TargetName $vmIp -Count 1 -Quiet -ErrorAction SilentlyContinue
  if ($ping) { $ok = $true; break }
}
if ($ok) { Say "  $vmIp erisilebilir" }
else      { Say "  $vmIp YANIT VERMIYOR (30+ saniye). Konuk aciliyor olabilir." }

# ---------------------------------------------------------------- 5) Tools
Adim 'VMware Tools durumu'
$toolsState = (& $vmrun -T ws checkToolsState $vmx 2>&1) -join ' '
Say "  checkToolsState: $toolsState"
if ($toolsState -notmatch 'running' -and $toolsState -notmatch 'installed') {
  Say '  UYARI: Tools calismiyor gibi. Paylasim klasoru de olmaz.'
  Say '  Cozum: .tools\vm-guest.ps1 ile kur (bkz. vm-tools-kur.ps1)'
}

Say ''
Say '============================================================'
Say ' TAMAM. Simdi .tools\vm-guest.ps1 ile konuga komut gonderebilirsin.'
Say ' Kopyala-yapistir ve surukle-birak icin: konugu yeniden baslat.'
Say '============================================================'
