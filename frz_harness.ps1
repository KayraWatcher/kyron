# GECICI - donma teshisi harness v2. Olcumden sonra SILINECEK.
param([int]$MaxRounds = 6)

$S = Split-Path -Parent $MyInvocation.MyCommand.Path
$D = "CUFEMVTGNR4L4TU4"
$log = Join-Path $S "harness_log.txt"
$Port = "35717"
$Auth = "7RlctrTBj1w="

function Log([string]$m) {
  $m | Out-File -FilePath $log -Append -Encoding UTF8
  Write-Output $m
}

function Cap([string]$n) {
  $f = Join-Path $S "$n.png"
  for ($t = 0; $t -lt 3; $t++) {
    adb -s $D shell screencap -p "/sdcard/$n.png" 2>&1 | Out-Null
    adb -s $D pull "/sdcard/$n.png" $f 2>&1 | Out-Null
    if (Test-Path $f) { return (Get-FileHash $f).Hash }
    Start-Sleep -Milliseconds 400
  }
  return ""
}

function Dump-Evidence([int]$round, [string]$reason) {
  Log "########## FREEZE - KANITLAR (round $round) - $reason ##########"
  adb -s $D shell screencap -p /sdcard/frozen2.png 2>&1 | Out-Null
  adb -s $D pull /sdcard/frozen2.png (Join-Path $S "frozen2.png") 2>&1 | Out-Null

  Log "===== FRZ zinciri (son 100) ====="
  $frz = adb -s $D logcat -d -s flutter:I 2>&1 | Select-String -Pattern "FRZ"
  $lines = @($frz | ForEach-Object { $_.Line })
  $lines | Select-Object -Last 100 | ForEach-Object { Log $_ }
  $lines | ForEach-Object { $_ } | Out-File (Join-Path $S "frz_chain.txt") -Encoding UTF8

  Log "===== FRZ disi flutter log (son 25) ====="
  adb -s $D logcat -d -s flutter:I 2>&1 | Select-String -Pattern "FRZ" -NotMatch |
    Select-Object -Last 25 | ForEach-Object { Log $_.Line }

  Log "===== VM service stack ====="
  if ($Port -ne "PORT") {
    & dart (Join-Path $S "frz_stack.dart") $Port $Auth stack 2>&1 | ForEach-Object { Log "$_" }
  } else { Log "port bilinmiyor" }

  Log "===== threadler (taze ile karsilastirma) ====="
  $p = ("$(adb -s $D shell pidof com.goldapp.gold)").Trim()
  adb -s $D shell "ps -T -p $p" 2>&1 | Out-File (Join-Path $S "threads_frozen.txt") -Encoding UTF8
  $f = @(Get-Content (Join-Path $S "threads_frozen.txt"))
  $r = @(Get-Content (Join-Path $S "threads_fresh.txt"))
  Log ("taze=" + $r.Count + " donma=" + $f.Count)
  Log "--- taze'de var, donma aninda yok ---"
  Compare-Object $r $f | Where-Object { $_.SideIndicator -eq "<=" } | ForEach-Object { Log $_.InputObject }
  Log "--- donma aninda eklenen ---"
  Compare-Object $r $f | Where-Object { $_.SideIndicator -eq "=>" } | ForEach-Object { Log $_.InputObject }

  Log "===== cpu (top -H, 2 ornek) ====="
  adb -s $D shell top -H -b -n 2 -d 2 -q -p $p 2>&1 | Select-String -Pattern "goldapp" |
    Select-Object -Last 16 | ForEach-Object { Log $_.Line }

  Log "===== input dispatch ====="
  adb -s $D shell dumpsys input 2>&1 |
    Select-String -Pattern "PendingEvent|WaitQueue: <full|FocusedWindow" | Select-Object -First 10 |
    ForEach-Object { Log $_.Line }

  Log "===== mem ====="
  adb -s $D shell dumpsys meminfo com.goldapp.gold 2>&1 |
    Select-String -Pattern "TOTAL PSS|Native Heap" | ForEach-Object { Log $_.Line }

  Log "===== FRZ zinciri toplam adet ====="
  Log ("FRZ satir sayisi: " + $lines.Count)
}

if (Test-Path $log) { Remove-Item $log -Force }
Log "harness v2 basliyor (max $MaxRounds round)"
adb -s $D logcat -c

$dragStress = 'input motionevent DOWN 300 1400; sleep 1; i=0; while [ $i -lt 15 ]; do input motionevent MOVE 830 1400; input motionevent MOVE 300 1400; i=$((i+1)); done; input motionevent UP 300 1400'
$dragCheck = 'input motionevent DOWN 300 1400; sleep 1.2; input motionevent MOVE 700 1400; sleep 5; input motionevent MOVE 300 1400; sleep 5; input motionevent UP 300 1400'

for ($r = 1; $r -le $MaxRounds; $r++) {
  Log "---- round $r : 20 hizli pan ----"
  for ($j = 0; $j -lt 20; $j++) {
    $e = adb -s $D shell input swipe 300 1400 830 1400 60 2>&1 | Out-String
    if ($e -match "Exception") { Log ("  [pan " + $j + " ENJEKSIYON HATASI]") }
  }

  Log "---- round $r : hizli imlec surukleme stresi ----"
  $p1 = Start-Process -FilePath "adb" -ArgumentList @("-s", $D, "shell", $dragStress) -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 8
  try { Wait-Process -Id $p1.Id -Timeout 30 -ErrorAction Stop } catch {}
  if (-not $p1.HasExited) { Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue }

  Log "---- round $r : kontrol testi (700 -> 300) ----"
  $p2 = Start-Process -FilePath "adb" -ArgumentList @("-s", $D, "shell", $dragCheck) -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 3.5
  $h1 = Cap ("d" + $r + "_1")
  Start-Sleep -Seconds 5.5
  $h2 = Cap ("d" + $r + "_2")
  try { Wait-Process -Id $p2.Id -Timeout 15 -ErrorAction Stop } catch {}
  if (-not $p2.HasExited) { Stop-Process -Id $p2.Id -Force -ErrorAction SilentlyContinue }

  if ($h1 -eq "" -or $h2 -eq "") {
    Log "  [uyari] ekran goruntusu alinamadi"
    continue
  }
  $same = ($h1 -eq $h2)
  Log ("  S1=" + $h1.Substring(0, 10) + " S2=" + $h2.Substring(0, 10) + " " + $(if ($same) { "AYNI -> FREEZE" } else { "farkli -> canli" }))

  Log "  [round FRZ son 15]"
  adb -s $D logcat -d -s flutter:I 2>&1 | Select-String -Pattern "FRZ" | Select-Object -Last 15 |
    ForEach-Object { Log ("    " + $_.Line) }

  if ($same) {
    Dump-Evidence $r "imlec konumu degismiyor"
    Log "########## FREEZE YAKALANDI ##########"
    exit 0
  }
  Log "  [round tamam - ekran goruntuleri siliniyor]"
  Remove-Item (Join-Path $S ("d" + $r + "_1.png")), (Join-Path $S ("d" + $r + "_2.png")) -Force -ErrorAction SilentlyContinue
}
Log "harness bitti - freeze yakalanamadi"
