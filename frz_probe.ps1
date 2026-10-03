# GECICI - donma teshisi icin objektif kanit araci. Olcumden sonra SILINECEK.
$S = Split-Path -Parent $MyInvocation.MyCommand.Path
$D = "CUFEMVTGNR4L4TU4"

Add-Type -AssemblyName System.Drawing

function Shot([string]$name) {
  $p = Join-Path $S "$name.png"
  Remove-Item $p -Force -ErrorAction SilentlyContinue
  adb -s $D shell screencap -p /sdcard/$name.png 2>&1 | Out-Null
  adb -s $D pull /sdcard/$name.png $p 2>&1 | Out-Null
  return $p
}

# Iki screenshot'i kucultup piksel bazinda karsilastirir.
# Donen deger: farkli piksel sayisi.
function Diff([string]$a, [string]$b) {
  if (-not (Test-Path $a) -or -not (Test-Path $b)) { return -1 }
  $ia = [System.Drawing.Image]::FromFile($a)
  $ib = [System.Drawing.Image]::FromFile($b)
  $w = 135; $h = 300
  $ba = New-Object System.Drawing.Bitmap $w, $h
  $bb = New-Object System.Drawing.Bitmap $w, $h
  $ga = [System.Drawing.Graphics]::FromImage($ba)
  $gb = [System.Drawing.Graphics]::FromImage($bb)
  $ga.InterpolationMode = 'NearestNeighbor'
  $gb.InterpolationMode = 'NearestNeighbor'
  $ga.DrawImage($ia, 0, 0, $w, $h)
  $gb.DrawImage($ib, 0, 0, $w, $h)
  $n = 0
  for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
      $ca = $ba.GetPixel($x, $y); $cb = $bb.GetPixel($x, $y)
      $d = [math]::Abs($ca.R - $cb.R) + [math]::Abs($ca.G - $cb.G) + [math]::Abs($ca.B - $cb.B)
      if ($d -gt 30) { $n++ }
    }
  }
  $ga.Dispose(); $gb.Dispose(); $ba.Dispose(); $bb.Dispose()
  $ia.Dispose(); $ib.Dispose()
  return $n
}

function FrzCount {
  return @(adb -s $D logcat -d 2>&1 | Select-String -Pattern "FRZ").Count
}

function Out([string]$m) {
  $m | Out-File -FilePath (Join-Path $S "probe_log.txt") -Append -Encoding UTF8
  Write-Output $m
}

Remove-Item (Join-Path $S "probe_log.txt") -Force -ErrorAction SilentlyContinue

# --- gezinme: Ana Sayfa -> Piyasalar -> BIST 30 ---
adb -s $D shell input tap 107 2200; Start-Sleep -Seconds 2
adb -s $D shell input tap 323 2200; Start-Sleep -Seconds 2
adb -s $D shell input tap 540 1051; Start-Sleep -Seconds 6

$base = FrzCount
Out "temel FRZ sayisi: $base"

$s0 = Shot "p0"
Out "p0 alindi"

# --- TEST A: chart uzerinde long press + surukleme ---
adb -s $D shell "input motionevent DOWN 540 1700; sleep 0.8; input motionevent MOVE 570 1700; input motionevent MOVE 610 1700; input motionevent MOVE 650 1700; input motionevent UP 650 1700"
Start-Sleep -Seconds 2
$s1 = Shot "p1"
$d1 = Diff $s0 $s1
$f1 = FrzCount
Out "A) longpress+surukleme: gorsel fark piksel=$d1  FRZ delta=$($f1 - $base)"

# --- TEST B: hizli pan (swipe) ---
$s2pre = $s1
adb -s $D shell "input swipe 800 1700 300 1700 400"
Start-Sleep -Seconds 2
$s2 = Shot "p2"
$d2 = Diff $s2pre $s2
$f2 = FrzCount
Out "B) hizli pan:          gorsel fark piksel=$d2  FRZ delta=$($f2 - $f1)"

# --- TEST C: tek dokunma (tap) ---
adb -s $D shell input tap 540 1700
Start-Sleep -Seconds 2
$s3 = Shot "p3"
$d3 = Diff $s2 $s3
$f3 = FrzCount
Out "C) tek dokunma:        gorsel fark piksel=$d3  FRZ delta=$($f3 - $f2)"

# --- TEST D: interval degisimi (5 dk) ---
adb -s $D shell input tap 295 986
Start-Sleep -Seconds 4
$s4 = Shot "p4"
$d4 = Diff $s3 $s4
$f4 = FrzCount
Out "D) interval 5 dk:      gorsel fark piksel=$d4  FRZ delta=$($f4 - $f3)"

# --- TEST E: interval degisiminden SONRA hemen tekrar long press ---
adb -s $D shell "input motionevent DOWN 540 1700; sleep 0.9; input motionevent MOVE 580 1700; input motionevent MOVE 640 1700; input motionevent UP 640 1700"
Start-Sleep -Seconds 2
$s5 = Shot "p5"
$d5 = Diff $s4 $s5
$f5 = FrzCount
Out "E) interval+longpress: gorsel fark piksel=$d5  FRZ delta=$($f5 - $f4)"

# --- TEST F: uzerine cliplenen butonlar calisiyor mu? (Geri butonu) ---
adb -s $D shell input tap 77 167
Start-Sleep -Seconds 3
$s6 = Shot "p6"
$d6 = Diff $s5 $s6
$f6 = FrzCount
Out "F) Geri butonu:        gorsel fark piksel=$d6  FRZ delta=$($f6 - $f5)"

Out "TOPLAM FRZ: $f6 (temel $base)"
Out "FRZ zinciri (son 40):"
adb -s $D logcat -d -s flutter:I 2>&1 | Select-String -Pattern "FRZ" | Select-Object -Last 40 |
  ForEach-Object { Out ("  " + $_.Line) }

Out "NON-FRZ flutter loglari (son 30):"
adb -s $D logcat -d -s flutter:* 2>&1 | Select-String -Pattern "FRZ" -NotMatch |
  Select-Object -Last 30 | ForEach-Object { Out ("  " + $_.Line) }
