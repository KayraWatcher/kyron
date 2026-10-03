# GECICI - canli donma izleyici. Olcumden sonra SILINECEK.
# Cihazda kullanici gesture yapar; asagidaki kosullardan biri saglaninca
# kanitlari toplar ve biter.
param([int]$MaxMinutes = 45)

$S = Split-Path -Parent $MyInvocation.MyCommand.Path
$D = "CUFEMVTGNR4L4TU4"
$Port = "35717"
$Auth = "7RlctrTBj1w="
$live = Join-Path $S "frz_live.txt"
$tail = Join-Path $S "frz_tail.txt"
$det  = Join-Path $S "freeze_detected.txt"
$mlog = Join-Path $S "monitor_log.txt"

function M([string]$m) {
  (Get-Date -Format "HH:mm:ss") + " " + $m | Out-File -FilePath $mlog -Append -Encoding UTF8
}

function Dump-Evidence([string]$reason, [string]$tag) {
  M "ESAS: $reason"
  $base = "freeze_$tag"
  adb -s $D shell screencap -p /sdcard/$base.png 2>&1 | Out-Null
  adb -s $D pull /sdcard/$base.png (Join-Path $S "$base.png") 2>&1 | Out-Null

  $frz = @(adb -s $D logcat -d -s flutter:I 2>&1 | Select-String -Pattern "FRZ" |
             ForEach-Object { $_.Line })
  $frz | Out-File (Join-Path $S "freeze_chain.txt") -Encoding UTF8
  M ("FRZ zinciri satir: " + $frz.Count)
  $frz | Select-Object -Last 120 | Out-File (Join-Path $S "freeze_chain_tail.txt") -Encoding UTF8

  adb -s $D logcat -d -s flutter:I 2>&1 |
    Select-String -Pattern "FRZ" -NotMatch | Select-Object -Last 30 |
    ForEach-Object { $_.Line } | Out-File (Join-Path $S "freeze_otherlog.txt") -Encoding UTF8

  M "VM service stack"
  & dart (Join-Path $S "frz_stack.dart") $Port $Auth stack 2>&1 |
    Out-File (Join-Path $S "freeze_stack.txt") -Encoding UTF8

  $p = ("$(adb -s $D shell pidof com.goldapp.gold)").Trim()
  adb -s $D shell "ps -T -p $p" 2>&1 | Out-File (Join-Path $S "freeze_threads.txt") -Encoding UTF8
  if (Test-Path (Join-Path $S "threads_fresh.txt")) {
    $f = @(Get-Content (Join-Path $S "freeze_threads.txt"))
    $r = @(Get-Content (Join-Path $S "threads_fresh.txt"))
    ("taze=" + $r.Count + " donma=" + $f.Count) | Out-File (Join-Path $S "freeze_threads.txt") -Append
    "--- taze'de var, donma aninda yok ---" | Out-File (Join-Path $S "freeze_threads.txt") -Append
    Compare-Object $r $f | Where-Object { $_.SideIndicator -eq "<=" } |
      ForEach-Object { $_.InputObject } | Out-File (Join-Path $S "freeze_threads.txt") -Append
    "--- donma aninda eklenen ---" | Out-File (Join-Path $S "freeze_threads.txt") -Append
    Compare-Object $r $f | Where-Object { $_.SideIndicator -eq "=>" } |
      ForEach-Object { $_.InputObject } | Out-File (Join-Path $S "freeze_threads.txt") -Append
  }

  adb -s $D shell top -H -b -n 3 -d 2 -q -p $p 2>&1 |
    Select-String -Pattern "goldapp" | Out-File (Join-Path $S "freeze_top.txt") -Encoding UTF8

  adb -s $D shell dumpsys input 2>&1 |
    Select-String -Pattern "PendingEvent|WaitQueue|FocusedWindow|dispatchingTimeout" |
    ForEach-Object { $_.Line } | Out-File (Join-Path $S "freeze_input.txt") -Encoding UTF8

  adb -s $D shell dumpsys meminfo com.goldapp.gold 2>&1 |
    Select-String -Pattern "TOTAL PSS|Native Heap|Java Heap" |
    ForEach-Object { $_.Line } | Out-File (Join-Path $S "freeze_mem.txt") -Encoding UTF8

  $layer = "SurfaceView - com.goldapp.gold/com.goldapp.gold.MainActivity#0"
  $lat = adb -s $D shell "dumpsys SurfaceFlinger --latency '$layer'" 2>&1
  $lat | Out-File (Join-Path $S "freeze_latency.txt") -Encoding UTF8
  M "latency satir sayisi: $($lat.Count)"

  adb -s $D logcat -d 2>&1 | Out-File (Join-Path $S "freeze_logcat.txt") -Encoding UTF8

  @(
    "NEDEN: $reason",
    "zaman: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "FRZ satir: $($frz.Count)"
  ) | Out-File $det -Encoding UTF8
  M "KANITLAR TAMAMLANDI"
}

Remove-Item $live, $tail, $det, $mlog -Force -ErrorAction SilentlyContinue
M "izleyici basladi (max $MaxMinutes dk)"

$seen = New-Object 'System.Collections.Generic.HashSet[string]'
$lastActivity = Get-Date
$lastActivityLog = Get-Date
$crossOpen = $false
$crossStuckSince = $null
$downAt = $null
$downRecognized = $false
$deadline = (Get-Date).AddMinutes($MaxMinutes)

while ((Get-Date) -lt $deadline) {
  $lines = @(adb -s $D logcat -d -s flutter:I 2>&1 | Select-String -Pattern "FRZ" |
               ForEach-Object { $_.Line })
  $new = @()
  foreach ($t in $lines) { if ($seen.Add($t)) { $new += $t } }

  if ($new.Count -gt 0) {
    $new | Out-File -FilePath $live -Append -Encoding UTF8
    $new | Select-Object -Last 8 | Out-File -FilePath $tail -Encoding UTF8
    $lastActivity = Get-Date

    foreach ($t in $new) {
      if ($t -match '->true') { $crossOpen = $true; $crossStuckSince = $null; M "IMLEC ACILDI: $t" }
      if ($t -match '->false') { $crossOpen = $false; $crossStuckSince = $null; M "IMLEC KAPANDI" }
      if ($t -match 'ptrDown') { $downAt = Get-Date; $downRecognized = $false; M "PDOWN: $t" }
      if ($t -match 'longStart|scaleStart|tapUp|onDoubleTap') { $downRecognized = $true }
      if ($t -match 'ptrUp|ptrCancel') {
        M "PUP: $t"
        if ($crossOpen) { $crossStuckSince = Get-Date } else { $downAt = $null }
      }
      if ($t -match 'longEnd|longCancel') { $downAt = $null; $downRecognized = $true }
    }
  }

  $now = Get-Date

  # KOSUL 1: ptrUp alindi ama imlec hala acik kaldi (5 sn'den uzun)
  if ($crossStuckSince -and (($now - $crossStuckSince).TotalSeconds -gt 5)) {
    Dump-Evidence "ptrUp gelmesine ragmen imlec kapandi $([math]::Round(($now - $crossStuckSince).TotalSeconds,1)) sn kapali kalmadi" "stuck_crosshair"
    break
  }

  # KOSUL 2: ptrDown alindi ama 4 sn icinde hicbir gesture tanimlanmadi
  if ($downAt -and -not $downRecognized -and (($now - $downAt).TotalSeconds -gt 4)) {
    Dump-Evidence "ptrDown alindi ama longStart/scaleStart/tapUp hic gelmedi ($([math]::Round(($now - $downAt).TotalSeconds,1)) sn)" "gesture_not_recognized"
    break
  }

  # KOSUL 3: son 2 dakikada etkilesim vardi, simdi 20 sn'dir hic FRZ yok
  if (($now - $lastActivity).TotalSeconds -gt 20 -and
      ($lastActivity - $lastActivityLog).TotalSeconds -lt 60 -and
      ($now - $lastActivityLog).TotalSeconds -gt 20) {
    M "YAVAS UYARI: FRZ akisi 20 sn durdu"
    $lastActivityLog = $now
  }

  Start-Sleep -Milliseconds 1500
}
M "izleyici bitti"
