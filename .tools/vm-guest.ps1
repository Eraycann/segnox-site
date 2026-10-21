# Segnox VM konuk kontrolu - HOST'ta calistir
# Konuga KOMUT YAZMADAN (terminale elle yazmadan) komut gonderir.
# Altyapi: VMware Tools "Guest Operations" (vmrun). Konukta Tools kurulu
# ve kullanici giris yapmis olmali.
#
# Kullanim:
#   .\vm-guest.ps1 status
#   .\vm-guest.ps1 put  <hostDosya> <konukYol>       (dosya gonder)
#   .\vm-guest.ps1 get  <konukYol> <hostDosya>       (dosya al)
#   .\vm-guest.ps1 run  <hostScript.ps1>             (calistir, ciktisi al)
#   .\vm-guest.ps1 screen <hostCikti.png>            (ekran goruntusu)
#   .\vm-guest.ps1 dir  <konukYol>
#
# Kimlik bilgisi: .tools\vm-cred.txt  (gitignore'da)
#   kullanici=...
#   parola=...

$ErrorActionPreference = 'Stop'

$vmrun = 'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
$vmxLong = 'C:\Users\Erayc\Documents\Virtual Machines\Windows 11 x64\Windows 11 x64.vmx'
# vmrun bosluklu yollari boluyor -> 8.3 kisa yol kullanilir
Add-Type -Namespace W32 -Name N -MemberDefinition @'
[DllImport("kernel32.dll", CharSet=CharSet.Auto)]
public static extern int GetShortPathName(string l, System.Text.StringBuilder s, int c);
'@ -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder 260
if ([W32.N]::GetShortPathName($vmxLong, $sb, 260) -gt 0) { $vmx = $sb.ToString() } else { $vmx = $vmxLong }
$credF = 'C:\Users\Erayc\Desktop\segnox-site\.tools\vm-cred.txt'
$outD  = 'C:\Users\Erayc\Desktop\segnox-site\.tools\vm-paylasim'
$konukD = 'C:\segnox-test'

function Say ($s) { Write-Host $s }

# --- kimlik bilgisi ---
if (-not (Test-Path $credF)) {
  Say "HATA: $credF yok. Icine su iki satiri yaz:"
  Say "  kullanici=<konuk Windows kullanici adi>"
  Say "  parola=<konuk parolasi>"
  exit 1
}
$gu = $null; $gp = $null
foreach ($l in Get-Content $credF) {
  if ($l -match '^\s*kullanici\s*=\s*(.+)$') { $gu = $Matches[1].Trim() }
  if ($l -match '^\s*parola\s*=\s*(.+)$')    { $gp = $Matches[1].Trim() }
}
if (-not $gu) { Say "HATA: cred dosyasinda 'kullanici=' yok"; exit 1 }

function Vmrun {
  param([Parameter(ValueFromRemainingArguments=$true)][string[]]$A)
  & $vmrun -T ws -gu $gu -gp $gp @A 2>&1
}

$cmd = if ($args.Count -ge 1) { $args[0] } else { 'status' }
New-Item -ItemType Directory -Path $outD -Force | Out-Null

switch ($cmd) {

  'status' {
    Say '--- VM ---'
    Say ((& $vmrun -T ws list) -join "`n")
    Say '--- Tools ---'
    Say ("  " + ((& $vmrun -T ws checkToolsState $vmx) -join ' '))
    Say '--- Konuk erisimi (klasor listesi) ---'
    $r = Vmrun 'listDirectoryInGuest' $vmx 'C:\' 2>&1
    Say ("  " + ($r -join "`n  "))
  }

  'put' {
    $src = $args[1]; $dst = $args[2]
    if (-not (Test-Path $src)) { Say "HATA: kaynak yok: $src"; exit 1 }
    $r = Vmrun 'copyFileFromHostToGuest' $vmx $src $dst 2>&1
    if ($LASTEXITCODE -ne 0) { Say "HATA: kopyalanamadi: $($r -join ' ')"; exit 1 }
    Say "  gonderildi: $src -> $dst"
  }

  'get' {
    $src = $args[1]; $dst = $args[2]
    $r = Vmrun 'copyFileFromGuestToHost' $vmx $src $dst 2>&1
    if ($LASTEXITCODE -ne 0) { Say "HATA: alinamadi: $($r -join ' ')"; exit 1 }
    Say "  alindi: $src -> $dst"
  }

  'dir' {
    $p = $args[1]
    $r = Vmrun 'listDirectoryInGuest' $vmx $p 2>&1
    Say ($r -join "`n")
  }

  'screen' {
    $dst = if ($args.Count -ge 2) { $args[1] } else { Join-Path $outD 'ekran.png' }
    $r = Vmrun 'captureScreen' $vmx $dst 2>&1
    if ($LASTEXITCODE -ne 0) { Say "HATA: ekran alinamadi: $($r -join ' ')"; exit 1 }
    Say "  ekran goruntusu: $dst"
  }

  'run' {
    $script = $args[1]
    if (-not (Test-Path $script)) { Say "HATA: betik yok: $script"; exit 1 }
    $name = [System.IO.Path]::GetFileName($script)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($name)

    # 1) konukta klasor
    Vmrun 'createDirectoryInGuest' $vmx $konukD | Out-Null
    Vmrun 'createDirectoryInGuest' $vmx "$konukD\out" | Out-Null

    # 2) betigi gonder
    $r = Vmrun 'copyFileFromHostToGuest' $vmx $script "$konukD\$name" 2>&1
    if ($LASTEXITCODE -ne 0) { Say "HATA: betik gonderilemedi: $($r -join ' ')"; exit 1 }

    # 3) sarmalayici .cmd (yonlendirmeyi icinde yapar)
    $cmdFile = Join-Path $env:TEMP "vmrun-$stem.cmd"
    @(
      '@echo off',
      "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$konukD\$name`" > `"$konukD\out\$stem.log`" 2>&1",
      "echo EXIT=%ERRORLEVEL% >> `"$konukD\out\$stem.log`""
    ) | Set-Content -Path $cmdFile -Encoding ASCII
    $r = Vmrun 'copyFileFromHostToGuest' $vmx $cmdFile "$konukD\run.cmd" 2>&1
    if ($LASTEXITCODE -ne 0) { Say "HATA: sarmalayici gonderilemedi: $($r -join ' ')"; exit 1 }

    # 4) calistir (bitene kadar bekler)
    Say "  calistiriliyor: $name"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = Vmrun 'runProgramInGuest' $vmx 'cmd.exe' '/c' "$konukD\run.cmd" 2>&1
    $sw.Stop()
    Say ("  bitti: " + $sw.Elapsed.ToString('mm\:ss') + "  (cikis: " + (($r -join ' ') -replace '\s+',' ') + ")")

    # 5) ciktiyi al
    $log = "$konukD\out\$stem.log"
    $hostLog = Join-Path $outD "$stem.log"
    $r = Vmrun 'copyFileFromGuestToHost' $vmx $log $hostLog 2>&1
    if ($LASTEXITCODE -ne 0) {
      Say "  UYARI: cikti alinamadi (betik belki cok uzun surdu veya konukta bitti)"
      Say "  Konukta: $log"
    } else {
      Say "--- cikti: $hostLog ---"
      Get-Content $hostLog | ForEach-Object { Write-Host "  $_" }
    }
  }

  default {
    Say "Bilinmeyen komut: $cmd"
    Say 'Kullanim: status | put | get | run | dir | screen'
    exit 1
  }
}
